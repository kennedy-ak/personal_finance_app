import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
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
      final amount = double.parse(_amountCtrl.text);
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accounts = ref.watch(activeAccountsProvider).value ?? const <Account>[];
    final isBill = _direction == ObligationDirection.out;

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
                _isNew ? 'New commitment' : 'Edit commitment',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Anything the app should count before calling money spendable.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              SegmentedButton<ObligationDirection>(
                segments: const [
                  ButtonSegment(
                    value: ObligationDirection.out,
                    icon: Icon(Icons.arrow_upward, size: 16),
                    label: Text('Bill'),
                  ),
                  ButtonSegment(
                    value: ObligationDirection.incoming,
                    icon: Icon(Icons.arrow_downward, size: 16),
                    label: Text('Income'),
                  ),
                ],
                selected: {_direction},
                onSelectionChanged: (s) => setState(() {
                  _direction = s.first;
                  _category = null;
                }),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Name',
                  hintText: isBill ? 'e.g. Rent' : 'e.g. Salary',
                  prefixIcon: const Icon(Icons.label_outline),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: 'GHS ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a positive amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<Cadence>(
                initialValue: _cadence,
                decoration: const InputDecoration(
                  labelText: 'How often',
                  prefixIcon: Icon(Icons.repeat),
                ),
                items: [
                  for (final c in Cadence.values)
                    DropdownMenuItem(value: c, child: Text(c.label)),
                ],
                onChanged: (v) => setState(() => _cadence = v ?? _cadence),
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: _cadence == Cadence.once
                        ? 'Date'
                        : 'Next time it lands',
                    prefixIcon: const Icon(Icons.event),
                    suffixIcon: const Icon(Icons.chevron_right),
                  ),
                  child: Text(dateLongFmt.format(_nextDue)),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue:
                    accounts.any((a) => a.id == _accountId) ? _accountId : null,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: isBill ? 'Paid from' : 'Arrives in',
                  prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                  helperText: 'Optional — helps the coach pick the right account.',
                  helperMaxLines: 2,
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Not decided')),
                  for (final a in accounts)
                    DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              if (isBill) ...[
                const SizedBox(height: 14),
                Builder(builder: (_) {
                  final categories = ref.watch(expenseCategoryNamesProvider);
                  return DropdownButtonFormField<String?>(
                    initialValue:
                        categories.contains(_category) ? _category : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('None')),
                      for (final c in categories)
                        DropdownMenuItem<String?>(value: c, child: Text(c)),
                    ],
                    onChanged: (v) => setState(() => _category = v),
                  );
                }),
              ],
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: isBill ? AppColors.expense : AppColors.income,
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
                label: Text(_isNew ? 'Add commitment' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
