import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_icons.dart';
import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/theme.dart';
import '../data/category_repository.dart';
import '../domain/category.dart';

/// Creates or edits one category.
///
/// Returns the category's name on success, so a picker that opened it can
/// select what was just made instead of making the user hunt for it.
class CategoryEditorSheet extends ConsumerStatefulWidget {
  /// Null creates a new category.
  final Category? category;
  final CategoryKind kind;

  /// Prefills the name — used when a picker opens this with what the user had
  /// already typed.
  final String? initialName;

  const CategoryEditorSheet({
    super.key,
    this.category,
    required this.kind,
    this.initialName,
  });

  static Future<String?> show(
    BuildContext context, {
    Category? category,
    required CategoryKind kind,
    String? initialName,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      // Without this the sheet opens inside the shell's Scaffold body and the
      // floating add button is painted on top of the form.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CategoryEditorSheet(
        category: category,
        kind: kind,
        initialName: initialName,
      ),
    );
  }

  @override
  ConsumerState<CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<CategoryEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late String? _icon;
  bool _saving = false;

  bool get _isNew => widget.category == null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: widget.category?.name ?? widget.initialName ?? '',
    );
    _icon = widget.category?.icon ?? 'label';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameCtrl.text.trim();
    setState(() => _saving = true);
    final repo = ref.read(categoryRepositoryProvider);
    try {
      if (_isNew) {
        await repo.create(name: name, kind: widget.kind, icon: _icon);
      } else {
        final c = widget.category!;
        if (c.name != name) await repo.rename(c.id, name);
        if (c.icon != _icon) await repo.setIcon(c.id, _icon);
      }
      bumpCategories(ref);
      if (mounted) Navigator.pop(context, name);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Two failures have an answer the user can act on. Everything else is
      // genuinely unexpected and shows the provider's own words.
      final duplicate = e.toString().contains('categories_user_id_kind_name_key');
      final message = duplicate
          ? 'You already have a ${widget.kind.label.toLowerCase()} category '
              'called "$name".'
          : isCategoriesTableMissing(e)
              ? kCategoriesSetupHint
              : 'Error: $e';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: isCategoriesTableMissing(e)
              ? const Duration(seconds: 8)
              : const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return SheetSurface(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                title: _isNew
                    ? 'New ${widget.kind.label.toLowerCase()} category'
                    : 'Edit category',
              ),
              const SizedBox(height: 16),
              SheetField(
                label: 'Name',
                controller: _nameCtrl,
                hint: widget.kind == CategoryKind.income
                    ? 'Salary'
                    : 'Transportation',
                textCapitalization: TextCapitalization.words,
                autofocus: true,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Give it a name' : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              LabeledField(
                label: 'Icon',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final key in _iconChoices)
                      _IconChoice(
                        iconKey: key,
                        // The glyph previews with the name the user is
                        // typing, so they see the initials that will show up
                        // on every row before they commit to it.
                        preview: _nameCtrl.text.trim().isEmpty
                            ? 'Category'
                            : _nameCtrl.text.trim(),
                        selected: _icon == key,
                        onTap: () => setState(() => _icon = key),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                'Rows show the first letters of the name. The icon is used '
                'wherever there is room for one.',
                style: AppType.rowSub.copyWith(height: 1.4, color: t.inkFaint),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isNew ? 'Create category' : 'Save category',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The icons offered in the picker, in the order a money app needs them.
const _iconChoices = <String>[
  'bus',
  'restaurant',
  'grocery',
  'bolt',
  'phone',
  'home',
  'shopping',
  'medical',
  'school',
  'gift',
  'savings',
  'cash',
  'work',
  'business',
  'trending_up',
  'label',
];

class _IconChoice extends StatelessWidget {
  final String iconKey;
  final String preview;
  final bool selected;
  final VoidCallback onTap;

  const _IconChoice({
    required this.iconKey,
    required this.preview,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final hue = preview.hashCode.abs() % t.glyphSurfaces.length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: t.glyphSurfaces[hue],
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: t.glyphInks[hue], width: 2)
              : null,
        ),
        child: Icon(iconForKey(iconKey), size: 19, color: t.glyphInks[hue]),
      ),
    );
  }
}
