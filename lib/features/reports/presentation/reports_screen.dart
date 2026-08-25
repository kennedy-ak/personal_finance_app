import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/kpi_card.dart';
import '../../../shared/widgets/section_header.dart';
import '../../accounts/data/account_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  DateTime _selectedWeek = _weekStart(DateTime.now());

  static DateTime _weekStart(DateTime d) {
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return DateTime(monday.year, monday.month, monday.day);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final txns = ref.watch(transactionsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'This week'),
            Tab(text: 'Trends'),
            Tab(text: 'Detailed'),
          ],
        ),
      ),
      body: txns.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => TabBarView(
          controller: _tab,
          children: [
            _CurrentWeekTab(transactions: list),
            _TrendsTab(transactions: list),
            _DetailedTab(
              transactions: list,
              week: _selectedWeek,
              onPick: (d) => setState(() => _selectedWeek = _weekStart(d)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekStats {
  final double income;
  final double expense;
  final int count;
  const _WeekStats(this.income, this.expense, this.count);
  double get net => income - expense;
}

_WeekStats _statsFor(List<Txn> txns, DateTime weekStart) {
  final end = weekStart.add(const Duration(days: 7));
  double inc = 0, exp = 0;
  int n = 0;
  for (final t in txns) {
    if (!t.isRealMoneyMovement) continue;
    if (!t.date.isBefore(weekStart) && t.date.isBefore(end)) {
      if (t.isIncome) {
        inc += t.amount;
      } else {
        exp += t.amount;
      }
      n++;
    }
  }
  return _WeekStats(inc, exp, n);
}

class _CurrentWeekTab extends StatelessWidget {
  final List<Txn> transactions;
  const _CurrentWeekTab({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final start = _ReportsScreenState._weekStart(DateTime.now());
    final stats = _statsFor(transactions, start);
    return ListView(
      // Clears the docked add button at the bottom of the screen.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Week of ${dateLongFmt.format(start)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(formatMoney(stats.net),
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: stats.net >= 0 ? AppColors.income : AppColors.expense,
                      letterSpacing: -1,
                    )),
                Text('${stats.count} transactions',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Income',
                value: formatMoney(stats.income),
                icon: Icons.arrow_downward,
                gradient: const [AppColors.incomeGradStart, AppColors.incomeGradEnd],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KpiCard(
                label: 'Expenses',
                value: formatMoney(stats.expense),
                icon: Icons.arrow_upward,
                gradient: const [AppColors.expenseGradStart, AppColors.expenseGradEnd],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const SectionHeader(title: 'Daily breakdown'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 220,
              child: _DailyBars(weekStart: start, transactions: transactions),
            ),
          ),
        ),
      ],
    );
  }
}

class _DailyBars extends StatelessWidget {
  final DateTime weekStart;
  final List<Txn> transactions;
  const _DailyBars({required this.weekStart, required this.transactions});

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));
    final inc = List.filled(7, 0.0);
    final exp = List.filled(7, 0.0);
    for (final t in transactions) {
      if (!t.isRealMoneyMovement) continue;
      for (var i = 0; i < 7; i++) {
        final d = days[i];
        if (t.date.year == d.year && t.date.month == d.month && t.date.day == d.day) {
          if (t.isIncome) {
            inc[i] += t.amount;
          } else {
            exp[i] += t.amount;
          }
        }
      }
    }
    final maxV = [...inc, ...exp].fold<double>(0, (m, v) => v > m ? v : m);
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return BarChart(
      BarChartData(
        maxY: maxV == 0 ? 10 : maxV * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(labels[v.toInt()],
                    style: const TextStyle(fontSize: 11)),
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < 7; i++)
            BarChartGroupData(x: i, barsSpace: 4, barRods: [
              BarChartRodData(toY: inc[i], color: AppColors.income, width: 8, borderRadius: BorderRadius.circular(3)),
              BarChartRodData(toY: exp[i], color: AppColors.expense, width: 8, borderRadius: BorderRadius.circular(3)),
            ]),
        ],
      ),
    );
  }
}

