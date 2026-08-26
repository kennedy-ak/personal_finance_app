import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/finance/money_engine.dart';
import '../../../core/finance/snapshot_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../data/goal_repository.dart';
import '../data/obligation_repository.dart';
import '../domain/goal.dart';
import '../domain/obligation.dart';
import 'goal_editor_sheet.dart';
import 'obligation_editor_sheet.dart';

/// What is already owed, and what is being saved for.
///
/// Until the app knows these, a balance is just a number: the dashboard cannot
/// tell spendable money from money that is already spoken for.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        alignment: Alignment.centerLeft,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () =>
                            context.canPop() ? context.pop() : context.go('/'),
                        icon: Icon(Icons.arrow_back,
                            size: 22, color: t.inkMuted),
                      ),
                      const Spacer(),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _tab == 0
                            ? ObligationEditorSheet.show(context)
                            : GoalEditorSheet.show(context),
                        child: Text('Add',
                            style: AppType.label
                                .copyWith(fontSize: 13, color: t.brandInk)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('Commitments',
                      style: AppType.title.copyWith(color: t.ink)),
                  const SizedBox(height: 16),
                  SegmentedTabs(
                    labels: const ['Bills & income', 'Goals'],
                    index: _tab,
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _tab == 0 ? const _ObligationsTab() : const _GoalsTab(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObligationsTab extends ConsumerWidget {
  const _ObligationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final async = ref.watch(obligationsProvider);
    final snapshot = ref.watch(moneySnapshotProvider).value;
    final accounts = ref.watch(accountsProvider).value ?? [];
    final accountNames = {for (final a in accounts) a.id: a.name};

    return async.when(
      loading: () => Center(child: CircularProgressIndicator(color: t.brandInk)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorCard(
          title: 'Could not load your commitments',
          message: 'Check your connection and try again.',
          onRetry: () => bumpObligations(ref),
        ),
      ),
      data: (list) {
        final active = list.where((o) => o.isActive).toList();
        if (active.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: EmptyCard(
                title: 'Nothing committed yet',
                message: 'Add your rent, subscriptions and salary. Until the '
                    'app knows what is already owed, a balance is just a '
                    'number.',
                actionLabel: 'Add a commitment',
                onAction: () => ObligationEditorSheet.show(context),
              ),
            ),
          );
        }

        final bills = active.where((o) => o.isOutflow).toList()
          ..sort((a, b) => a.nextDue.compareTo(b.nextDue));
        final incomes = active.where((o) => !o.isOutflow).toList()
          ..sort((a, b) => a.nextDue.compareTo(b.nextDue));

        return RefreshIndicator(
          color: t.brandInk,
          backgroundColor: t.card,
          onRefresh: () async {
            bumpObligations(ref);
            await ref.read(obligationsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
            children: [
              if (snapshot != null) ...[
                _CommittedSummary(snapshot: snapshot),
                const SizedBox(height: 16),
              ],
              for (final o in [...bills, ...incomes])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ObligationCard(
                    obligation: o,
                    accountName: accountNames[o.accountId],
                    snapshot: snapshot,
                    onTap: () =>
                        ObligationEditorSheet.show(context, obligation: o),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The point of the whole screen, stated in one card.
class _CommittedSummary extends StatelessWidget {
  final MoneySnapshot snapshot;
  const _CommittedSummary({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final covered = snapshot.usableCash >= snapshot.committed;

    return CediCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('Leaving before ${dayMonthFmt.format(snapshot.horizon)}',
              size: 11, color: t.inkFaint),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(kCurrencyCode,
                  style: AppType.label.copyWith(color: t.inkMuted)),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    moneyDigits(snapshot.committed),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.heroFigure
                        .copyWith(fontSize: 30, letterSpacing: -0.9, color: t.ink),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            covered
                ? 'Your accounts cover all of it. '
                    '${formatMoney(snapshot.safeToSpend)} is left over.'
                : 'That is more than the ${formatMoney(snapshot.usableCash)} '
                    'you can currently reach.',
            style: AppType.bodySmall.copyWith(
                height: 1.5, color: covered ? t.inkMuted : t.expense.ink),
          ),
        ],
      ),
    );
  }
}

/// One bill or one expected income.
///
/// A bill that cannot be paid is the single most useful thing this screen can
/// tell you, so it is the only one that gets a tinted card.
class _ObligationCard extends StatelessWidget {
  final Obligation obligation;
  final String? accountName;
  final MoneySnapshot? snapshot;
  final VoidCallback onTap;

  const _ObligationCard({
    required this.obligation,
    required this.accountName,
    required this.snapshot,
    required this.onTap,
  });

  /// Whether the account this bill is pinned to can actually cover it. A bill
  /// with no pinned account falls back to whether anything can.
  bool get _covered {
    final s = snapshot;
    if (s == null || !obligation.isOutflow) return true;
    final pinned = obligation.accountId;
    if (pinned == null) return s.usableCash >= obligation.amount;
    final standing =
        s.standings.where((x) => x.account.id == pinned).firstOrNull;
    if (standing == null) return s.usableCash >= obligation.amount;
    return standing.available >= obligation.amount;
  }

  double get _shortBy {
    final s = snapshot;
    if (s == null) return 0;
    final pinned = obligation.accountId;
    final standing = pinned == null
        ? null
        : s.standings.where((x) => x.account.id == pinned).firstOrNull;
    final reachable = standing?.available ?? s.usableCash;
    final gap = obligation.amount - reachable;
    return gap > 0 ? gap : 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final income = !obligation.isOutflow;
    final uncovered = obligation.isOutflow && !_covered;

    final tint = income
        ? t.income
        : uncovered
            ? t.expense
            : t.neutral;

    final eyebrow = income
        ? 'Income · ${dayMonthFmt.format(obligation.nextDue)}'
        : '${uncovered ? 'Not covered' : 'Covered'} · '
            'due ${dayMonthFmt.format(obligation.nextDue)}';

    final detail = income
        ? '${accountName == null ? 'No account set' : 'Into $accountName'}, '
            '${obligation.cadence.label.toLowerCase()}'
        : uncovered
            ? '${accountName ?? 'No account'} is short '
                '${formatMoney(_shortBy)} for this.'
            : '${accountName == null ? 'No account set' : 'From $accountName'}, '
                '${obligation.cadence.label.toLowerCase()}';

    return TintCard(
      tint: tint,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(obligation.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowTitle
                            .copyWith(fontSize: 15, color: tint.body)),
                    const SizedBox(height: 7),
                    Eyebrow(eyebrow,
                        size: 10,
                        color: income || uncovered ? tint.muted : t.inkMuted),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(formatMoney(obligation.amount),
                  softWrap: false,
                  style: AppType.figureRow.copyWith(
                      fontSize: 16,
                      color: income || uncovered ? tint.ink : t.ink)),
            ],
          ),
          const SizedBox(height: 9),
          Text(detail,
              style: AppType.rowSub.copyWith(
                  height: 1.45,
                  color: income || uncovered ? tint.muted : t.inkMuted)),
        ],
      ),
    );
  }
}

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final async = ref.watch(goalsProvider);

    return async.when(
      loading: () => Center(child: CircularProgressIndicator(color: t.brandInk)),
      error: (e, _) => Padding(
        padding: const EdgeInsets.all(16),
        child: ErrorCard(
          title: 'Could not load your goals',
          message: 'Check your connection and try again.',
          onRetry: () => bumpGoals(ref),
        ),
      ),
      data: (list) {
        final active = list.where((g) => g.isActive).toList();
        if (active.isEmpty) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: EmptyCard(
                title: 'No goals yet',
                message: 'Money you name is money you keep. A goal is held out '
                    'of safe-to-spend, so it stops being spent by accident.',
                actionLabel: 'Add a goal',
                onAction: () => GoalEditorSheet.show(context),
              ),
            ),
          );
        }

        return RefreshIndicator(
          color: t.brandInk,
          backgroundColor: t.card,
          onRefresh: () async {
            bumpGoals(ref);
            await ref.read(goalsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 112),
            children: [
              for (var i = 0; i < active.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _GoalCard(
                    goal: active[i],
                    index: i,
                    onTap: () => GoalEditorSheet.show(context, goal: active[i]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GoalCard extends StatelessWidget {
  final Goal goal;
  final int index;
  final VoidCallback onTap;

  const _GoalCard(
      {required this.goal, required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final monthly = goal.requiredMonthlyContribution;
    final colour = goal.isComplete
        ? t.income.ink
        : index.isEven
            ? t.brand
            : t.protected;

    return CediCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(goal.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowTitle
                            .copyWith(fontSize: 15, color: t.ink)),
                    const SizedBox(height: 7),
                    Eyebrow(
                      goal.targetDate == null
                          ? 'No target date'
                          : 'Target ${dayMonthFmt.format(goal.targetDate!)}',
                      size: 10,
                      color: t.inkMuted,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text('${(goal.progress * 100).round()}%',
                  style: AppType.figureRow.copyWith(fontSize: 16, color: t.ink)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: goal.progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: t.track,
              valueColor: AlwaysStoppedAnimation(colour),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('${formatMoney(goal.savedAmount)} saved',
                  style: AppType.rowSub.copyWith(height: 1.0, color: t.inkBody)),
              const SizedBox(width: 6),
              Text('of ${formatMoney(goal.targetAmount)}',
                  style:
                      AppType.rowSub.copyWith(height: 1.0, color: t.inkMuted)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            goal.isComplete
                ? 'Funded. It stays out of safe-to-spend until you spend it.'
                : monthly != null
                    ? '${formatMoney(monthly)} a month keeps this on time.'
                    : 'Counted as protected, so it never shows as safe to '
                        'spend.',
            style: AppType.rowSub.copyWith(height: 1.45, color: t.inkMuted),
          ),
        ],
      ),
    );
  }
}
