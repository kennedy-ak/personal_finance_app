import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
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
      backgroundColor: Colors.transparent,
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
      final target = double.parse(_targetCtrl.text.replaceAll(',', ''));
      final saved = double.tryParse(_savedCtrl.text.replaceAll(',', '')) ?? 0;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save this goal.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final accounts = ref.watch(activeAccountsProvider).value ?? const <Account>[];

    return SheetSurface(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHeader(title: _isNew ? 'New goal' : 'Edit goal'),
              const SizedBox(height: 16),
              SheetField(
                label: 'Goal',
                controller: _nameCtrl,
                hint: 'Laptop',
                textCapitalization: TextCapitalization.sentences,
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
                      label: 'Target',
                      controller: _targetCtrl,
                      validator: (v) {
                        final n =
                            double.tryParse((v ?? '').replaceAll(',', ''));
                        if (n == null || n <= 0) return 'Set a target';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: MoneyField(
                      label: 'Saved',
                      controller: _savedCtrl,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 13),
              RowGroup(
                children: [
                  PickerRow(
                    label: 'Target date',
                    value: _targetDate == null
                        ? 'None'
                        : dateLongFmt.format(_targetDate!),
                    onTap: _pickDate,
                  ),
                  if (accounts.isNotEmpty)
                    PickerRow(
                      label: 'Held in',
                      value: accounts
                              .where((a) => a.id == _accountId)
                              .firstOrNull
                              ?.name ??
                          'Any account',
                      onTap: () => _pickAccount(accounts),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                'A goal is held back from safe-to-spend, so the money stops '
                'being spent by accident.',
                style: AppType.rowSub.copyWith(height: 1.4, color: t.inkFaint),
              ),
              const SizedBox(height: 20),
              PrimaryButton(
                label: _isNew ? 'Create goal' : 'Save goal',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
              if (!_isNew) ...[
                const SizedBox(height: 10),
                DangerButton(
                  label: 'Delete goal',
                  onPressed: _saving ? null : _delete,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickAccount(List<Account> accounts) async {
    final chosen = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'Held in'),
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

  Future<void> _delete() async {
    final goal = widget.goal!;
    final ok = await showDeleteConfirmation(
      context: context,
      title: 'Delete "${goal.name}"?',
      message: 'The ${formatMoney(goal.savedAmount)} held for it goes back '
          'into safe-to-spend. Your balances do not change.',
    );
    if (ok != true) return;
    setState(() => _saving = true);
    try {
      await ref.read(goalRepositoryProvider).delete(goal.id);
      bumpGoals(ref);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete this goal.')),
      );
    }
  }
}
