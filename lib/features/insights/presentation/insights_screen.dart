import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/finance/alerts.dart';
import '../../../core/finance/money_engine.dart';
import '../../../core/finance/snapshot_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../planning/domain/goal.dart';
import '../../planning/domain/obligation.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../../dashboard/presentation/widgets/alert_list.dart';
import 'ask_ai_tab.dart';
import 'daily_tip_card.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final txns = ref.watch(transactionsProvider).value ?? const <Txn>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.insights), text: 'Overview'),
            Tab(icon: Icon(Icons.auto_awesome), text: 'Ask AI'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          const _Overview(),
          AskAiTab(accounts: accounts, txns: txns),
        ],
      ),
    );
  }
}

/// Everything here is derived from the user's actual position.
///
/// The previous version padded this screen out with canned finance lessons and
/// a score built from invented constants. None of it said anything about *this*
/// person's money, so none of it survived. A section now appears only when
/// there is something real to put in it.
class _Overview extends ConsumerWidget {
  const _Overview();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(moneySnapshotProvider);
    final alerts = ref.watch(moneyAlertsProvider).value ?? const <MoneyAlert>[];
    final obligations =
        ref.watch(obligationsProvider).value ?? const <Obligation>[];
    final goals = ref.watch(goalsProvider).value ?? const <Goal>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];

    return snapshotAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (s) {
        final gaps = _gaps(
          snapshot: s,
          accounts: accounts,
          obligations: obligations,
          hasSpending: s.spend30d > 0,
        );

        return RefreshIndicator(
          onRefresh: () async {
            bumpAccounts(ref);
            bumpTransactions(ref);
            bumpObligations(ref);
            bumpGoals(ref);
            await ref.read(moneySnapshotProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              if (alerts.isNotEmpty) ...[
                const SectionHeader(title: 'Needs your attention'),
                AlertList(alerts: alerts, collapsedCount: 3),
                const SizedBox(height: 18),
              ],

              if (gaps.isNotEmpty) ...[
                const SectionHeader(title: 'Make this sharper'),
                for (final gap in gaps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GapCard(gap: gap),
                  ),
                const SizedBox(height: 18),
              ],

              // Figures only exist once there is history to compute them from.
              if (s.spend30d > 0 || s.income30d > 0) ...[
                const SectionHeader(title: 'Your numbers'),
                _NumbersGrid(snapshot: s),
                const SizedBox(height: 18),
              ],

              if (goals.any((g) => g.isActive)) ...[
                const SectionHeader(title: 'Goals'),
                for (final g in goals.where((g) => g.isActive))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GoalProgress(goal: g),
                  ),
                const SizedBox(height: 18),
              ],

              const SectionHeader(title: 'Today'),
              const DailyTipCard(),
            ],
          ),
        );
      },
    );
  }
}

/// Something the app cannot work out on its own, with the reason it matters.
class _Gap {
  final IconData icon;
  final String title;
  final String body;
  final String cta;
  final String route;

  const _Gap({
    required this.icon,
    required this.title,
    required this.body,
    required this.cta,
    required this.route,
  });
}

/// Built from what is actually missing, not from a fixed checklist.
///
/// Each entry names the specific thing the app currently cannot do because of
/// it — a setup prompt that cannot say what it unlocks is just nagging.
List<_Gap> _gaps({
  required MoneySnapshot snapshot,
  required List<Account> accounts,
  required List<Obligation> obligations,
  required bool hasSpending,
}) {
  final gaps = <_Gap>[];

  if (accounts.isEmpty) {
    return const [
      _Gap(
        icon: Icons.account_balance_wallet_outlined,
        title: 'Add an account',
        body: 'Nothing can be worked out until the app knows where your money '
            'sits.',
        cta: 'Add an account',
        route: '/accounts',
      ),
    ];
  }

  if (!hasSpending) {
    gaps.add(const _Gap(
      icon: Icons.receipt_long_outlined,
      title: 'Log some spending',
      body: 'Without transactions there is no spending rate, so the app cannot '
          'tell you how long your money lasts.',
      cta: 'Add a transaction',
      route: '/add',
    ));
  }

  if (snapshot.daysUntilIncome == null) {
    gaps.add(const _Gap(
      icon: Icons.event_available_outlined,
      title: 'Record when you get paid',
      body: 'Safe-to-spend is falling back to a flat 30 days. With a real income '
          'date it becomes the amount that has to last until then.',
      cta: 'Add expected income',
      route: '/plan',
    ));
  }

  if (!obligations.any((o) => o.isActive && o.isOutflow)) {
    gaps.add(const _Gap(
      icon: Icons.receipt_outlined,
      title: 'Add your bills',
      body: 'Rent and subscriptions are counted as spendable right now, so your '
          'safe-to-spend is higher than it really is.',
      cta: 'Add a bill',
      route: '/plan',
    ));
  }

  // Only worth raising once there is more than one place money could come from.
  final spendable = accounts.where((a) => a.isSpendable).toList();
  if (spendable.length > 1 && spendable.every((a) => a.minBalance == 0)) {
    gaps.add(const _Gap(
      icon: Icons.shield_outlined,
      title: 'Set a floor on an account',
      body: 'Nothing is protected, so a payment can be suggested from any '
          'account right down to zero.',
      cta: 'Open accounts',
      route: '/accounts',
    ));
  }

  return gaps;
}

