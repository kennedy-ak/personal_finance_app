import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/finance/snapshot_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
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

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshotAsync = ref.watch(moneySnapshotProvider);
    final alertsAsync = ref.watch(moneyAlertsProvider);
    final txns = ref.watch(transactionsProvider);
    final accounts = ref.watch(accountsProvider);
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
          onRefresh: () => _refresh(ref),
          child: ListView(
            // Bottom padding clears the docked add button, which otherwise
            // sits on top of the last card.
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
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
                    onPressed: () => _refresh(ref),
                  ),
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => context.push('/settings'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // What you can actually spend, and whether it will hold.
              snapshotAsync.when(
                data: (s) => SafeToSpendHero(snapshot: s),
                loading: () => const SizedBox(
                    height: 190, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => _ErrorCard(message: '$e'),
              ),
              const SizedBox(height: 12),

              // The question the app exists to answer, one tap away.
              OutlinedButton.icon(
                onPressed: () => context.push('/pay'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  foregroundColor: AppColors.seed,
                  side: BorderSide(color: AppColors.seed.withValues(alpha: 0.45)),
                ),
                icon: const Icon(Icons.alt_route, size: 20),
                label: const Text('I need to pay someone — where from?',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 16),

              // What the app has noticed, before anything it merely reports.
              alertsAsync.maybeWhen(
                data: (alerts) => AlertList(alerts: alerts),
                orElse: () => const SizedBox.shrink(),
              ),

              snapshotAsync.maybeWhen(
                data: (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 22),
                  child: MoneyPlacementBar(snapshot: s),
                ),
                orElse: () => const SizedBox.shrink(),
              ),

              const SectionHeader(title: 'Spending'),
              snapshotAsync.when(
                data: (s) => SpendingMovement(snapshot: s),
                loading: () => const SizedBox(
                    height: 160, child: Center(child: CircularProgressIndicator())),
                error: (e, _) => _ErrorCard(message: '$e'),
              ),
              const SizedBox(height: 22),

              SectionHeader(
                title: 'Recent transactions',
                action: 'See all',
                onAction: () => context.go('/history'),
              ),
              txns.when(
                data: (list) {
                  final recent = list.take(4).toList();
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
                          _TxnTile(t: recent[i], names: names),
                          if (i < recent.length - 1)
                            const Divider(height: 1, indent: 64, endIndent: 12),
                        ],
                      ],
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorCard(message: '$e'),
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

class _TxnTile extends StatelessWidget {
  final Txn t;
  final Map<String, String> names;
  const _TxnTile({required this.t, required this.names});

  @override
  Widget build(BuildContext context) {
    final color = colorForTxn(t.type);
    final accountName = names[t.accountId];

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(iconForTxn(t), color: color, size: 22),
      ),
      title: Text(
        titleForTxn(t, fromName: accountName, toName: names[t.toAccountId]),
        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      subtitle: Text(
        '${dateLongFmt.format(t.date)}${accountName != null ? ' • $accountName' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: Text(
        '${signForTxn(t.type)}${formatMoney(t.amount)}',
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 14),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  const _ErrorCard({required this.message});

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.expense.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: AppColors.expense),
              const SizedBox(width: 12),
              Expanded(child: Text(message, style: const TextStyle(fontSize: 12.5))),
            ],
          ),
        ),
      );
}
