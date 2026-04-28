import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../../shared/widgets/section_header.dart';
import '../data/account_repository.dart';
import '../domain/account.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  Future<void> _showCreate(BuildContext context, WidgetRef ref) async {
    final nameCtrl = TextEditingController();
    final balCtrl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Name', prefixIcon: Icon(Icons.label_outline))),
            const SizedBox(height: 12),
            TextField(
              controller: balCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Starting balance', prefixText: 'GHS '),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      try {
        await ref.read(accountRepositoryProvider).create(
              nameCtrl.text.trim(),
              double.tryParse(balCtrl.text) ?? 0,
            );
        bumpAccounts(ref);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
        }
      }
    }
  }

  Future<void> _showEdit(BuildContext context, WidgetRef ref, Account a) async {
    final nameCtrl = TextEditingController(text: a.name);
    final balCtrl = TextEditingController(text: a.balance.toStringAsFixed(2));
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Name')),
            const SizedBox(height: 12),
            TextField(
              controller: balCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Balance', prefixText: 'GHS '),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Delete', style: TextStyle(color: Colors.red))),
          TextButton(onPressed: () => Navigator.pop(ctx, 'cancel'), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Save')),
        ],
      ),
    );

    final repo = ref.read(accountRepositoryProvider);
    try {
      if (action == 'save') {
        if (nameCtrl.text.trim() != a.name) {
          await repo.rename(a.id, nameCtrl.text.trim());
        }
        final newBal = double.tryParse(balCtrl.text) ?? a.balance;
        if (newBal != a.balance) await repo.updateBalance(a.id, newBal);
        bumpAccounts(ref);
      } else if (action == 'delete') {
        if (!context.mounted) return;
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
        if (confirm == true) {
          await repo.delete(a.id);
          bumpAccounts(ref);
        }
      }
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
                                child: const Icon(Icons.account_balance_wallet,
                                    color: AppColors.seed),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(a.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600, fontSize: 15)),
                                    const SizedBox(height: 2),
                                    Text(
                                      a.balance < 100
                                          ? 'Low balance'
                                          : 'Active',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: a.balance < 100
                                            ? AppColors.warning
                                            : Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Text(formatMoney(a.balance),
                                  style: const TextStyle(
                                      fontSize: 16, fontWeight: FontWeight.w700)),
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right),
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
