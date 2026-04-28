import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/category_icons.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/kpi_card.dart';
import '../../../shared/widgets/section_header.dart';
import '../../accounts/data/account_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../insights/presentation/daily_tip_card.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final txns = ref.watch(transactionsProvider);
    final user = ref.watch(authRepositoryProvider).currentUser;
    final email = user?.email ?? '';
    final firstName = email.split('@').first;
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? 'Good morning'
        : hour < 17
            ? 'Good afternoon'
            : 'Good evening';

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            bumpAccounts(ref);
            bumpTransactions(ref);
            await Future.wait([
              ref.read(accountsProvider.future),
              ref.read(transactionsProvider.future),
            ]);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(greet,
                            style: TextStyle(
                                fontSize: 13,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 2),
                        Text(
                          firstName,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () {
                      bumpAccounts(ref);
                      bumpTransactions(ref);
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _BalanceHero(),
              const SizedBox(height: 16),
              _Kpis(),
              const SizedBox(height: 16),
              const DailyTipCard(),
              const SizedBox(height: 22),
              const SectionHeader(title: 'Spending by category'),
              SizedBox(
                height: 240,
                child: txns.when(
                  data: (list) => _CategoryPie(transactions: list),
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                ),
              ),
              const SizedBox(height: 22),
              SectionHeader(
                title: 'Recent transactions',
                action: 'See all',
                onAction: () => context.go('/history'),
              ),
              txns.when(
                data: (list) {
                  final recent = list.take(6).toList();
                  if (recent.isEmpty) {
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long_outlined,
                                color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(width: 12),
                            const Expanded(child: Text('No transactions yet.')),
                          ],
                        ),
                      ),
                    );
                  }
                  final names = (accounts.value ?? [])
                      .fold<Map<String, String>>({}, (m, a) => m..[a.id] = a.name);
                  return Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < recent.length; i++) ...[
                          _TxnTile(t: recent[i], accountName: names[recent[i].accountId]),
                          if (i < recent.length - 1)
                            const Divider(height: 1, indent: 64, endIndent: 12),
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Error: $e'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BalanceHero extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return accounts.when(
      data: (list) {
        final total = list.fold<double>(0, (s, a) => s + a.balance);
        final radius = BorderRadius.circular(22);
        return Material(
          color: Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: () => context.go('/accounts'),
            child: Ink(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: const LinearGradient(
                  colors: [AppColors.gradStart, AppColors.gradEnd],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.gradEnd.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet, color: Colors.white70, size: 18),
                  SizedBox(width: 8),
                  Text('Total balance',
                      style: TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                formatMoney(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '${list.length} account${list.length == 1 ? '' : 's'}',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 140, child: Center(child: CircularProgressIndicator())),
      error: (e, _) => Text('Error: $e'),
    );
  }
}

class _Kpis extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider);
    return txns.when(
      data: (list) {
        final cutoff = DateTime.now().subtract(const Duration(days: 30));
        final last30 = list.where((t) => !t.date.isBefore(cutoff));
        final income = last30
            .where((t) => t.type == TxnType.income)
            .fold<double>(0, (s, t) => s + t.amount);
        final expense = last30
            .where((t) => t.type == TxnType.expense)
            .fold<double>(0, (s, t) => s + t.amount);
        final net = income - expense;
        return Row(
          children: [
            Expanded(
              child: KpiCard(
                label: 'Income (30d)',
                value: formatMoney(income),
                icon: Icons.arrow_downward,
                gradient: const [AppColors.incomeGradStart, AppColors.incomeGradEnd],
                onTap: () => context.go('/history'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KpiCard(
                label: 'Expenses (30d)',
                value: formatMoney(expense),
                icon: Icons.arrow_upward,
                gradient: const [AppColors.expenseGradStart, AppColors.expenseGradEnd],
                onTap: () => context.go('/history'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: KpiCard(
                label: 'Net (30d)',
                value: formatMoney(net),
                icon: net >= 0 ? Icons.trending_up : Icons.trending_down,
                gradient: const [AppColors.netGradStart, AppColors.netGradEnd],
                onTap: () => context.go('/reports'),
              ),
            ),
          ],
        );
      },
      loading: () => const SizedBox(height: 110),
      error: (e, _) => Text('Error: $e'),
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Txn t;
  final String? accountName;
  const _TxnTile({required this.t, this.accountName});

  @override
  Widget build(BuildContext context) {
    final isIncome = t.type == TxnType.income;
    final color = isIncome ? AppColors.income : AppColors.expense;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(iconForCategory(t.category), color: color, size: 22),
      ),
      title: Text(t.category,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(
        '${dateLongFmt.format(t.date)}${accountName != null ? ' • $accountName' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '${isIncome ? '+' : '-'}${formatMoney(t.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }
}

class _CategoryPie extends StatelessWidget {
  final List<Txn> transactions;
  const _CategoryPie({required this.transactions});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthly = transactions
        .where((t) => t.type == TxnType.expense && !t.date.isBefore(monthStart));
    final Map<String, double> byCategory = {};
    for (final t in monthly) {
      byCategory[t.category] = (byCategory[t.category] ?? 0) + t.amount;
    }
    if (byCategory.isEmpty) {
      return Card(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pie_chart_outline,
                  size: 36,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 8),
              const Text('No expenses this month'),
            ],
          ),
        ),
      );
    }
    final entries = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = byCategory.values.fold<double>(0, (s, v) => s + v);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: AspectRatio(
                aspectRatio: 1,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 3,
                    centerSpaceRadius: 44,
                    sections: [
                      for (var i = 0; i < entries.length; i++)
                        PieChartSectionData(
                          value: entries[i].value,
                          title: '${(entries[i].value / total * 100).toStringAsFixed(0)}%',
                          color: AppColors.chart[i % AppColors.chart.length],
                          radius: 42,
                          titleStyle: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < entries.length && i < 5; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: AppColors.chart[i % AppColors.chart.length],
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              entries[i].key,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          Text(formatMoney(entries[i].value),
                              style: const TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
