import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/account_repository.dart';
import '../domain/account.dart';
import 'account_editor_sheet.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _showCreate(BuildContext context, WidgetRef ref) =>
      AccountEditorSheet.show(context);

  Future<void> _showEdit(BuildContext context, WidgetRef ref, Account a) =>
      AccountEditorSheet.show(context, account: a);

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Account a) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${a.name}"?'),
        content: const Text('All transactions on this account will also be deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(accountRepositoryProvider).delete(a.id);
      bumpAccounts(ref);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'accounts-fab',
        onPressed: () => _showCreate(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: accounts.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.account_balance_outlined,
              title: 'No accounts yet',
              message: 'Tap the + button to create your first account.',
              action: FilledButton.icon(
                onPressed: () => _showCreate(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Create account'),
              ),
            );
          }
          final total = list.fold<double>(0, (s, a) => s + a.balance);
          return RefreshIndicator(
            onRefresh: () async {
              bumpAccounts(ref);
              await ref.read(accountsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [AppColors.gradStart, AppColors.gradEnd],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total across all accounts',
                          style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 8),
                      Text(formatMoney(total),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                          )),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: ListTile(
                    onTap: () => context.push('/plan'),
                    leading: const Icon(Icons.event_repeat_outlined,
                        color: AppColors.seed),
                    title: const Text('Commitments & goals',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
                    subtitle: const Text(
                      'Bills, expected income and money you will not touch',
                      style: TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                if (list.length > 1) ...[
                  const SizedBox(height: 18),
                  const SectionHeader(title: 'Distribution'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: SizedBox(
                        height: 180,
                        child: Row(
                          children: [
                            Expanded(
                              child: PieChart(
                                PieChartData(
                                  sectionsSpace: 3,
                                  centerSpaceRadius: 36,
                                  sections: [
                                    for (var i = 0; i < list.length; i++)
                                      PieChartSectionData(
                                        value: list[i].balance.abs() < 0.01
                                            ? 0.001
                                            : list[i].balance,
                                        color: AppColors.chart[i % AppColors.chart.length],
                                        radius: 40,
                                        title: total > 0
                                            ? '${(list[i].balance / total * 100).toStringAsFixed(0)}%'
                                            : '',
                                        titleStyle: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  for (var i = 0; i < list.length; i++)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: AppColors.chart[i % AppColors.chart.length],
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(list[i].name,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12)),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const SectionHeader(title: 'Accounts'),
                for (final a in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showEdit(context, ref, a),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: AppColors.seed.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(_iconFor(a.kind), color: AppColors.seed),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600, fontSize: 15)),
                                    const SizedBox(height: 3),
                                    _AccountStatusLine(account: a),
                                  ],
                                ),
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(formatMoney(a.balance),
                                      style: const TextStyle(
                                          fontSize: 16, fontWeight: FontWeight.w700)),
                                  if (a.minBalance > 0)
                                    Text(
                                      '${formatMoney(a.available)} free',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (v) {
                                  if (v == 'edit') _showEdit(context, ref, a);
                                  if (v == 'delete') _confirmDelete(context, ref, a);
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
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

IconData _iconFor(AccountKind kind) => switch (kind) {
      AccountKind.bank => Icons.account_balance,
      AccountKind.momo => Icons.phone_android,
      AccountKind.cash => Icons.payments_outlined,
      AccountKind.savings => Icons.savings_outlined,
      AccountKind.investment => Icons.trending_up,
      AccountKind.credit => Icons.credit_card,
    };

/// The one-line answer to "what is this money doing?".
class _AccountStatusLine extends StatelessWidget {
  final Account account;
  const _AccountStatusLine({required this.account});

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;

    final (String text, Color color) = switch (account) {
      final a when a.isBelowFloor => (
          'Below your ${formatMoney(a.minBalance)} floor',
          AppColors.expense,
        ),
      final a when a.liquidity == Liquidity.locked => (
          '${a.kind.label} • Locked',
          muted,
        ),
      final a when a.liquidity == Liquidity.reserved => (
          '${a.kind.label} • Reserved',
          AppColors.warning,
        ),
      final a when a.purpose != null && a.purpose!.isNotEmpty => (
          a.purpose!,
          muted,
        ),
      final a => ('${a.kind.label} • Spendable', muted),
    };

    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 11.5, color: color),
    );
  }
}
