import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_icons.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';
import 'category_editor_sheet.dart';

/// Where the user shapes the list the pickers offer.
///
/// Hiding is the default way out rather than deleting, because a category with
/// three years of transactions under it is still the right label for those
/// transactions — it just should not be suggested any more.
class CategoriesScreen extends ConsumerStatefulWidget {
  const CategoriesScreen({super.key});

  @override
  ConsumerState<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends ConsumerState<CategoriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  CategoryKind get _kind =>
      _tabs.index == 1 ? CategoryKind.income : CategoryKind.expense;

  Future<void> _add() async {
    final made = await CategoryEditorSheet.show(context, kind: _kind);
    if (made != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"$made" added'),
          backgroundColor: AppColors.income,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allCategoriesProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categories'),
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}),
          tabs: const [
            Tab(text: 'Spending'),
            Tab(text: 'Income'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'restore') {
                await ref.read(categoryRepositoryProvider).restoreDefaults();
                bumpCategories(ref);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'restore',
                child: Text('Restore the default list'),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('New category'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => _LoadError(error: e),
        data: (all) => TabBarView(
          controller: _tabs,
          children: [
            _CategoryList(
              categories:
                  all.where((c) => c.kind == CategoryKind.expense).toList(),
              kind: CategoryKind.expense,
            ),
            _CategoryList(
              categories:
                  all.where((c) => c.kind == CategoryKind.income).toList(),
              kind: CategoryKind.income,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryList extends ConsumerWidget {
  final List<Category> categories;
  final CategoryKind kind;

  const _CategoryList({required this.categories, required this.kind});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Category c,
  ) async {
    final used = await ref.read(categoryRepositoryProvider).usageCount(c.id);
    if (!context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${c.name}"?'),
        content: Text(
          used == 0
              ? 'Nothing is filed under it, so this removes it cleanly.'
              : '$used transaction${used == 1 ? '' : 's'} '
                  '${used == 1 ? 'is' : 'are'} filed under it. '
                  '${used == 1 ? 'It keeps' : 'They keep'} the label and stay '
                  'in your history and reports — you just will not be offered '
                  'it again. Hiding does the same thing and is reversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.expense),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(categoryRepositoryProvider).delete(c.id);
    bumpCategories(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final active = categories.where((c) => !c.isHidden).toList();
    final hidden = categories.where((c) => c.isHidden).toList();

    if (categories.isEmpty) {
      return EmptyState(
        icon: Icons.category_outlined,
        title: 'No categories yet',
        message: 'Add the ones you actually use — they will show up whenever '
            'you record money.',
      );
    }

    Widget tile(Category c) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: (kind == CategoryKind.income
                      ? AppColors.income
                      : AppColors.expense)
                  .withValues(alpha: c.isHidden ? 0.06 : 0.14),
              child: Icon(
                c.icon != null ? iconForKey(c.icon) : iconForCategory(c.name),
                size: 20,
                color: c.isHidden
                    ? cs.onSurfaceVariant
                    : (kind == CategoryKind.income
                        ? AppColors.income
                        : AppColors.expense),
              ),
            ),
            title: Text(
              c.name,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: c.isHidden ? cs.onSurfaceVariant : null,
                decoration: c.isHidden ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: c.isBuiltin ? const Text('Built in') : null,
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                final repo = ref.read(categoryRepositoryProvider);
                switch (v) {
                  case 'edit':
                    await CategoryEditorSheet.show(context,
                        category: c, kind: c.kind);
                  case 'hide':
                    await repo.setHidden(c.id, true);
                    bumpCategories(ref);
                  case 'show':
                    await repo.setHidden(c.id, false);
                    bumpCategories(ref);
                  case 'delete':
                    if (context.mounted) await _confirmDelete(context, ref, c);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'edit', child: Text('Rename or change icon')),
                if (c.isHidden)
                  const PopupMenuItem(value: 'show', child: Text('Show again'))
                else
                  const PopupMenuItem(
                      value: 'hide', child: Text('Hide from pickers')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        for (final c in active) tile(c),
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 14),
          const SectionHeader(title: 'Hidden'),
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Still on old transactions, no longer offered when you add one.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
            ),
          ),
          for (final c in hidden) tile(c),
        ],
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  final Object error;
  const _LoadError({required this.error});

  @override
  Widget build(BuildContext context) {
    // The one failure worth naming: the table does not exist yet because the
    // migration has not been run against this project.
    final missing = isCategoriesTableMissing(error);
    return EmptyState(
      icon: Icons.error_outline,
      title: missing ? 'Categories not set up yet' : 'Categories unavailable',
      message: missing
          ? '$kCategoriesSetupHint\n\nUntil then the built-in list still works '
              'for recording money — you just cannot add to it or hide any of '
              'it.'
          : '$error',
    );
  }
}
