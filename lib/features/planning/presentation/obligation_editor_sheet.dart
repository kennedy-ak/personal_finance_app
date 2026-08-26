import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/category_repository.dart';
import '../data/obligation_repository.dart';
import '../domain/obligation.dart';

/// Records something that is going to happen to the user's money whether they
/// think about it or not — rent, a subscription, a salary.
class ObligationEditorSheet extends ConsumerStatefulWidget {
  final Obligation? obligation;

  const ObligationEditorSheet({super.key, this.obligation});

  static Future<bool?> show(BuildContext context, {Obligation? obligation}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ObligationEditorSheet(obligation: obligation),
    );
  }

  @override
  ConsumerState<ObligationEditorSheet> createState() =>
      _ObligationEditorSheetState();
}

class _ObligationEditorSheetState extends ConsumerState<ObligationEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;

  late ObligationDirection _direction;
  late Cadence _cadence;
  late DateTime _nextDue;
  String? _accountId;
  String? _category;
  bool _saving = false;

  bool get _isNew => widget.obligation == null;

  @override
  void initState() {
    super.initState();
    final o = widget.obligation;
    _nameCtrl = TextEditingController(text: o?.name ?? '');
    _amountCtrl =
        TextEditingController(text: o == null ? '' : o.amount.toStringAsFixed(2));
    _direction = o?.direction ?? ObligationDirection.out;
    _cadence = o?.cadence ?? Cadence.monthly;
    _nextDue = o?.nextDue ?? DateTime.now().add(const Duration(days: 1));
    _accountId = o?.accountId;
    _category = o?.category;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _nextDue,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      helpText: 'When does it next land?',
    );
    if (picked != null) setState(() => _nextDue = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(obligationRepositoryProvider);
    try {
      final amount = double.parse(_amountCtrl.text.replaceAll(',', ''));
      if (_isNew) {
        await repo.create(
          name: _nameCtrl.text.trim(),
          amount: amount,
          nextDue: _nextDue,
          direction: _direction,
          cadence: _cadence,
          accountId: _accountId,
          category: _category,
        );
      } else {
        await repo.update(
          widget.obligation!.id,
          name: _nameCtrl.text.trim(),
          amount: amount,
          nextDue: _nextDue,
          direction: _direction,
          cadence: _cadence,
          accountId: _accountId ?? '',
          category: _category ?? '',
        );
      }
      bumpObligations(ref);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this commitment.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final accounts = ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final categories = _direction == ObligationDirection.out
        ? ref.watch(expenseCategoryNamesProvider)
        : ref.watch(incomeCategoryNamesProvider);
    final out = _direction == ObligationDirection.out;

    return SheetSurface(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(
                  title: _isNew ? 'New commitment' : 'Edit commitment'),
              const SizedBox(height: 16),
              SegmentedChips<ObligationDirection>(
                options: const [
                  (ObligationDirection.out, 'Bill'),
                  (ObligationDirection.incoming, 'Income'),
                ],
                selected: _direction,
                onChanged: (d) => setState(() {
                  _direction = d;
                  _category = null;
                }),
              ),
              const SizedBox(height: 13),
              SheetField(
                label: 'What is it',
                controller: _nameCtrl,
                hint: out ? 'Rent' : 'Salary',
                autofocus: _isNew,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Give it a name' : null,
              ),
              const SizedBox(height: 13),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: MoneyField(
                      label: 'Amount',
                      controller: _amountCtrl,
                      validator: (v) {
                        final n =
                            double.tryParse((v ?? '').replaceAll(',', ''));
                        if (n == null || n <= 0) return 'Enter an amount';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: LabeledField(
                      label: 'Repeats',
                      child: _PickerBox(
                        value: _cadence.label,
                        onTap: _pickCadence,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              RowGroup(
                children: [
                  PickerRow(
                    label: 'Next due',
                    value: dateLongFmt.format(_nextDue),
                    onTap: _pickDate,
                  ),
                  PickerRow(
                    label: out ? 'Leaves from' : 'Lands in',
                    value: accounts
                            .where((a) => a.id == _accountId)
                            .firstOrNull
                            ?.name ??
                        'Any account',
                    onTap: () => _pickAccount(accounts),
                  ),
                  if (categories.isNotEmpty)
                    PickerRow(
                      label: 'Category',
                      value: _category ?? 'None',
                      onTap: () => _pickCategory(categories),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                out
                    ? 'Pinning it to an account is what lets the app warn you '
                        'when that account cannot cover it.'
                    : 'The next due date sets the horizon for safe-to-spend.',
                style: AppType.rowSub.copyWith(height: 1.4, color: t.inkFaint),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isNew ? 'Create commitment' : 'Save commitment',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
              if (!_isNew) ...[
                const SizedBox(height: 10),
                DangerButton(
                  label: 'Delete commitment',
                  onPressed: _saving ? null : _delete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickCadence() async {
    final chosen = await showEditorSheet<Cadence>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'How often'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final c in Cadence.values)
                SelectChip(
                  label: c.label,
                  selected: c == _cadence,
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ],
      ),
    );
    if (chosen != null) setState(() => _cadence = chosen);
  }

  Future<void> _pickAccount(List<Account> accounts) async {
    final chosen = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
              title: _direction == ObligationDirection.out
                  ? 'Leaves from'
                  : 'Lands in'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              SelectChip(
                label: 'Any account',
                selected: _accountId == null,
                onTap: () => Navigator.pop(ctx, '__any__'),
              ),
              for (final a in accounts)
                SelectChip(
                  label: a.name,
                  selected: _accountId == a.id,
                  onTap: () => Navigator.pop(ctx, a.id),
                ),
            ],
          ),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() => _accountId = chosen == '__any__' ? null : chosen);
  }

  Future<void> _pickCategory(List<String> categories) async {
    final chosen = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'Category'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              SelectChip(
                label: 'None',
                selected: _category == null,
                onTap: () => Navigator.pop(ctx, '__none__'),
              ),
              for (final c in categories)
                SelectChip(
                  label: c,
                  selected: _category == c,
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() => _category = chosen == '__none__' ? null : chosen);
  }

  Future<void> _delete() async {
    final o = widget.obligation!;
    final ok = await showDeleteConfirmation(
      context: context,
      title: 'Delete "${o.name}"?',
      message: '${formatMoney(o.amount)} stops being held back, so your '
          'safe-to-spend goes up by that much. Your balances do not change.',
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(obligationRepositoryProvider).delete(o.id);
      bumpObligations(ref);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this commitment.')),
      );
    }
  }
}

/// A field-shaped box that opens a picker — used where a value belongs beside
/// another field rather than in a row group.
class _PickerBox extends StatelessWidget {
  final String value;
  final VoidCallback onTap;

  const _PickerBox({required this.value, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Material(
      color: t.field,
      borderRadius: Radii.sm,
      child: InkWell(
        borderRadius: Radii.sm,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 15),
          decoration: BoxDecoration(
            borderRadius: Radii.sm,
            border: Border.all(color: t.fieldBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body
                        .copyWith(fontSize: 15, height: 1.0, color: t.ink)),
              ),
              Icon(Icons.expand_more, size: 18, color: t.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}
