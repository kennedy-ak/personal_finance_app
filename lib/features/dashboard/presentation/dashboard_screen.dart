import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/finance/snapshot_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../auth/data/auth_repository.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';
import '../../transactions/presentation/txn_style.dart';
import 'widgets/alert_list.dart';
import 'widgets/money_placement_bar.dart';
import 'widgets/safe_to_spend_hero.dart';
import 'widgets/spending_movement.dart';

/// One screen, one question: what can I spend, and is anything about to break?
///
/// It has two shapes. The ordinary one reports and then offers the pay
/// question. The shortfall one stops reporting, names what would close the
/// gap, and puts the two things you can do about it under your thumb.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final snapshotAsync = ref.watch(moneySnapshotProvider);
    final alertsAsync = ref.watch(moneyAlertsProvider);
    final txns = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider);
    final name = ref.watch(authRepositoryProvider).displayName;
    final snapshot = snapshotAsync.value;
    final shortfall = snapshot != null && snapshot.safeToSpend < 0;

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () => _refresh(ref),
          color: t.brandInk,
          backgroundColor: t.card,
          child: ListView(
            // Bottom padding clears the docked add button, which otherwise
            // sits on top of the last card.
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
            children: [
              _Greeting(name: name, onRefresh: () => _refresh(ref)),
              const SizedBox(height: 20),

              // What you can actually spend, and whether it will hold.
              snapshotAsync.when(
                data: (s) => SafeToSpendHero(snapshot: s),
                loading: () => const _HeroSkeleton(),
                error: (e, _) => ErrorCard(
                  title: 'Could not work out your position',
                  message: '$e',
                  onRetry: () => _refresh(ref),
                ),
              ),

              if (!shortfall) ...[
                const SizedBox(height: 20),
                // The question the app exists to answer, one tap away.
                BrandPromptButton(
                  label: 'I need to pay someone — where from?',
                  onPressed: () => context.push('/pay'),
                ),
              ],

              // What the app has noticed, before anything it merely reports.
              alertsAsync.maybeWhen(
                data: (alerts) => alerts.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 20),
                        child: AlertList(
                          alerts: alerts,
                          heading: shortfall
                              ? 'What closes the gap'
                              : 'Needs a decision',
                        ),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),

              // In the shortfall case the actions come before the reporting.
              // Nothing below this point changes what the user should do next.
              if (shortfall) ...[
                const SizedBox(height: 20),
                PrimaryButton(
                  label: 'Work through the gap',
                  onPressed: () => context.push('/plan'),
                ),
                const SizedBox(height: 9),
                SecondaryButton(
                  label: 'I need to pay someone — where from?',
                  filled: Theme.of(context).brightness == Brightness.light,
                  onPressed: () => context.push('/pay'),
                ),
              ],

              if (snapshot != null) ...[
                const SizedBox(height: 20),
                MoneyPlacementBar(snapshot: snapshot),
                const SizedBox(height: 20),
                SpendingMovement(snapshot: snapshot),
              ],

              const SizedBox(height: 20),
              SectionRow(
                title: 'Recent',
                action: 'See all',
                onAction: () => context.go('/history'),
              ),
              const SizedBox(height: 8),
              txns.when(
                data: (list) {
                  final recent = list.take(4).toList();
                  if (recent.isEmpty) {
                    return EmptyCard(
                      title: 'Nothing here yet',
                      message: 'Add your first transaction and the dashboard '
                          'starts working.',
                      actionLabel: 'Add transaction',
                      onAction: () => context.push('/add'),
                    );
                  }
                  final names = (accounts.value ?? [])
                      .fold<Map<String, String>>({}, (m, a) => m..[a.id] = a.name);
                  return RowGroup(
                    children: [
                      for (final txn in recent)
                        _TxnTile(t: txn, names: names),
                    ],
                  );
                },
                loading: () => const _RowsSkeleton(),
                error: (e, _) => ErrorCard(
                  title: 'Could not load your transactions',
                  message: 'Check your connection and try again.',
                  onRetry: () => _refresh(ref),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh(WidgetRef ref) async {
    bumpAccounts(ref);
    bumpTransactions(ref);
    bumpObligations(ref);
    bumpGoals(ref);
    await Future.wait([
      ref.read(accountsProvider.future),
      ref.read(transactionsProvider.future),
      ref.read(obligationsProvider.future),
      ref.read(goalsProvider.future),
    ]);
  }
}

/// Time of day plus a first name. It is the one place the app is warm, and it
/// earns that by being the only place.
class _Greeting extends StatelessWidget {
  final String? name;
  final VoidCallback onRefresh;

  const _Greeting({required this.name, required this.onRefresh});

  static String _dayPart(DateTime now) {
    final weekday = <String>[
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ][now.weekday - 1];
    final part = now.hour < 12
        ? 'morning'
        : now.hour < 17
            ? 'afternoon'
            : 'evening';
    return '$weekday $part';
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_dayPart(DateTime.now()),
                  style: AppType.bodySmall
                      .copyWith(height: 1.0, color: t.inkMuted)),
              const SizedBox(height: 5),
              Text(
                name == null ? 'Hello' : 'Hello, $name',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.title.copyWith(color: t.ink),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconAction(
            icon: Icons.refresh, tooltip: 'Refresh', onPressed: onRefresh),
        const SizedBox(width: 8),
        IconAction(
          icon: Icons.settings_outlined,
          tooltip: 'Settings',
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }
}

class _TxnTile extends StatelessWidget {
  final Txn t;
  final Map<String, String> names;
  const _TxnTile({required this.t, required this.names});

  @override
  Widget build(BuildContext context) {
    final tokens = CediTokens.of(context);
    final accountName = names[t.accountId];
    final transfer = t.type == TxnType.transfer;

    final color = switch (t.type) {
      TxnType.income => tokens.income.ink,
      TxnType.expense => tokens.expense.ink,
      TxnType.transfer => tokens.inkMuted,
    };

    return TxnRow(
      leading: CategoryGlyph(
        name: t.category,
        hue: t.category.hashCode,
        neutral: transfer,
      ),
      title: titleForTxn(t, fromName: accountName, toName: names[t.toAccountId]),
      subtitle: [
        ?accountName,
        dayMonthFmt.format(t.date),
      ].join(' · '),
      amount: '${signForTxn(t.type)}${formatMoney(t.amount)}',
      amountColor: color,
    );
  }
}

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Container(
      height: 226,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: Radii.lg,
        border: Border.all(color: t.hairline),
      ),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: t.brandInk),
        ),
      ),
    );
  }
}

class _RowsSkeleton extends StatelessWidget {
  const _RowsSkeleton();

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: t.card,
        borderRadius: Radii.md,
        border: Border.all(color: t.hairline),
      ),
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: t.brandInk),
        ),
      ),
    );
  }
}
