import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants.dart';
import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/category_repository.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_editor_sheet.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';

/// Amount first, everything else after.
///
/// The number is the only thing the user already knows when they open this
/// screen, so it gets the top of the page and the keyboard. Transfer is a
/// distinct layout rather than a hidden extra field — moving your own money
/// between pockets is a different act from spending it, and the screen should
/// say so.
class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() =>
      _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  TxnType _type = TxnType.expense;
  Account? _account;
  Account? _toAccount;
  String? _category;
  DateTime _date = DateTime.now();
  bool _saving = false;

  bool get _isTransfer => _type == TxnType.transfer;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  List<String> get _categories => _type == TxnType.income
      ? ref.watch(incomeCategoryNamesProvider)
      : ref.watch(expenseCategoryNamesProvider);

  double get _amount =>
      double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _applyQuick(QuickAdd q) {
    setState(() {
      _type = TxnType.expense;
      _amountCtrl.text = q.amount.toStringAsFixed(0);
      _category = q.category;
    });
  }

  Future<void> _pickAccount({required bool destination}) async {
    final accounts = ref.read(accountsProvider).value ?? const <Account>[];
    final available = accounts.where((a) => !a.isArchived).toList();
    final chosen = await showEditorSheet<Account>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(title: destination ? 'Move it to' : 'Take it from'),
          const SizedBox(height: 16),
          RowGroup(
            children: [
              for (final a in available)
                TxnRow(
                  onTap: () => Navigator.pop(ctx, a),
                  leading: CategoryGlyph(name: a.name, hue: a.name.hashCode),
                  title: a.name,
                  subtitle: a.kind.label,
                  amount: formatMoney(a.balance),
                  amountColor: CediTokens.of(ctx).ink,
                ),
            ],
          ),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() {
      if (destination) {
        _toAccount = chosen;
      } else {
        _account = chosen;
      }
    });
  }

  Future<void> _pickCategory() async {
    final options = _categories;
    final chosen = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetHeader(
            title: 'Category',
            action: 'New',
            onAction: () => Navigator.pop(ctx, '__new__'),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final c in options)
                SelectChip(
                  label: c,
                  selected: c == _category,
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    if (chosen == '__new__') {
      final made = await CategoryEditorSheet.show(
        context,
        kind: CategoryKind.forTxn(_type),
      );
      if (made != null && mounted) setState(() => _category = made);
      return;
    }
    setState(() => _category = chosen);
  }

  Future<void> _pickNote() async {
    final ctrl = TextEditingController(text: _descCtrl.text);
    final saved = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'Note'),
          const SizedBox(height: 16),
          SheetField(
            label: 'What was it for?',
            controller: ctrl,
            hint: 'Melcom',
            autofocus: true,
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.pop(ctx, ctrl.text),
          ),
        ],
      ),
    );
    if (saved != null) setState(() => _descCtrl.text = saved);
  }

  String _dateLabel() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(_date.year, _date.month, _date.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Today, ${dayMonthFmt.format(_date)}';
    if (diff == 1) return 'Yesterday, ${dayMonthFmt.format(_date)}';
    return dateLongFmt.format(_date);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    if (_isTransfer) return _saveTransfer();

    if (!_formKey.currentState!.validate()) return;
    if (_account == null) return _toast('Pick the account it came from.');
    if (_category == null) return _toast('Pick a category.');

    setState(() => _saving = true);
    try {
      await ref.read(transactionRepositoryProvider).create(
            accountId: _account!.id,
            type: _type,
            amount: _amount,
            category: _category!,
            description: _descCtrl.text.isEmpty ? null : _descCtrl.text,
            date: _date,
          );
      // The account balance is derived from transactions in the database, so
      // inserting the row is all it takes.
      bumpTransactions(ref);
      bumpAccounts(ref);
      if (!mounted) return;
      _toast(_type == TxnType.income ? 'Income saved' : 'Expense saved');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      _toast('Could not save that. Nothing was changed.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTransfer() async {
    if (!_formKey.currentState!.validate()) return;
    if (_account == null || _toAccount == null) {
      return _toast('Pick both accounts.');
    }
    if (_account!.id == _toAccount!.id) {
      return _toast('Pick two different accounts.');
    }
    if (_account!.balance < _amount) {
      return _toast('${_account!.name} only holds '
          '${formatMoney(_account!.balance)}.');
    }

    setState(() => _saving = true);
    try {
      // One row, not an Expense plus an Income. Moving your own money is not
      // spending, and it should never show up as either.
      await ref.read(transactionRepositoryProvider).createTransfer(
            fromAccountId: _account!.id,
            toAccountId: _toAccount!.id,
            amount: _amount,
            description: _descCtrl.text.isEmpty ? null : _descCtrl.text,
            date: _date,
          );
      bumpTransactions(ref);
      bumpAccounts(ref);
      if (!mounted) return;
      _toast('Transfer saved');
      context.pop();
    } catch (e) {
      if (!mounted) return;
      _toast('Could not save that. Nothing was changed.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final accountsAsync = ref.watch(accountsProvider);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: accountsAsync.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: t.brandInk)),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorCard(
              title: 'Could not load your accounts',
              message: 'Check your connection and try again.',
              onRetry: () => bumpAccounts(ref),
            ),
          ),
          data: (all) {
            final accounts = all.where((a) => !a.isArchived).toList();
            if (accounts.isEmpty) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _TopBar(onCancel: () => context.pop()),
                    const SizedBox(height: 18),
                    EmptyCard(
                      title: 'No accounts yet',
                      message: 'A transaction has to come from somewhere. Add '
                          'an account and this screen starts working.',
                      actionLabel: 'Add an account',
                      onAction: () => context.go('/accounts'),
                    ),
                  ],
                ),
              );
            }

            // Keep the selections pointing at rows that still exist.
            _account = accounts.firstWhere((a) => a.id == _account?.id,
                orElse: () => accounts.first);
            if (_isTransfer && accounts.length > 1) {
              _toAccount = accounts.firstWhere(
                (a) => a.id == _toAccount?.id && a.id != _account!.id,
                orElse: () => accounts.firstWhere((a) => a.id != _account!.id),
              );
            }

            return Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(onCancel: () => context.pop()),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      children: [
                        _AmountHero(
                          controller: _amountCtrl,
                          validator: (v) {
                            final n =
                                double.tryParse((v ?? '').replaceAll(',', ''));
                            if (n == null || n <= 0) return 'Enter an amount';
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        SegmentedChips<TxnType>(
                          options: const [
                            (TxnType.expense, 'Expense'),
                            (TxnType.income, 'Income'),
                            (TxnType.transfer, 'Transfer'),
                          ],
                          selected: _type,
                          onChanged: (v) => setState(() {
                            _type = v;
                            _category = null;
                          }),
                        ),
                        const SizedBox(height: 16),
                        if (_isTransfer)
                          ..._transferFields(accounts)
                        else
                          ..._spendFields(),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                    child: PrimaryButton(
                      label: switch (_type) {
                        TxnType.expense => 'Save expense',
                        TxnType.income => 'Save income',
                        TxnType.transfer => 'Save transfer',
                      },
                      loading: _saving,
                      onPressed: _saving ? null : _save,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  List<Widget> _spendFields() => [
        if (_type == TxnType.expense) ...[
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final q in kQuickAdds)
                SelectChip(
                  label: '${q.label} ${formatMoney(q.amount).replaceAll('.00', '')}',
                  selected: false,
                  onTap: () => _applyQuick(q),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        RowGroup(
          children: [
            PickerRow(
              label: 'Account',
              value: _account?.name ?? 'Pick one',
              onTap: () => _pickAccount(destination: false),
            ),
            PickerRow(
              label: 'Category',
              value: _category ?? 'Pick one',
              onTap: _pickCategory,
            ),
            PickerRow(
              label: 'Date',
              value: _dateLabel(),
              onTap: _pickDate,
            ),
            PickerRow(
              label: 'Note',
              value: _descCtrl.text.isEmpty ? 'Optional' : _descCtrl.text,
              onTap: _pickNote,
            ),
          ],
        ),
      ];

  List<Widget> _transferFields(List<Account> accounts) {
    final t = CediTokens.of(context);
    return [
      CediCard(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TransferEnd(
              label: 'From',
              account: _account,
              onTap: () => _pickAccount(destination: false),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Container(height: 1, color: t.rule)),
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: t.fieldBorder),
                  ),
                  child: Icon(Icons.swap_vert, size: 15, color: t.inkMuted),
                ),
                Expanded(child: Container(height: 1, color: t.rule)),
              ],
            ),
            const SizedBox(height: 12),
            _TransferEnd(
              label: 'To',
              account: _toAccount,
              onTap: () => _pickAccount(destination: true),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      // The one thing people get wrong about transfers, said plainly.
      TintCard(
        tint: t.safe,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Text(
          _amount > 0
              ? 'A transfer does not change your total balance. It moves '
                  '${formatMoney(_amount)} into an account you can spend from.'
              : 'A transfer does not change your total balance. It moves money '
                  'into an account you can spend from.',
          style: AppType.bodySmall.copyWith(height: 1.5, color: t.safe.ink),
        ),
      ),
      const SizedBox(height: 16),
      RowGroup(
        children: [
          PickerRow(label: 'Date', value: _dateLabel(), onTap: _pickDate),
          PickerRow(
            label: 'Note',
            value: _descCtrl.text.isEmpty ? 'Optional' : _descCtrl.text,
            onTap: _pickNote,
          ),
        ],
      ),
    ];
  }
}

class _TopBar extends StatelessWidget {
  final VoidCallback onCancel;
  const _TopBar({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onCancel,
            child: Text('Cancel',
                style: AppType.label.copyWith(fontSize: 15, color: t.inkMuted)),
          ),
          Expanded(
            child: Text('New transaction',
                textAlign: TextAlign.center,
                style: AppType.cardTitle.copyWith(fontSize: 15, color: t.ink)),
          ),
          // Balances the Cancel label so the title sits dead centre.
          const SizedBox(width: 44),
        ],
      ),
    );
  }
}

/// The amount, given the top of the screen and the keyboard.
class _AmountHero extends StatelessWidget {
  final TextEditingController controller;
  final String? Function(String?) validator;

  const _AmountHero({required this.controller, required this.validator});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return CediCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        children: [
          Eyebrow('Amount', color: t.inkFaint),
          const SizedBox(height: 12),
          MoneyField(
            label: 'Amount',
            controller: controller,
            validator: validator,
            autofocus: true,
            hero: true,
          ),
        ],
      ),
    );
  }
}

class _TransferEnd extends StatelessWidget {
  final String label;
  final Account? account;
  final VoidCallback onTap;

  const _TransferEnd({
    required this.label,
    required this.account,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Eyebrow(label, color: t.inkFaint),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(account?.name ?? 'Pick an account',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label.copyWith(
                        fontSize: 15,
                        color: account == null ? t.inkFaint : t.ink)),
              ),
              const SizedBox(width: 10),
              if (account != null)
                Text(formatMoney(account!.balance),
                    softWrap: false,
                    style: AppType.bodySmall.copyWith(
                        height: 1.0,
                        color: t.inkMuted,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              Icon(Icons.chevron_right, size: 18, color: t.inkMuted),
            ],
          ),
        ],
      ),
    );
  }
}
