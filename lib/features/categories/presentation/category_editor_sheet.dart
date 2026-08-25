import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/category_icons.dart';
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
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
    final cs = Theme.of(context).colorScheme;
    final accent =
        widget.kind == CategoryKind.income ? AppColors.income : AppColors.expense;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _isNew
                    ? 'New ${widget.kind.label.toLowerCase()} category'
                    : 'Edit category',
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: widget.kind == CategoryKind.income
                      ? 'e.g. Side hustle'
                      : 'e.g. Tithe, Chop money, Data bundle',
                  prefixIcon: Icon(iconForKey(_icon)),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                onFieldSubmitted: (_) {
                  if (!_saving) _save();
                },
              ),
              if (!_isNew) ...[
                const SizedBox(height: 6),
                Text(
                  'Renaming also relabels every transaction already filed '
                  'under it.',
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 20),
              const _FieldLabel('Icon'),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final entry in kPickableIcons.entries)
                        _IconChoice(
                          icon: entry.value,
                          selected: _icon == entry.key,
                          color: accent,
                          onTap: () => setState(() => _icon = entry.key),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: accent,
                ),
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_isNew ? 'Create category' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChoice extends StatelessWidget {
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color:
              selected ? color.withValues(alpha: 0.15) : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.6,
          ),
        ),
        child:
            Icon(icon, size: 22, color: selected ? color : cs.onSurfaceVariant),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      );
}