class _GapCard extends StatelessWidget {
  final _Gap gap;
  const _GapCard({required this.gap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push(gap.route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(gap.icon, size: 20, color: AppColors.seed),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(gap.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(gap.body,
                  style: TextStyle(
                      fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => context.push(gap.route),
                  child: Text(gap.cta),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The figures worth knowing, each computed by the money engine.
///
/// A tile is skipped when its input does not exist, rather than shown as a
/// confident zero.
class _NumbersGrid extends StatelessWidget {
  final MoneySnapshot snapshot;
  const _NumbersGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final tiles = <_Number>[];

    if (s.income30d > 0) {
      final rate = (s.income30d - s.spend30d) / s.income30d * 100;
      tiles.add(_Number(
        label: 'Kept from income',
        value: '${rate.toStringAsFixed(0)}%',
        sub: '${formatMoney(s.income30d - s.spend30d)} of ${formatMoney(s.income30d)}',
        color: rate >= 0 ? AppColors.income : AppColors.expense,
      ));
    }

    if (s.dailyBurn > 0) {
      tiles.add(_Number(
        label: 'Spending a day',
        value: formatMoney(s.dailyBurn),
        sub: '${formatMoney(s.dailyBurn * 30)} a month at this rate',
        color: AppColors.expense,
      ));
    }

    if (s.runwayDays != null) {
      tiles.add(_Number(
        label: 'Cash lasts',
        value: '${s.runwayDays!.floor()} days',
        sub: s.daysUntilIncome == null
            ? 'no income date recorded'
            : 'income in ${s.daysUntilIncome} days',
        color: s.willFallShort ? AppColors.expense : AppColors.seed,
      ));

      // Months of cover only means something against a real monthly spend.
      final monthly = s.dailyBurn * 30.44;
      if (monthly > 0) {
        final months = (s.liquid + s.reserved) / monthly;
        tiles.add(_Number(
          label: 'Buffer',
          value: '${months.toStringAsFixed(1)} mo',
          sub: 'of spending covered',
          color: months >= 3 ? AppColors.income : AppColors.warning,
        ));
      }
    }

    if (s.committed > 0) {
      tiles.add(_Number(
        label: 'Committed',
        value: formatMoney(s.committed),
        sub: 'before ${dateLongFmt.format(s.horizon)}',
        color: AppColors.warning,
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          children: [
            for (var i = 0; i < tiles.length; i++) ...[
              _NumberRow(number: tiles[i]),
              if (i < tiles.length - 1) const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
  }
}

class _Number {
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _Number({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });
}

class _NumberRow extends StatelessWidget {
  final _Number number;
  const _NumberRow({required this.number});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(number.label,
                    style: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(number.sub,
                    style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          Text(
            number.value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: number.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalProgress extends StatelessWidget {
  final Goal goal;
  const _GoalProgress({required this.goal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthly = goal.requiredMonthlyContribution;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => context.push('/plan'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(goal.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14.5)),
                  ),
                  Text(
                    '${(goal.progress * 100).round()}%',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 8,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(
                      goal.isComplete ? AppColors.income : AppColors.seed),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                goal.isComplete
                    ? 'Funded.'
                    : monthly != null
                        ? '${formatMoney(goal.remaining)} to go — '
                            '${formatMoney(monthly)} a month to land on time.'
                        : '${formatMoney(goal.remaining)} to go.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
