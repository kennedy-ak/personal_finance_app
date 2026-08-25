import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/category_icons.dart';
import '../../../core/constants.dart';
import '../../../core/supabase_client.dart';
import '../domain/category.dart';

class CategoryRepository {
  Future<List<Category>> list() async {
    final rows = await supabase
        .from('categories')
        .select()
        .order('sort_order')
        .order('name');
    return (rows as List)
        .map((r) => Category.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  Future<Category> create({
    required String name,
    required CategoryKind kind,
    String? icon,
    int sortOrder = 100,
  }) async {
    final userId = supabase.auth.currentUser!.id;
    final row = await supabase
        .from('categories')
        .insert({
          'user_id': userId,
          'name': name,
          'kind': kind.value,
          'icon': icon,
          'sort_order': sortOrder,
        })
        .select()
        .single();
    return Category.fromJson(row);
  }

  /// Renames the category *and* every transaction wearing the old label.
  ///
  /// Done in the database so reports never catch the halfway state where the
  /// same spending is split across two spellings.
  Future<void> rename(String id, String newName) async {
    await supabase.rpc('rename_category', params: {
      'p_id': id,
      'p_new_name': newName,
    });
  }

  Future<void> setIcon(String id, String? icon) async {
    await supabase.from('categories').update({'icon': icon}).eq('id', id);
  }

  /// Takes a category out of the pickers without touching the ledger.
  Future<void> setHidden(String id, bool hidden) async {
    await supabase.from('categories').update({'is_hidden': hidden}).eq('id', id);
  }

  /// How many transactions currently carry this category's label.
  Future<int> usageCount(String id) async {
    final n = await supabase.rpc('category_usage_count', params: {'p_id': id});
    return (n as num?)?.toInt() ?? 0;
  }

  /// Removes the category from the list. Transactions keep their label — the
  /// column is free text — so nothing disappears from history or reports.
  Future<void> delete(String id) async {
    await supabase.from('categories').delete().eq('id', id);
  }

  /// Puts the seeded defaults back for anyone who deleted more than they meant
  /// to. Existing rows are left alone.
  Future<void> restoreDefaults() async {
    final userId = supabase.auth.currentUser!.id;
    await supabase.rpc('seed_default_categories', params: {'p_user': userId});
  }
}

/// Whether a failure is "the categories table does not exist yet".
///
/// Worth singling out because it is not a bug the user can do anything about
/// by retrying: PostgREST answers PGRST205 until migration 0007 has been run
/// against the project, and reads quietly fall back to the built-in list, so
/// the first sign of it is a save that fails for no visible reason.
bool isCategoriesTableMissing(Object error) {
  final s = error.toString();
  return s.contains('PGRST205') || s.contains('public.categories');
}

const String kCategoriesSetupHint =
    'Categories are not set up on the server yet. Run '
    '0007_custom_categories.sql in the Supabase SQL editor, then try again.';

final categoryRepositoryProvider = Provider((_) => CategoryRepository());

final categoriesRefreshProvider = StateProvider<int>((_) => 0);

/// Every category the user has, hidden ones included. Manage-screen fodder.
final allCategoriesProvider = FutureProvider<List<Category>>((ref) async {
  ref.watch(categoriesRefreshProvider);
  return ref.watch(categoryRepositoryProvider).list();
});

/// Keeps [iconForCategory] in step with the user's own icons.
///
/// Deliberately its own provider rather than a side effect inside
/// [allCategoriesProvider]: the list is the natural seam to override in a test
/// or a preview, and burying the registration in the body means every override
/// silently loses it. Watched once at the app root, so every screen that draws
/// a category glyph gets the right one without threading a ref down to it.
final categoryIconSyncProvider = Provider<void>((ref) {
  final cats = ref.watch(allCategoriesProvider).value ?? const <Category>[];
  registerCategoryIcons({
    for (final c in cats)
      if (c.icon != null) c.name: c.icon!,
  });
});

/// What the pickers offer: nothing hidden, in the user's own order.
///
/// Falls back to the old constants only when there is nothing at all to show —
/// the list is still loading, or migration 0007 has not been run against this
/// project. Someone who has deliberately hidden every category gets an empty
/// picker, because quietly resurrecting the list they just cleared would be
/// the app arguing with them.
List<String> _names(List<Category> all, CategoryKind kind, List<String> fallback) {
  final ofKind = all.where((c) => c.kind == kind);
  if (ofKind.isEmpty) return fallback;
  return ofKind.where((c) => !c.isHidden).map((c) => c.name).toList();
}

final expenseCategoryNamesProvider = Provider<List<String>>((ref) {
  final all = ref.watch(allCategoriesProvider).value ?? const <Category>[];
  return _names(all, CategoryKind.expense, kExpenseCategories);
});

final incomeCategoryNamesProvider = Provider<List<String>>((ref) {
  final all = ref.watch(allCategoriesProvider).value ?? const <Category>[];
  return _names(all, CategoryKind.income, kIncomeCategories);
});

void bumpCategories(WidgetRef ref) =>
    ref.read(categoriesRefreshProvider.notifier).state++;
