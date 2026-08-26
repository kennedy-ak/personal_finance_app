import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/theme.dart';
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

class _CategoriesScreenState extends ConsumerState<CategoriesScreen> {
  int _tab = 0;

  CategoryKind get _kind =>
      _tab == 1 ? CategoryKind.income : CategoryKind.expense;

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final async = ref.watch(allCategoriesProvider);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        alignment: Alignment.centerLeft,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go('/settings'),
                        icon: Icon(Icons.arrow_back,
                            size: 22, color: t.inkMuted),
                      ),
                      const Spacer(),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            CategoryEditorSheet.show(context, kind: _kind),
                        child: Text('New',
                            style: AppType.label
                                .copyWith(fontSize: 13, color: t.brandInk)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Categories',
                      style: AppType.title.copyWith(color: t.ink)),
                  const SizedBox(height: 16),
                  SegmentedTabs(
                    labels: const ['Spending', 'Income'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ],
              ),
            ),
            Expanded(
              child: async.when(
                loading: () =>
                    Center(child: CircularProgressIndicator(color: t.brandInk)),
                error: (e, _) => _LoadError(
                  error: e,
                  onRetry: () => bumpCategories(ref),
                ),
                data: (all) => _CategoryList(
                  categories: all.where((c) => c.kind == _kind).toList(),
                  kind: _kind,
                ),
              ),
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
      BuildContext context, WidgetRef ref, Category c) async {
    final used = await ref.read(categoryRepositoryProvider).usageCount(c.id);
    if (!context.mounted) return;

    final ok = await showDeleteConfirmation(
      context: context,
      title: 'Delete "${c.name}"?',
      message: used == 0
          ? 'Nothing is filed under it, so this removes it cleanly.'
          : '$used transaction${used == 1 ? '' : 's'} '
              '${used == 1 ? 'is' : 'are'} filed under it. '
              '${used == 1 ? 'It keeps' : 'They keep'} the label and stay in '
              'your history and reports — you just will not be offered it '
              'again. Hiding does the same thing and is reversible.',
    );
    if (ok != true) return;
    await ref.read(categoryRepositoryProvider).delete(c.id);
    bumpCategories(ref);
  }

  Future<void> _openActions(
      BuildContext context, WidgetRef ref, Category c) async {
    final action = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: c.name),
          const SizedBox(height: 16),
          RowGroup(
            children: [
              _ActionRow(
                label: 'Rename or change icon',
                onTap: () => Navigator.pop(ctx, 'edit'),
              ),
              _ActionRow(
                label: c.isHidden ? 'Show it again' : 'Hide from pickers',
                detail: c.isHidden
                    ? 'It starts being offered when you add money again.'
                    : 'Old transactions keep the label. It just stops being '
                        'offered.',
                onTap: () => Navigator.pop(ctx, c.isHidden ? 'show' : 'hide'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          DangerButton(
            label: 'Delete',
            onPressed: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    );
    if (action == null || !context.mounted) return;

    final repo = ref.read(categoryRepositoryProvider);
    switch (action) {
      case 'edit':
        await CategoryEditorSheet.show(context, category: c, kind: c.kind);
      case 'hide':
        await repo.setHidden(c.id, true);
        bumpCategories(ref);
      case 'show':
        await repo.setHidden(c.id, false);
        bumpCategories(ref);
      case 'delete':
        if (context.mounted) await _confirmDelete(context, ref, c);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final active = categories.where((c) => !c.isHidden).toList();
    final hidden = categories.where((c) => c.isHidden).toList();

    if (categories.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        children: [
          DottedBorderBox(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('No categories yet',
                    textAlign: TextAlign.center,
                    style:
                        AppType.rowTitle.copyWith(fontSize: 17, color: t.ink)),
                const SizedBox(height: 8),
                Text(
                  'Without categories, spending reports have nothing to group '
                  'by. The default list covers trotro, food, utilities, '
                  'airtime and sending money.',
                  textAlign: TextAlign.center,
                  style: AppType.body.copyWith(height: 1.55, color: t.inkMuted),
                ),
                const SizedBox(height: 18),
                PrimaryButton(
                  label: 'Use the default list',
                  onPressed: () async {
                    await ref
                        .read(categoryRepositoryProvider)
                        .restoreDefaults();
                    bumpCategories(ref);
                  },
                ),
                const SizedBox(height: 10),
                SecondaryButton(
                  label: 'Or create my own',
                  filled:
                      Theme.of(context).brightness == Brightness.light,
                  onPressed: () =>
                      CategoryEditorSheet.show(context, kind: kind),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        RowGroup(
          children: [
            for (final c in active)
              _CategoryRow(
                category: c,
                onTap: () => _openActions(context, ref, c),
              ),
          ],
        ),
        if (hidden.isNotEmpty) ...[
          const SizedBox(height: 18),
          SectionRow(title: 'Hidden', note: '${hidden.length}'),
          const SizedBox(height: 8),
          Text(
            'Still on old transactions, no longer offered when you add one.',
            style: AppType.rowSub.copyWith(height: 1.45, color: t.inkFaint),
          ),
          const SizedBox(height: 10),
          RowGroup(
            children: [
              for (final c in hidden)
                _CategoryRow(
                  category: c,
                  onTap: () => _openActions(context, ref, c),
                  trailingLabel: 'Restore',
                  onTrailing: () async {
                    await ref
                        .read(categoryRepositoryProvider)
                        .setHidden(c.id, false);
                    bumpCategories(ref);
                  },
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final Category category;
  final VoidCallback onTap;

  /// The hidden list swaps the overflow control for a single one-tap Restore.
  final String? trailingLabel;
  final VoidCallback? onTrailing;

  const _CategoryRow({
    required this.category,
    required this.onTap,
    this.trailingLabel,
    this.onTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final hidden = category.isHidden;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Opacity(
              opacity: hidden ? 0.45 : 1,
              child: CategoryGlyph(
                name: category.name,
                hue: category.name.hashCode,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.rowTitle
                    .copyWith(color: hidden ? t.inkMuted : t.ink),
              ),
            ),
            if (category.isBuiltin && trailingLabel == null) ...[
              const SizedBox(width: 8),
              Eyebrow('Built in', size: 9, color: t.inkFaint),
            ],
            const SizedBox(width: 10),
            if (trailingLabel != null)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onTrailing,
                child: Text(trailingLabel!,
                    style: AppType.label
                        .copyWith(fontSize: 13, color: t.brandInk)),
              )
            else
              Icon(Icons.more_vert, size: 18, color: t.inkMuted),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final String label;
  final String? detail;
  final VoidCallback onTap;

  const _ActionRow({required this.label, this.detail, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: AppType.rowTitle.copyWith(color: t.ink)),
                  if (detail != null) ...[
                    const SizedBox(height: 4),
                    Text(detail!,
                        style: AppType.rowSub
                            .copyWith(height: 1.4, color: t.inkMuted)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: t.inkMuted),
          ],
        ),
      ),
    );
  }
}

/// The one failure worth naming: the table does not exist yet because the
/// migration has not been run against this project.
class _LoadError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const _LoadError({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final missing = isCategoriesTableMissing(error);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        ErrorCard(
          title: missing
              ? 'Categories are not set up yet'
              : 'Categories could not be loaded',
          message: missing
              ? '$kCategoriesSetupHint Until then the built-in list still '
                  'works for recording money — you just cannot add to it or '
                  'hide any of it.'
              : 'Your transactions are safe. Reports will group everything as '
                  'Uncategorised until this is fixed.',
          onRetry: onRetry,
        ),
      ],
    );
  }
}
