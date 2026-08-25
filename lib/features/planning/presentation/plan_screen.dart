import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Where the user tells the app what it cannot work out on its own: what is
/// already owed, what is coming in, and what must not be touched.
class PlanScreen extends ConsumerStatefulWidget {
  const PlanScreen({super.key});

  @override
  ConsumerState<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends ConsumerState<PlanScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Commitments'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Bills & income'),
            Tab(text: 'Goals'),
          ],
        ),
      ),
      floatingActionButton: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => FloatingActionButton.extended(
          heroTag: 'plan-fab',
          onPressed: () => _tabs.index == 0
              ? ObligationEditorSheet.show(context)
              : GoalEditorSheet.show(context),
          icon: const Icon(Icons.add),
          label: Text(_tabs.index == 0 ? 'Commitment' : 'Goal'),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_ObligationsTab(), _GoalsTab()],
      ),
    );
  }
}

class _ObligationsTab extends ConsumerWidget {
  const _ObligationsTab();

  Future<void> _delete(BuildContext context, WidgetRef ref, Obligation o) async {
    final ok = await _confirm(context, 'Delete "${o.name}"?');
    if (ok != true) return;
    await ref.read(obligationRepositoryProvider).delete(o.id);
    bumpObligations(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(obligationsProvider);
    final snapshot = ref.watch(moneySnapshotProvider).value;
    final accountNames = {
      for (final a in ref.watch(accountsProvider).value ?? []) a.id: a.name
    };

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return _Empty(
            icon: Icons.event_repeat_outlined,
            title: 'Nothing committed yet',
            message:
                'Add your rent, subscriptions and salary. Until the app knows '
                'what is already owed, a balance is just a number.',
            onAdd: () => ObligationEditorSheet.show(context),
            addLabel: 'Add a commitment',
          );
        }

        final bills = list.where((o) => o.isOutflow && o.isActive).toList();
        final incomes = list.where((o) => !o.isOutflow && o.isActive).toList();

        return RefreshIndicator(
          onRefresh: () async {
            bumpObligations(ref);
            await ref.read(obligationsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              if (snapshot != null) _CommittedSummary(snapshot: snapshot),
              if (bills.isNotEmpty) ...[
                const SizedBox(height: 18),
                const _GroupHeader('Bills'),
                for (final o in bills)
                  _ObligationTile(
                    obligation: o,
                    accountName: accountNames[o.accountId],
                    onEdit: () =>
                        ObligationEditorSheet.show(context, obligation: o),
                    onDelete: () => _delete(context, ref, o),
                  ),
              ],
              if (incomes.isNotEmpty) ...[
                const SizedBox(height: 18),
                const _GroupHeader('Expected income'),
                for (final o in incomes)
                  _ObligationTile(
                    obligation: o,
                    accountName: accountNames[o.accountId],
                    onEdit: () =>
                        ObligationEditorSheet.show(context, obligation: o),
                    onDelete: () => _delete(context, ref, o),
                  ),
              ],
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
    final cs = Theme.of(context).colorScheme;
    final days = snapshot.horizon.difference(snapshot.asOf).inDays;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cs.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Committed in the next $days days',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(snapshot.committed),
            style: const TextStyle(
                fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8),
          ),
          const SizedBox(height: 10),
          Text(
            snapshot.daysUntilIncome == null
                ? 'Add your salary so the app knows when money next arrives.'
                : 'Next income in ${snapshot.daysUntilIncome} days.',
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ObligationTile extends StatelessWidget {
  final Obligation obligation;
  final String? accountName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ObligationTile({
    required this.obligation,
    required this.accountName,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final o = obligation;
    final color = o.isOutflow ? AppColors.expense : AppColors.income;
    final next = o.nextOccurrenceOnOrAfter(DateTime.now());
    final daysAway = next?.difference(DateTime.now()).inDays;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
        onTap: onEdit,
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(o.isOutflow ? Icons.receipt_long : Icons.payments,
              color: color, size: 20),
        ),
        title: Text(o.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        subtitle: Text(
          [
            o.cadence.label,
            if (next != null)
              daysAway != null && daysAway <= 0
                  ? 'due today'
                  : 'in ${daysAway ?? 0} days',
            ?accountName,
          ].join(' • '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${o.isOutflow ? '-' : '+'}${formatMoney(o.amount)}',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 14),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'delete') onDelete();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(
                    value: 'delete',
                    child:
                        Text('Delete', style: TextStyle(color: AppColors.expense))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalsTab extends ConsumerWidget {
  const _GoalsTab();

  Future<void> _delete(BuildContext context, WidgetRef ref, Goal g) async {
    final ok = await _confirm(context, 'Delete "${g.name}"?');
    if (ok != true) return;
    await ref.read(goalRepositoryProvider).delete(g.id);
    bumpGoals(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(goalsProvider);

    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (list) {
        if (list.isEmpty) {
          return _Empty(
            icon: Icons.flag_outlined,
            title: 'No goals yet',
            message:
                'An emergency fund in a current account looks exactly like '
                'grocery money. Name it here and the app will stop offering it.',
            onAdd: () => GoalEditorSheet.show(context),
            addLabel: 'Add a goal',
          );
        }

        final active = list.where((g) => g.isActive).toList();
        final reserved = active.fold<double>(0, (s, g) => s + g.savedAmount);

        return RefreshIndicator(
          onRefresh: () async {
            bumpGoals(ref);
            await ref.read(goalsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 96),
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Held back from spending',
                        style: TextStyle(
                            fontSize: 12.5,
                            color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 6),
                    Text(formatMoney(reserved),
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final g in active)
                _GoalTile(
                  goal: g,
                  onEdit: () => GoalEditorSheet.show(context, goal: g),
                  onDelete: () => _delete(context, ref, g),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _GoalTile extends StatelessWidget {
  final Goal goal;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _GoalTile({
    required this.goal,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final monthly = goal.requiredMonthlyContribution;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(goal.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  Text(
                    '${formatMoney(goal.savedAmount)} / ${formatMoney(goal.targetAmount)}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20),
                    onSelected: (v) {
                      if (v == 'edit') onEdit();
                      if (v == 'delete') onDelete();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete',
                              style: TextStyle(color: AppColors.expense))),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 6),
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
                        ? '${formatMoney(monthly)} a month to hit this on time.'
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

class _GroupHeader extends StatelessWidget {
  final String text;
  const _GroupHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      );
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback onAdd;
  final String addLabel;

  const _Empty({
    required this.icon,
    required this.title,
    required this.message,
    required this.onAdd,
    required this.addLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 44, color: cs.onSurfaceVariant),
            const SizedBox(height: 14),
            Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.45, color: cs.onSurfaceVariant)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: Text(addLabel),
            ),
          ],
        ),
      ),
    );
  }
}

Future<bool?> _confirm(BuildContext context, String title) => showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
