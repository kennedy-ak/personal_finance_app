import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/finance/alerts.dart';
import '../../../core/finance/money_engine.dart';
import '../../../core/finance/snapshot_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../dashboard/presentation/widgets/alert_list.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../planning/domain/goal.dart';
import '../../planning/domain/obligation.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import 'ask_ai_tab.dart';
import 'daily_tip_card.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];
    final txns = ref.watch(transactionsProvider).value ?? const <Txn>[];

    // Ask AI runs edge to edge — its composer is pinned to the bottom and it
    // owns its own header, so the shared chrome would only get in the way.
    if (_tab == 1) {
      return Scaffold(
        backgroundColor: t.canvas,
        body: SafeArea(
          bottom: false,
          child: AskAiTab(
            accounts: accounts,
            txns: txns,
            onBackToOverview: () => setState(() => _tab = 0),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Insights', style: AppType.title.copyWith(color: t.ink)),
                  const SizedBox(height: 18),
                  SegmentedTabs(
                    labels: const ['Overview', 'Ask AI'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ],
              ),
            ),
            const Expanded(child: _Overview()),
          ],
        ),
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
    final t = CediTokens.of(context);
    final snapshotAsync = ref.watch(moneySnapshotProvider);
    final alerts = ref.watch(moneyAlertsProvider).value ?? const <MoneyAlert>[];
    final obligations =
        ref.watch(obligationsProvider).value ?? const <Obligation>[];
    final goals = ref.watch(goalsProvider).value ?? const <Goal>[];
    final accounts = ref.watch(accountsProvider).value ?? const <Account>[];

    return snapshotAsync.when(
      loading: () => Center(child: CircularProgressIndicator(color: t.brandInk)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorCard(
          title: 'Could not work out your position',
          message: 'Check your connection and try again.',
          onRetry: () => bumpAccounts(ref),
        ),
      ),
      data: (s) {
        final gaps = _gaps(
          snapshot: s,
          accounts: accounts,
          obligations: obligations,
          hasSpending: s.spend30d > 0,
        );
        final activeGoals = goals.where((g) => g.isActive).toList();

        return RefreshIndicator(
          color: t.brandInk,
          backgroundColor: t.card,
          onRefresh: () async {
            bumpAccounts(ref);
            bumpTransactions(ref);
            bumpObligations(ref);
            bumpGoals(ref);
            await ref.read(moneySnapshotProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
            children: [
              const DailyTipCard(),

              if (alerts.isNotEmpty) ...[
                const SizedBox(height: 18),
                AlertList(
                  alerts: alerts,
                  collapsedCount: 3,
                  heading: 'Needs your attention',
                ),
              ],

              if (gaps.isNotEmpty) ...[
                const SizedBox(height: 18),
                const SectionRow(title: 'Make this sharper'),
                const SizedBox(height: 10),
                RowGroup(
                  children: [for (final gap in gaps) _GapRow(gap: gap)],
                ),
              ],

              // Figures only exist once there is history to compute them from.
              if (s.spend30d > 0 || s.income30d > 0) ...[
                const SizedBox(height: 18),
                const SectionRow(title: 'Your numbers'),
                const SizedBox(height: 10),
                _NumbersGrid(snapshot: s),
              ],

              if (activeGoals.isNotEmpty) ...[
                const SizedBox(height: 18),
                SectionRow(
                  title: 'Goals',
                  action: 'Edit',
                  onAction: () => context.push('/plan'),
                ),
                const SizedBox(height: 10),
                CediCard(
                  onTap: () => context.push('/plan'),
                  child: Column(
                    children: [
                      for (var i = 0; i < activeGoals.length; i++) ...[
                        if (i > 0) const SizedBox(height: 14),
                        _GoalMeter(goal: activeGoals[i], index: i),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Something the app cannot work out on its own, with the reason it matters.
class _Gap {
  final String title;
  final String body;
  final String route;

  const _Gap({required this.title, required this.body, required this.route});
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
        title: 'Add an account',
        body: 'Nothing can be worked out until the app knows where your money '
            'sits.',
        route: '/accounts',
      ),
    ];
  }

  if (!hasSpending) {
    gaps.add(const _Gap(
      title: 'Log some spending',
      body: 'Without transactions there is no spending rate, so the app cannot '
          'tell you how long your money lasts.',
      route: '/add',
    ));
  }

  if (snapshot.daysUntilIncome == null) {
    gaps.add(const _Gap(
      title: 'Record when you get paid',
      body: 'Safe-to-spend is falling back to a flat 30 days. With a real '
          'income date it becomes the amount that has to last until then.',
      route: '/plan',
    ));
  }

  if (!obligations.any((o) => o.isActive && o.isOutflow)) {
    gaps.add(const _Gap(
      title: 'Add your bills',
      body: 'Rent and subscriptions are counted as spendable right now, so '
          'your safe-to-spend is higher than it really is.',
      route: '/plan',
    ));
  }

  // Only worth raising once there is more than one place money could come from.
  final spendable = accounts.where((a) => a.isSpendable).toList();
  if (spendable.length > 1 && spendable.every((a) => a.minBalance == 0)) {
    gaps.add(_Gap(
      title: 'Set a floor on ${spendable.first.name}',
      body: 'Nothing is protected, so a payment can be suggested from any '
          'account right down to zero.',
      route: '/accounts',
    ));
  }

  return gaps;
}

class _GapRow extends StatelessWidget {
  final _Gap gap;
  const _GapRow({required this.gap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return InkWell(
      onTap: () => context.push(gap.route),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(gap.title,
                      style: AppType.rowTitle.copyWith(color: t.ink)),
                  const SizedBox(height: 4),
                  Text(gap.body,
                      style: AppType.rowSub
                          .copyWith(height: 1.4, color: t.inkMuted)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Icon(Icons.arrow_forward, size: 16, color: t.brandInk),
          ],
        ),
      ),
    );
  }
}

/// The figures worth knowing, each computed by the money engine.
///
/// A tile is skipped when its input does not exist, rather than shown as a
/// confident zero. Money tiles put the currency code on its own line, the same
/// way every other figure in the app does.
class _NumbersGrid extends StatelessWidget {
  final MoneySnapshot snapshot;
  const _NumbersGrid({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final tiles = <_NumberTile>[];

    if (s.income30d > 0) {
      final kept = (s.income30d - s.spend30d) / s.income30d * 100;
      tiles.add(_NumberTile(
        label: 'Kept of income',
        value: '${kept.round()}%',
      ));
    }

    if (s.dailyBurn > 0) {
      tiles.add(_NumberTile(label: 'Spending a day', amount: s.dailyBurn));
    }

    if (s.runwayDays != null) {
      tiles.add(_NumberTile(
        label: 'Cash lasts',
        value: '${s.runwayDays!.floor()} days',
      ));
    }

    if (s.committed > 0) {
      tiles.add(_NumberTile(label: 'Committed', amount: s.committed));
    }

    final txnCount = s.categories.length;
    if (txnCount > 0 && s.spend30d > 0) {
      tiles.add(_NumberTile(
        label: 'Biggest category',
        value: s.categories.first.category,
        small: true,
      ));
    }

    if (tiles.isEmpty) return const SizedBox.shrink();

    // An odd tile out would leave a hole in a two-column grid, so the last one
    // takes the full width instead.
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      final left = tiles[i];
      final right = i + 1 < tiles.length ? tiles[i + 1] : null;
      // IntrinsicHeight, not bare `stretch`: this grid is a direct child of a
      // ListView, which hands its children an unbounded height. A stretching
      // Row would pass that straight down as a tight infinite constraint and
      // the scroll extent would run off the end of the screen.
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: left),
            if (right != null) ...[
              const SizedBox(width: 8),
              Expanded(child: right),
            ],
          ],
        ),
      ));
    }

    return Column(
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          rows[i],
        ],
      ],
    );
  }
}

class _NumberTile extends StatelessWidget {
  final String label;

  /// Either a plain [value] or a money [amount] — never both.
  final String? value;
  final double? amount;

  /// Shrinks the figure for values that are words rather than numbers.
  final bool small;

  const _NumberTile({
    required this.label,
    this.value,
    this.amount,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return CediCard(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.figureLabel
                  .copyWith(fontSize: 11, height: 1.3, color: t.inkMuted)),
          const SizedBox(height: 8),
          if (amount != null) ...[
            Text(kCurrencyCode,
                style: AppType.currencyCode.copyWith(color: t.inkFaint)),
            const SizedBox(height: 3),
          ],
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              amount != null ? moneyDigits(amount!) : value!,
              maxLines: 1,
              softWrap: false,
              style: AppType.figure.copyWith(
                fontSize: small ? 16 : (amount != null ? 18 : 20),
                letterSpacing: -0.4,
                color: t.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoalMeter extends StatelessWidget {
  final Goal goal;
  final int index;

  const _GoalMeter({required this.goal, required this.index});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return ProgressMeter(
      label: goal.name,
      trailing: '${moneyDigits(goal.savedAmount)} / ${moneyDigits(goal.targetAmount)}',
      fraction: goal.progress,
      color: goal.isComplete
          ? t.income.ink
          : index.isEven
              ? t.brand
              : t.protected,
    );
  }
}
