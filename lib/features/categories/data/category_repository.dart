import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api_client.dart';
import '../../../core/category_icons.dart';
import '../../../core/constants.dart';
import '../domain/category.dart';

class CategoryRepository {
  Future<List<Category>> list() async {
    final rows = await api.get('/categories');
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
    final row = await api.post('/categories', body: {
      'name': name,
      'kind': kind.value,
      'icon': icon,
      'sort_order': sortOrder,
    });
    return Category.fromJson(row as Map<String, dynamic>);
  }

  /// Renames the category *and* every transaction wearing the old label.
  ///
  /// Done on the server so reports never catch the halfway state where the
  /// same spending is split across two spellings.
  Future<void> rename(String id, String newName) async {
    await api.post('/categories/$id/rename', body: {'new_name': newName});
  }

  Future<void> setIcon(String id, String? icon) async {
    await api.patch('/categories/$id', body: {'icon': icon});
  }

  /// Takes a category out of the pickers without touching the ledger.
  Future<void> setHidden(String id, bool hidden) async {
    await api.patch('/categories/$id', body: {'is_hidden': hidden});
  }

  /// How many transactions currently carry this category's label.
  Future<int> usageCount(String id) async {
    final res = await api.get('/categories/$id/usage');
    return ((res as Map)['count'] as num?)?.toInt() ?? 0;
  }

  /// Removes the category from the list. Transactions keep their label — the
  /// column is free text — so nothing disappears from history or reports.
  Future<void> delete(String id) async {
    await api.delete('/categories/$id');
  }

  /// Puts the seeded defaults back for anyone who deleted more than they meant
  /// to. Existing rows are left alone.
  Future<void> restoreDefaults() async {
    await api.post('/categories/restore-defaults');
  }
}

/// With the FastAPI backend the categories table is created on boot, so a
/// "table missing" failure cannot happen anymore. Kept because the category
/// screens still branch on it; it now simply never matches.
bool isCategoriesTableMissing(Object error) => false;

const String kCategoriesSetupHint =
    'Categories are not available on the server right now. Try again.';

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
/// Falls back to the old constants only when there is nothing at all to show.
/// Someone who has deliberately hidden every category gets an empty picker,
/// because quietly resurrecting the list they just cleared would be the app
/// arguing with them.
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
