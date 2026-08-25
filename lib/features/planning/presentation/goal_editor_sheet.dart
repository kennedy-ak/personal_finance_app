import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../data/goal_repository.dart';
import '../domain/goal.dart';

/// Money the user has decided is not available, even though it is sitting
/// right there in a spendable account.
class GoalEditorSheet extends ConsumerStatefulWidget {
  final Goal? goal;

  const GoalEditorSheet({super.key, this.goal});

  static Future<bool?> show(BuildContext context, {Goal? goal}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => GoalEditorSheet(goal: goal),
    );
  }

  @override
  ConsumerState<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<GoalEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _targetCtrl;
  late final TextEditingController _savedCtrl;

  DateTime? _targetDate;
  String? _accountId;
  bool _saving = false;

  bool get _isNew => widget.goal == null;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _nameCtrl = TextEditingController(text: g?.name ?? '');
    _targetCtrl = TextEditingController(
        text: g == null ? '' : g.targetAmount.toStringAsFixed(2));
    _savedCtrl = TextEditingController(
        text: (g?.savedAmount ?? 0).toStringAsFixed(2));
    _targetDate = g?.targetDate;
    _accountId = g?.accountId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _targetCtrl.dispose();
    _savedCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _targetDate ?? DateTime.now().add(const Duration(days: 90)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 20)),
      helpText: 'Target date',
    );
    if (picked != null) setState(() => _targetDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final repo = ref.read(goalRepositoryProvider);
    try {
      final target = double.parse(_targetCtrl.text);
      final saved = double.tryParse(_savedCtrl.text) ?? 0;
      if (_isNew) {
        await repo.create(
          name: _nameCtrl.text.trim(),
          targetAmount: target,
          savedAmount: saved,
          targetDate: _targetDate,
          accountId: _accountId,
        );
      } else {
        await repo.update(
          widget.goal!.id,
          name: _nameCtrl.text.trim(),
          targetAmount: target,
          savedAmount: saved,
          targetDate: _targetDate,
          clearTargetDate: _targetDate == null,
          accountId: _accountId ?? '',
        );
      }
      bumpGoals(ref);
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
                _isNew ? 'New goal' : 'Edit goal',
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'What you set aside here stops counting as spendable money.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Emergency fund',
                  prefixIcon: Icon(Icons.flag_outlined),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Target',
                  prefixText: 'GHS ',
                  prefixIcon: Icon(Icons.flag),
                ),
                validator: (v) {
                  final n = double.tryParse(v ?? '');
                  if (n == null || n <= 0) return 'Enter a positive amount';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _savedCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Set aside so far',
                  prefixText: 'GHS ',
                  prefixIcon: Icon(Icons.savings_outlined),
                  helperText: 'This is the amount held back from spendable money.',
                  helperMaxLines: 2,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = double.tryParse(v);
                  if (n == null || n < 0) return 'Enter zero or more';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(14),
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: 'Target date (optional)',
                    prefixIcon: const Icon(Icons.event),
                    suffixIcon: _targetDate == null
                        ? const Icon(Icons.chevron_right)
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setState(() => _targetDate = null),
                          ),
                  ),
                  child: Text(
                    _targetDate == null
                        ? 'No deadline'
                        : dateLongFmt.format(_targetDate!),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String?>(
                initialValue:
                    accounts.any((a) => a.id == _accountId) ? _accountId : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Where the money sits (optional)',
                  prefixIcon: Icon(Icons.account_balance_wallet_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                      value: null, child: Text('Not specified')),
                  for (final a in accounts)
                    DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _accountId = v),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: AppColors.seed,
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
                label: Text(_isNew ? 'Add goal' : 'Save changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
