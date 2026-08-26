import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../data/transaction_repository.dart';
import '../domain/transaction.dart';
import 'history_filter_sheet.dart';
import 'txn_style.dart';

/// The ledger, grouped by day.
///
/// A flat list of 124 rows is a wall. Grouping by day with a subtotal per day
/// turns it into something you can scan: most people are looking for a
/// particular day's damage, not a particular row.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  final _searchCtrl = TextEditingController();
  HistoryFilters _filters = const HistoryFilters();
  String _search = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final txns = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider);
    final names = {
      for (final a in accounts.value ?? []) a.id as String: a.name as String,
    };

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        bottom: false,
        child: txns.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: t.brandInk)),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorCard(
              title: 'Could not load your transactions',
              message: 'Check your connection and try again.',
              onRetry: () => bumpTransactions(ref),
            ),
          ),
          data: (all) {
            final filtered = _filter(all, names);
            final days = _groupByDay(filtered);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text('History',
                                style: AppType.title.copyWith(color: t.ink)),
                          ),
                          Text(
                            '${filtered.length} ${filtered.length == 1 ? 'ROW' : 'ROWS'}',
                            style: AppType.monoCaption
                                .copyWith(fontSize: 12, color: t.inkFaint),
                          ),
                          if (filtered.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Export CSV',
                              visualDensity: VisualDensity.compact,
                              icon: Icon(Icons.ios_share,
                                  size: 19, color: t.inkMuted),
                              onPressed: () => _exportCsv(filtered, names),
                            ),
                          ],
                        ],
                      ),
                      if (all.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        SearchRow(
                          controller: _searchCtrl,
                          hint: 'Search description or amount',
                          filterCount: _filters.count,
                          onChanged: (v) => setState(() => _search = v),
                          onFilter: () => _openFilters(all, names),
                        ),
                      ],
                      if (_filters.count > 0) ...[
                        const SizedBox(height: 12),
                        _ActiveFilters(
                          filters: _filters,
                          accountNames: names,
                          onChanged: (f) => setState(() => _filters = f),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: all.isEmpty
                      ? _EmptyHistory(onAdd: () => context.push('/add'))
                      : filtered.isEmpty
                          ? _NoResults(
                              query: _search,
                              filterCount: _filters.count,
                              total: all.length,
                              onClear: () => setState(() {
                                _filters = const HistoryFilters();
                                _search = '';
                                _searchCtrl.clear();
                              }),
                            )
                          : RefreshIndicator(
                              color: t.brandInk,
                              backgroundColor: t.card,
                              onRefresh: () async {
                                bumpTransactions(ref);
                                await ref.read(transactionsProvider.future);
                              },
                              child: ListView.builder(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 4, 16, 112),
                                itemCount: days.length,
                                itemBuilder: (_, i) => Padding(
                                  padding:
                                      EdgeInsets.only(top: i == 0 ? 6 : 18),
                                  child: _DayGroup(
                                    day: days[i],
                                    names: names,
                                    onTap: _showDetails,
                                  ),
                                ),
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

  Future<void> _openFilters(
      List<Txn> all, Map<String, String> names) async {
    final accounts = ref.read(accountsProvider).value ?? [];
    final categories = all.map((t) => t.category).toSet().toList()..sort();

    final result = await showHistoryFilterSheet(
      context: context,
      current: _filters,
      accounts: {for (final a in accounts) a.id: a.name},
      categories: categories,
      countFor: (f) => _filter(all, names, override: f).length,
    );
    if (result != null) setState(() => _filters = result);
  }

  List<Txn> _filter(List<Txn> list, Map<String, String> names,
      {HistoryFilters? override}) {
    final f = override ?? _filters;
    final s = _search.trim().toLowerCase();
    return list.where((t) {
      if (!f.matches(t)) return false;
      if (s.isEmpty) return true;
      // Amount is searchable too: people remember "that 264 one" far more
      // often than they remember what they typed in the note.
      final hay = '${t.category} ${t.description ?? ''} '
              '${names[t.accountId] ?? ''} ${t.amount.toStringAsFixed(2)}'
          .toLowerCase();
      return hay.contains(s);
    }).toList();
  }

  static List<_Day> _groupByDay(List<Txn> rows) {
    final byDay = <DateTime, List<Txn>>{};
    for (final t in rows) {
      final key = DateTime(t.date.year, t.date.month, t.date.day);
      (byDay[key] ??= []).add(t);
    }
    final keys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    return [for (final k in keys) _Day(k, byDay[k]!)];
  }

  Future<void> _exportCsv(
      List<Txn> rows, Map<String, String> accountNames) async {
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
    final file = File(
        '${dir.path}/transactions_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csvText);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], text: 'Transactions export'),
    );
  }

  Future<void> _deleteTxn(Txn t) async {
    // Balances are derived in the database — deleting the row is enough, and
    // both sides of a transfer settle themselves.
    await ref.read(transactionRepositoryProvider).delete(t.id);
    bumpTransactions(ref);
    bumpAccounts(ref);
  }

  Future<void> _showDetails(Txn t) async {
    final names = {
      for (final a in ref.read(accountsProvider).value ?? [])
        a.id as String: a.name as String,
    };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TxnDetailSheet(
        txn: t,
        accountName: names[t.accountId],
        toAccountName: names[t.toAccountId],
        onDelete: () async {
          final ok = await showDeleteConfirmation(
            context: ctx,
            title: 'Delete this transaction?',
            message: '${titleForTxn(t, fromName: names[t.accountId], toName: names[t.toAccountId])} · '
                '${formatMoney(t.amount)} will be removed and your balances '
                'will settle back.',
          );
          if (ok != true) return;
          await _deleteTxn(t);
          if (ctx.mounted) Navigator.pop(ctx);
        },
      ),
    );
  }
}

class _Day {
  final DateTime date;
  final List<Txn> rows;
  const _Day(this.date, this.rows);

  /// Money in minus money out. Transfers move between your own pockets, so
  /// they contribute nothing.
  double get net => rows.fold<double>(
      0,
      (sum, t) => sum +
          (t.isIncome
              ? t.amount
              : t.isSpending
                  ? -t.amount
                  : 0));
}

class _DayGroup extends StatelessWidget {
  final _Day day;
  final Map<String, String> names;
  final ValueChanged<Txn> onTap;

  const _DayGroup(
      {required this.day, required this.names, required this.onTap});

  static String _label(DateTime d) {
    final today = DateTime.now();
    final t0 = DateTime(today.year, today.month, today.day);
    final diff = t0.difference(d).inDays;
    final stamp = dayMonthFmt.format(d);
    if (diff == 0) return 'Today · $stamp';
    if (diff == 1) return 'Yesterday · $stamp';
    return stamp;
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final net = day.net;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DayHeader(
          label: _label(day.date),
          amount: formatMoney(net),
          // Only a losing day earns red. A day of transfers, or a day that
          // came out ahead, has nothing to warn about.
          amountColor: net < 0
              ? t.expense.ink
              : net > 0
                  ? t.income.ink
                  : t.inkMuted,
        ),
        RowGroup(
          children: [
            for (final txn in day.rows)
              _HistoryRow(txn: txn, names: names, onTap: () => onTap(txn)),
          ],
        ),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final Txn txn;
  final Map<String, String> names;
  final VoidCallback onTap;

  const _HistoryRow(
      {required this.txn, required this.names, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final transfer = txn.type == TxnType.transfer;
    final accountName = names[txn.accountId];

    return TxnRow(
      onTap: onTap,
      leading: CategoryGlyph(
        name: txn.category,
        hue: txn.category.hashCode,
        neutral: transfer,
      ),
      title: txn.description?.isNotEmpty == true
          ? txn.description!
          : titleForTxn(txn,
              fromName: accountName, toName: names[txn.toAccountId]),
      subtitle: [
        if (transfer)
          'Transfer'
        else ...[
          ?accountName,
          txn.category,
        ],
        timeFmt.format(txn.date),
      ].join(' · '),
      amount: '${signForTxn(txn.type)}${formatMoney(txn.amount)}',
      amountColor: switch (txn.type) {
        TxnType.income => t.income.ink,
        TxnType.expense => t.expense.ink,
        TxnType.transfer => t.inkMuted,
      },
    );
  }
}

/// The chips that show what is currently filtering the list, each one its own
/// off switch.
class _ActiveFilters extends StatelessWidget {
  final HistoryFilters filters;
  final Map<String, String> accountNames;
  final ValueChanged<HistoryFilters> onChanged;

  const _ActiveFilters({
    required this.filters,
    required this.accountNames,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (filters.type != null) ...[
            SelectChip(
              label: filters.type!.label,
              selected: true,
              compact: true,
              onTap: () => onChanged(filters.copyWith(clearType: true)),
            ),
            const SizedBox(width: 7),
          ],
          if (filters.accountId != null) ...[
            SelectChip(
              label: accountNames[filters.accountId] ?? 'Account',
              selected: true,
              compact: true,
              onTap: () => onChanged(filters.copyWith(clearAccount: true)),
            ),
            const SizedBox(width: 7),
          ],
          if (filters.category != null) ...[
            SelectChip(
              label: filters.category!,
              selected: true,
              compact: true,
              onTap: () => onChanged(filters.copyWith(clearCategory: true)),
            ),
            const SizedBox(width: 7),
          ],
          SelectChip(
            label: 'Clear',
            selected: false,
            compact: true,
            onTap: () => onChanged(const HistoryFilters()),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyHistory({required this.onAdd});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
        child: Align(
          alignment: Alignment.topCenter,
          child: EmptyCard(
            title: 'No transactions yet',
            message: 'Log one payment and the dashboard can start telling you '
                'what is safe to spend.',
            actionLabel: 'Add transaction',
            onAction: onAdd,
          ),
        ),
      );
}

/// The search came back with nothing — and the reason is usually the filters,
/// so the screen says so and offers the one tap that fixes it.
class _NoResults extends StatelessWidget {
  final String query;
  final int filterCount;
  final int total;
  final VoidCallback onClear;

  const _NoResults({
    required this.query,
    required this.filterCount,
    required this.total,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final trimmed = query.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 112),
      child: Align(
        alignment: Alignment.topCenter,
        child: DottedBorderBox(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                trimmed.isEmpty
                    ? 'Nothing matches those filters'
                    : 'Nothing matches “$trimmed”',
                textAlign: TextAlign.center,
                style: AppType.rowTitle.copyWith(fontSize: 16, color: t.ink),
              ),
              const SizedBox(height: 8),
              Text(
                filterCount == 0
                    ? 'Try a shorter search, or a different word.'
                    : '$filterCount filter${filterCount == 1 ? ' is' : 's are'} '
                        'still on. Clearing ${filterCount == 1 ? 'it' : 'them'} '
                        'searches all $total rows.',
                textAlign: TextAlign.center,
                style: AppType.body.copyWith(height: 1.55, color: t.inkMuted),
              ),
              const SizedBox(height: 16),
              SecondaryButton(
                label: filterCount == 0 ? 'Clear search' : 'Clear filters',
                filled: Theme.of(context).brightness == Brightness.light,
                onPressed: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One transaction, in full, with the one destructive action it allows.
class _TxnDetailSheet extends StatelessWidget {
  final Txn txn;
  final String? accountName;
  final String? toAccountName;
  final Future<void> Function() onDelete;

  const _TxnDetailSheet({
    required this.txn,
    required this.accountName,
    required this.toAccountName,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final tint = switch (txn.type) {
      TxnType.income => t.income,
      TxnType.expense => t.expense,
      TxnType.transfer => t.neutral,
    };

    return SheetSurface(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CategoryGlyph(
                  name: txn.category,
                  hue: txn.category.hashCode,
                  size: 44,
                  neutral: txn.type == TxnType.transfer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        titleForTxn(txn,
                            fromName: accountName, toName: toAccountName),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowTitle
                            .copyWith(fontSize: 17, color: t.ink),
                      ),
                      const SizedBox(height: 4),
                      Eyebrow(txn.type.label, color: t.inkMuted),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TintCard(
              tint: tint,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(kCurrencyCode,
                      style:
                          AppType.currencyCode.copyWith(color: tint.muted)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      moneyDigits(txn.isSpending ? -txn.amount : txn.amount),
                      maxLines: 1,
                      softWrap: false,
                      style: AppType.heroFigure
                          .copyWith(fontSize: 34, color: tint.ink),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _DetailRow(label: 'Date', value: dateLongFmt.format(txn.date)),
            _DetailRow(label: 'Time', value: timeFmt.format(txn.date)),
            _DetailRow(label: 'Account', value: accountName ?? '—'),
            if (toAccountName != null)
              _DetailRow(label: 'To', value: toAccountName!),
            _DetailRow(label: 'Category', value: txn.category),
            if (txn.description?.isNotEmpty == true)
              _DetailRow(label: 'Note', value: txn.description!),
            const SizedBox(height: 20),
            DangerButton(label: 'Delete transaction', onPressed: onDelete),
            const SizedBox(height: 10),
            SecondaryButton(
              label: 'Close',
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(label,
                style: AppType.label.copyWith(color: t.inkMuted)),
          ),
          Expanded(
            child: Text(value,
                style: AppType.rowTitle.copyWith(height: 1.3, color: t.ink)),
          ),
        ],
      ),
    );
  }
}
