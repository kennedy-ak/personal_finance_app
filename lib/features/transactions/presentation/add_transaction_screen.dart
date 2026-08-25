import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/category_icons.dart';
import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/category_repository.dart';
import '../../categories/domain/category.dart';
import '../../categories/presentation/category_editor_sheet.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';

class AddTransactionScreen extends ConsumerStatefulWidget {
  const AddTransactionScreen({super.key});

  @override
  ConsumerState<AddTransactionScreen> createState() => _AddTransactionScreenState();
}

class _AddTransactionScreenState extends ConsumerState<AddTransactionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  TxnType _type = TxnType.expense;
  bool _isTransfer = false;
  Account? _account;
  Account? _toAccount;
  String? _category;
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  List<String> get _categories => _type == TxnType.expense
      ? ref.watch(expenseCategoryNamesProvider)
      : ref.watch(incomeCategoryNamesProvider);

  /// Opens the category editor straight from the picker, so a missing category
  /// is one tap to fix instead of a trip through Settings and back.
  Future<void> _createCategory() async {
    final made = await CategoryEditorSheet.show(
      context,
      kind: CategoryKind.forTxn(_type),
    );
    if (made != null && mounted) setState(() => _category = made);
  }

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
      _isTransfer = false;
      _amountCtrl.text = q.amount.toStringAsFixed(0);
      _category = q.category;
    });
  }

  Future<void> _save() async {
    if (_isTransfer) {
      await _saveTransfer();
      return;
    }
    if (!_formKey.currentState!.validate() || _account == null || _category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Fill all required fields')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountCtrl.text);
      await ref.read(transactionRepositoryProvider).create(
            accountId: _account!.id,
            type: _type,
            amount: amount,
            category: _category!,
            description: _descCtrl.text.isEmpty ? null : _descCtrl.text,
            date: _date,
          );
      // The account balance is derived from transactions in the database, so
      // inserting the row is all it takes.
      bumpTransactions(ref);
      bumpAccounts(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Transaction added'),
          backgroundColor: AppColors.income,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _amountCtrl.clear();
      _descCtrl.clear();
      setState(() => _category = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveTransfer() async {
    if (!_formKey.currentState!.validate() ||
        _account == null ||
        _toAccount == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick source and destination accounts')),
      );
      return;
    }
    if (_account!.id == _toAccount!.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Source and destination must differ')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountCtrl.text);
      if (_account!.balance < amount) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Insufficient balance in source account')),
        );
        setState(() => _saving = false);
        return;
      }
      final note = _descCtrl.text.isEmpty ? null : _descCtrl.text;
      // One row, not an Expense plus an Income. Moving your own money is not
      // spending, and it should never show up as either.
      await ref.read(transactionRepositoryProvider).createTransfer(
            fromAccountId: _account!.id,
            toAccountId: _toAccount!.id,
            amount: amount,
            description: note,
            date: _date,
          );
      bumpTransactions(ref);
      bumpAccounts(ref);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Transfer completed'),
          backgroundColor: AppColors.income,
          behavior: SnackBarBehavior.floating,
        ),
      );
      _amountCtrl.clear();
      _descCtrl.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Add Transaction')),
      body: accountsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (accounts) {
          if (accounts.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'No accounts yet',
              message: 'Create an account first to add transactions.',
              action: FilledButton.icon(
                onPressed: () => context.go('/accounts'),
                icon: const Icon(Icons.add),
                label: const Text('Create account'),
              ),
            );
          }
          _account = accounts.firstWhere(
            (a) => a.id == _account?.id,
            orElse: () => accounts.first,
          );
          if (_isTransfer) {
            final candidates = accounts.where((a) => a.id != _account!.id).toList();
            if (candidates.isNotEmpty) {
              _toAccount = candidates.firstWhere(
                (a) => a.id == _toAccount?.id,
                orElse: () => candidates.first,
              );
            } else {
              _toAccount = null;
            }
          }
          final color = _isTransfer
              ? AppColors.accent
              : (_type == TxnType.income ? AppColors.income : AppColors.expense);
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: _TypeTab(
                          label: 'Expense',
                          icon: Icons.arrow_upward,
                          color: AppColors.expense,
                          selected: !_isTransfer && _type == TxnType.expense,
                          onTap: () => setState(() {
                            _isTransfer = false;
                            _type = TxnType.expense;
                            _category = null;
                          }),
                        ),
                      ),
                      Expanded(
                        child: _TypeTab(
                          label: 'Income',
                          icon: Icons.arrow_downward,
                          color: AppColors.income,
                          selected: !_isTransfer && _type == TxnType.income,
                          onTap: () => setState(() {
                            _isTransfer = false;
                            _type = TxnType.income;
                            _category = null;
                          }),
                        ),
                      ),
                      Expanded(
                        child: _TypeTab(
                          label: 'Transfer',
                          icon: Icons.swap_horiz,
                          color: AppColors.accent,
                          selected: _isTransfer,
                          onTap: () => setState(() {
                            _isTransfer = true;
                            _category = null;
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: TextFormField(
                      controller: _amountCtrl,
                      textAlign: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.w800,
                        color: color,
                        letterSpacing: -1,
                      ),
                      decoration: InputDecoration(
                        hintText: '0.00',
                        prefixText: 'GHS  ',
                        prefixStyle: TextStyle(
                          fontSize: 18,
                          color: color.withValues(alpha: 0.7),
                          fontWeight: FontWeight.w600,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        final n = double.tryParse(v);
                        if (n == null || n <= 0) return 'Enter a positive amount';
                        return null;
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (!_isTransfer && _type == TxnType.expense) ...[
                  TextButton.icon(
                    onPressed: () => context.push('/pay'),
                    icon: const Icon(Icons.alt_route, size: 18),
                    label: const Text('Not sure which account? Let the app pick'),
                  ),
                  const SizedBox(height: 4),
                  const SectionHeader(title: 'Quick add'),
                  SizedBox(
                    height: 38,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // A shortcut to a category the user has hidden is a
                        // button that quietly does nothing.
                        for (final q in kQuickAdds
                            .where((q) => _categories.contains(q.category))) ...[
                          ActionChip(
                            avatar: Icon(iconForCategory(q.category), size: 16),
                            label: Text('${q.label} • ${formatMoney(q.amount)}'),
                            onPressed: () => _applyQuick(q),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                DropdownButtonFormField<Account>(
                  initialValue: _account,
                  decoration: InputDecoration(
                    labelText: _isTransfer ? 'From account' : 'Account',
                    prefixIcon: const Icon(Icons.account_balance_wallet),
                  ),
                  items: accounts
                      .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() {
                    _account = v;
                    if (_isTransfer && _toAccount?.id == v?.id) _toAccount = null;
                  }),
                ),
                const SizedBox(height: 12),
                if (_isTransfer)
                  DropdownButtonFormField<Account>(
                    initialValue: _toAccount,
                    decoration: const InputDecoration(
                      labelText: 'To account',
                      prefixIcon: Icon(Icons.swap_horiz),
                    ),
                    items: accounts
                        .where((a) => a.id != _account?.id)
                        .map((a) => DropdownMenuItem(value: a, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _toAccount = v),
                    validator: (v) => v == null ? 'Required' : null,
                  )
                else ...[
                  Builder(builder: (_) {
                    final categories = _categories;
                    // A category hidden or deleted while it sat selected would
                    // otherwise assert its way out of the dropdown.
                    final selected =
                        categories.contains(_category) ? _category : null;
                    return DropdownButtonFormField<String>(
                      initialValue: selected,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Category',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: [
                        for (final c in categories)
                          DropdownMenuItem(
                            value: c,
                            child: Row(
                              children: [
                                Icon(iconForCategory(c), size: 18),
                                const SizedBox(width: 10),
                                Expanded(
                                  child:
                                      Text(c, overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _category = v),
                      validator: (v) => v == null ? 'Required' : null,
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _createCategory,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New category'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 34),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(14),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date',
                      prefixIcon: Icon(Icons.calendar_today),
                      suffixIcon: Icon(Icons.chevron_right),
                    ),
                    child: Text(dateLongFmt.format(_date)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    prefixIcon: Icon(Icons.notes),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: Text(_isTransfer
                      ? 'Save Transfer'
                      : (_type == TxnType.income ? 'Save Income' : 'Save Expense')),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TypeTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _TypeTab({
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 18, color: selected ? Colors.white : color),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