class _TrendsTab extends StatelessWidget {
  final List<Txn> transactions;
  const _TrendsTab({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final thisWeekStart = _ReportsScreenState._weekStart(today);
    final weeks = List.generate(
        12, (i) => thisWeekStart.subtract(Duration(days: 7 * (11 - i))));
    final stats = weeks.map((w) => _statsFor(transactions, w)).toList();
    final maxV = stats.fold<double>(
        0, (m, s) => [s.income, s.expense, m].reduce((a, b) => a > b ? a : b));

    return ListView(
      // Clears the docked add button at the bottom of the screen.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        const SectionHeader(title: '12-week trend'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 240,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxV == 0 ? 10 : maxV * 1.2,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: Theme.of(context).dividerColor, strokeWidth: 0.5),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          getTitlesWidget: (v, _) => Text(
                                v >= 1000 ? '${(v / 1000).toStringAsFixed(0)}k' : v.toStringAsFixed(0),
                                style: const TextStyle(fontSize: 10),
                              )),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        interval: 2,
                        getTitlesWidget: (v, _) {
                          final i = v.toInt();
                          if (i < 0 || i >= weeks.length) return const SizedBox();
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('W${i + 1}',
                                style: const TextStyle(fontSize: 10)),
                          );
                        },
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [for (var i = 0; i < stats.length; i++) FlSpot(i.toDouble(), stats[i].income)],
                      color: AppColors.income,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      isCurved: true,
                    ),
                    LineChartBarData(
                      spots: [for (var i = 0; i < stats.length; i++) FlSpot(i.toDouble(), stats[i].expense)],
                      color: AppColors.expense,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      isCurved: true,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _legend('Income', AppColors.income),
            const SizedBox(width: 18),
            _legend('Expenses', AppColors.expense),
          ],
        ),
        const SizedBox(height: 22),
        const SectionHeader(title: 'Last 12 weeks'),
        for (var i = stats.length - 1; i >= 0; i--)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text('Week of ${dateLongFmt.format(weeks[i])}',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              subtitle: Text(
                  'In ${formatMoney(stats[i].income)} • Out ${formatMoney(stats[i].expense)}',
                  style: const TextStyle(fontSize: 11)),
              trailing: Text(
                formatMoney(stats[i].net),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: stats[i].net >= 0 ? AppColors.income : AppColors.expense,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _legend(String label, Color color) => Row(
        children: [
          Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

class _DetailedTab extends ConsumerWidget {
  final List<Txn> transactions;
  final DateTime week;
  final ValueChanged<DateTime> onPick;
  const _DetailedTab({required this.transactions, required this.week, required this.onPick});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final end = week.add(const Duration(days: 6));
    final stats = _statsFor(transactions, week);
    final inWeek = transactions
        .where((t) => !t.date.isBefore(week) && t.date.isBefore(week.add(const Duration(days: 7))));

    final byCat = <String, double>{};
    for (final t in inWeek.where((t) => t.isSpending)) {
      byCat[t.category] = (byCat[t.category] ?? 0) + t.amount;
    }
    final catEntries = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    final accounts = ref.watch(accountsProvider).value ?? [];
    final accountNames = {for (final a in accounts) a.id: a.name};
    final byAcc = <String, _WeekStats>{};
    for (final a in accounts) {
      final s = _statsFor(inWeek.where((t) => t.accountId == a.id).toList(), week);
      byAcc[a.id] = s;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.calendar_today),
            title: Text('${dateLongFmt.format(week)} – ${dateLongFmt.format(end)}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: week,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) onPick(picked);
            },
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Income',
                value: formatMoney(stats.income),
                icon: Icons.arrow_downward,
                gradient: const [AppColors.incomeGradStart, AppColors.incomeGradEnd],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KpiCard(
                label: 'Expense',
                value: formatMoney(stats.expense),
                icon: Icons.arrow_upward,
                gradient: const [AppColors.expenseGradStart, AppColors.expenseGradEnd],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KpiCard(
                label: 'Net',
                value: formatMoney(stats.net),
                icon: stats.net >= 0 ? Icons.trending_up : Icons.trending_down,
                gradient: const [AppColors.netGradStart, AppColors.netGradEnd],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        const SectionHeader(title: 'By category'),
        if (catEntries.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No expenses this week.')))
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < catEntries.length; i++) ...[
                  ListTile(
                    leading: Container(
                      width: 10,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.chart[i % AppColors.chart.length],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    title: Text(catEntries[i].key),
                    subtitle: Text(
                        '${(catEntries[i].value / stats.expense * 100).toStringAsFixed(0)}% of expenses'),
                    trailing: Text(formatMoney(catEntries[i].value),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  if (i < catEntries.length - 1) const Divider(height: 1, indent: 32, endIndent: 12),
                ],
              ],
            ),
          ),
        const SizedBox(height: 22),
        const SectionHeader(title: 'By account'),
        if (accountNames.isEmpty)
          const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No accounts.')))
        else
          Card(
            child: Column(
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: Text(accounts[i].name),
                    subtitle: Text(
                        'In ${formatMoney(byAcc[accounts[i].id]!.income)} • Out ${formatMoney(byAcc[accounts[i].id]!.expense)}'),
                    trailing: Text(formatMoney(byAcc[accounts[i].id]!.net),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: byAcc[accounts[i].id]!.net >= 0 ? AppColors.income : AppColors.expense,
                        )),
                  ),
                  if (i < accounts.length - 1) const Divider(height: 1, indent: 60, endIndent: 12),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
