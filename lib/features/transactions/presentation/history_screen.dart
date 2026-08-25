import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/category_icons.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../../accounts/data/account_repository.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import 'txn_style.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  TxnType? _typeFilter;
  String? _categoryFilter;
  String? _accountFilter;
  DateTimeRange? _range;
  String _search = '';

  Future<void> _exportCsv(List<Txn> rows, Map<String, String> accountNames) async {
    final data = <List<String>>[
      ['Date', 'Type', 'Amount', 'Account', 'Category', 'Description'],
      ...rows.map((t) => [
            dateFmt.format(t.date),
            t.type.label,
            t.amount.toStringAsFixed(2),
            accountNames[t.accountId] ?? '',
            t.category,
            t.description ?? '',
          ]),
    ];
    final csvText = Csv().encode(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/transactions_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csvText);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Transactions export'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: () => _showFilters(context),
          ),
          txns.maybeWhen(
            data: (list) => accounts.maybeWhen(
              data: (accs) {
                final names = {for (final a in accs) a.id: a.name};
                final filtered = _filter(list, names);
                return IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: 'Export CSV',
                  onPressed: filtered.isEmpty ? null : () => _exportCsv(filtered, names),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: txns.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => accounts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (accs) {
            final names = {for (final a in accs) a.id: a.name};
            final filtered = _filter(list, names);
            final inc = filtered.where((t) => t.isIncome).fold<double>(0, (s, t) => s + t.amount);
            final exp = filtered.where((t) => t.isSpending).fold<double>(0, (s, t) => s + t.amount);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search description, category…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      suffixIcon: _search.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => setState(() => _search = ''),
                            ),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                if (_hasAnyFilter())
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: SizedBox(
                      height: 36,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          if (_typeFilter != null)
                            _chip(_typeFilter!.label, () => setState(() => _typeFilter = null)),
                          if (_accountFilter != null)
                            _chip(names[_accountFilter] ?? 'Account',
                                () => setState(() => _accountFilter = null)),
                          if (_categoryFilter != null)
                            _chip(_categoryFilter!, () => setState(() => _categoryFilter = null)),
                          if (_range != null)
                            _chip(
                                '${dateFmt.format(_range!.start)} → ${dateFmt.format(_range!.end)}',
                                () => setState(() => _range = null)),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      _summary('In', inc, AppColors.income),
                      const SizedBox(width: 10),
                      _summary('Out', exp, AppColors.expense),
                      const SizedBox(width: 10),
                      _summary('Net', inc - exp,
                          (inc - exp) >= 0 ? AppColors.income : AppColors.expense),
                    ],
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptyState(
                          icon: Icons.search_off,
                          title: 'No transactions match',
                          message: 'Try adjusting your filters or add a new transaction.',
                        )
                      : RefreshIndicator(
                          onRefresh: () async {
                            bumpTransactions(ref);
                            await ref.read(transactionsProvider.future);
                          },
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final t = filtered[i];
                              final color = colorForTxn(t.type);
                              return Dismissible(
                                key: ValueKey(t.id),
                                background: Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.expense,
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 20),
                                  child: const Icon(Icons.delete, color: Colors.white),
                                ),
                                direction: DismissDirection.endToStart,
                                confirmDismiss: (_) async {
                                  return await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: const Text('Delete transaction?'),
                                          actions: [
                                            TextButton(
                                                onPressed: () => Navigator.pop(ctx, false),
                                                child: const Text('Cancel')),
                                            FilledButton(
                                                style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
                                                onPressed: () => Navigator.pop(ctx, true),
                                                child: const Text('Delete')),
                                          ],
                                        ),
                                      ) ??
                                      false;
                                },
                                onDismissed: (_) async {
                                  await _deleteTxn(t);
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Card(
                                    child: ListTile(
                                      onTap: () => _showDetails(t, names[t.accountId]),
                                      leading: Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Icon(iconForTxn(t),
                                            color: color, size: 22),
                                      ),
                                      title: Text(
                                          titleForTxn(t,
                                              fromName: names[t.accountId],
                                              toName: names[t.toAccountId]),
                                          style: const TextStyle(fontWeight: FontWeight.w600)),
                                      subtitle: Text(
                                        '${dateLongFmt.format(t.date)} • ${names[t.accountId] ?? ''}'
                                        '${t.description?.isNotEmpty == true ? ' • ${t.description}' : ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: Text(
                                        '${signForTxn(t.type)}${formatMoney(t.amount)}',
                                        style: TextStyle(
                                          color: color,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _summary(String label, double value, Color color) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(formatMoney(value),
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
            ],
          ),
        ),
      );

  Widget _chip(String label, VoidCallback onClear) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: InputChip(
          label: Text(label, style: const TextStyle(fontSize: 12)),
          onDeleted: onClear,
          deleteIconColor: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );

  bool _hasAnyFilter() =>
      _typeFilter != null || _categoryFilter != null || _accountFilter != null || _range != null;

  List<Txn> _filter(List<Txn> list, Map<String, String> names) {
    final s = _search.trim().toLowerCase();
    return list.where((t) {
      if (_typeFilter != null && t.type != _typeFilter) return false;
      if (_categoryFilter != null && t.category != _categoryFilter) return false;
      if (_accountFilter != null && t.accountId != _accountFilter) return false;
      if (_range != null) {
        if (t.date.isBefore(_range!.start)) return false;
        if (t.date.isAfter(_range!.end.add(const Duration(days: 1)))) return false;
      }
      if (s.isNotEmpty) {
        final hay =
            '${t.category} ${t.description ?? ''} ${names[t.accountId] ?? ''}'.toLowerCase();
        if (!hay.contains(s)) return false;
      }
      return true;
    }).toList();
  }

  Future<void> _deleteTxn(Txn t) async {
    // Balances are derived in the database — deleting the row is enough, and
    // both sides of a transfer settle themselves.
    await ref.read(transactionRepositoryProvider).delete(t.id);
    bumpTransactions(ref);
    bumpAccounts(ref);
  }

  Future<void> _showDetails(Txn t, String? accountName) async {
    final color = colorForTxn(t.type);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: 24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Theme.of(ctx).dividerColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(iconForCategory(t.category), color: color, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.category,
                            style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(t.type.label,
                            style: TextStyle(
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  Text(
                    '${signForTxn(t.type)}${formatMoney(t.amount)}',
                    style: TextStyle(
                        color: color,
                        fontSize: 20,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              _DetailRow(icon: Icons.calendar_today, label: 'Date', value: dateLongFmt.format(t.date)),
              _DetailRow(
                  icon: Icons.account_balance_wallet,
                  label: 'Account',
                  value: accountName ?? '—'),
              _DetailRow(icon: Icons.category_outlined, label: 'Category', value: t.category),
              if (t.description?.isNotEmpty == true)
                _DetailRow(icon: Icons.notes, label: 'Note', value: t.description!),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close),
                      label: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: ctx,
                          builder: (dctx) => AlertDialog(
                            title: const Text('Delete transaction?'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(dctx, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.expense),
                                onPressed: () => Navigator.pop(dctx, true),
                                child: const Text('Delete'),
                              ),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        await _deleteTxn(t);
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        final accs = ref.read(accountsProvider).value ?? [];
        final txnsList = ref.read(transactionsProvider).value ?? [];
        final categories = txnsList.map((t) => t.category).toSet().toList()..sort();
        return StatefulBuilder(
          builder: (ctx, setSheet) => Padding(
            padding: EdgeInsets.only(
              left: 18,
              right: 18,
              top: 18,
              bottom: 18 + MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).dividerColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Filters', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 16),
                DropdownButtonFormField<TxnType?>(
                  initialValue: _typeFilter,
                  decoration: const InputDecoration(labelText: 'Type'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: TxnType.income, child: Text('Income')),
                    DropdownMenuItem(value: TxnType.expense, child: Text('Expense')),
                  ],
                  onChanged: (v) => setSheet(() => _typeFilter = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _accountFilter,
                  decoration: const InputDecoration(labelText: 'Account'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...accs.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))),
                  ],
                  onChanged: (v) => setSheet(() => _accountFilter = v),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: _categoryFilter,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('All')),
                    ...categories.map((c) => DropdownMenuItem(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setSheet(() => _categoryFilter = v),
                ),
                const SizedBox(height: 10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.date_range),
                  title: Text(_range == null
                      ? 'Date range: All'
                      : '${dateFmt.format(_range!.start)} → ${dateFmt.format(_range!.end)}'),
                  trailing: Wrap(
                    children: [
                      if (_range != null)
                        IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () => setSheet(() => _range = null)),
                      IconButton(
                        icon: const Icon(Icons.edit_calendar),
                        onPressed: () async {
                          final picked = await showDateRangePicker(
                            context: ctx,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (picked != null) setSheet(() => _range = picked);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheet(() {
                            _typeFilter = null;
                            _categoryFilter = null;
                            _accountFilter = null;
                            _range = null;
                          });
                        },
                        child: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {});
                          Navigator.pop(ctx);
                        },
                        child: const Text('Apply'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cs.onSurfaceVariant),
          const SizedBox(width: 12),
          SizedBox(
            width: 84,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.5,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
