import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/finance/money_engine.dart';
import '../../../core/finance/payment_planner.dart';
import '../../../core/finance/snapshot_provider.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../accounts/data/account_repository.dart';
import '../../accounts/domain/account.dart';
import '../../categories/data/category_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../../transactions/data/transaction_repository.dart';
import '../../transactions/domain/transaction.dart';

/// "I need to send GHS 500 — where should it come from?"
///
/// The whole point of the screen is that the answer is worked out, not guessed:
/// the plan below the amount is produced by [planPayment], and every account it
/// declined to use says why.
class PayScreen extends ConsumerStatefulWidget {
  const PayScreen({super.key});

  @override
  ConsumerState<PayScreen> createState() => _PayScreenState();
}

class _PayScreenState extends ConsumerState<PayScreen> {
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  double _amount = 0;
  String? _forcedAccountId;
  String _category = 'Other';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(() {
      final parsed = double.tryParse(_amountCtrl.text) ?? 0;
      if (parsed != _amount) setState(() => _amount = parsed);
    });
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _record(PaymentPlan plan) async {
    setState(() => _saving = true);
    final txnRepo = ref.read(transactionRepositoryProvider);
    final note = _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim();

    try {
      // Move the money into place first, then record what actually left.
      for (final t in plan.transfers) {
        await txnRepo.createTransfer(
          fromAccountId: t.from.id,
          toAccountId: t.to.id,
          amount: t.amount,
          description: note == null ? 'To cover a payment' : 'To cover: $note',
          date: DateTime.now(),
        );
      }

      for (final s in plan.sources) {
        await txnRepo.create(
          accountId: s.account.id,
          type: TxnType.expense,
          amount: s.amount,
          category: _category,
          description: note,
          date: DateTime.now(),
        );
      }

      bumpTransactions(ref);
      bumpAccounts(ref);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recorded ${formatMoney(plan.amount)}'),
          backgroundColor: AppColors.income,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final snapshotAsync = ref.watch(moneySnapshotProvider);
    final obligations = ref.watch(obligationsProvider).value ?? const [];
    final accounts =
        ref.watch(activeAccountsProvider).value ?? const <Account>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Where should this come from?')),
      body: snapshotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (snapshot) {
          final plan = planPayment(
            amount: _amount,
            snapshot: snapshot,
            obligations: obligations,
            payFromAccountId: _forcedAccountId,
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: TextField(
                    controller: _amountCtrl,
                    autofocus: true,
                    textAlign: TextAlign.center,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -1,
                    ),
                    decoration: const InputDecoration(
                      hintText: '0.00',
                      prefixText: 'GHS  ',
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                initialValue: accounts.any((a) => a.id == _forcedAccountId)
                    ? _forcedAccountId
                    : null,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'It has to leave from',
                  prefixIcon: Icon(Icons.outbond_outlined),
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('Anywhere — you decide'),
                  ),
                  for (final a in accounts)
                    DropdownMenuItem<String?>(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _forcedAccountId = v),
              ),
              const SizedBox(height: 12),
              Builder(builder: (_) {
                final categories = ref.watch(expenseCategoryNamesProvider);
                // The default 'Other' is gone the moment someone hides it, so
                // fall back to whatever their list actually starts with —
                // pinned into state, not just the display, so the saved
                // transaction carries the category the user can see.
                if (categories.isNotEmpty && !categories.contains(_category)) {
                  _category = categories.first;
                }
                return DropdownButtonFormField<String>(
                  // Null rather than _category when the list is empty: a
                  // dropdown whose value is not among its items asserts.
                  initialValue:
                      categories.contains(_category) ? _category : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem(value: c, child: Text(c)),
                  ],
                  onChanged: (v) => setState(() => _category = v ?? _category),
                );
              }),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What is it for? (optional)',
                  hintText: 'e.g. Sending to Kwame',
                  prefixIcon: Icon(Icons.notes),
                ),
              ),
              const SizedBox(height: 22),
              _PlanCard(plan: plan, snapshot: snapshot),
              if (plan.isPossible) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: plan.isClean
                        ? AppColors.seed
                        : AppColors.warning,
                  ),
                  onPressed: _saving ? null : () => _record(plan),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check),
                  label: Text(
                    plan.transfers.isEmpty
                        ? 'Record this payment'
                        : 'Move the money and record it',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  plan.transfers.isEmpty
                      ? 'Logs the payment against the account above.'
                      : 'Logs ${plan.transfers.length} transfer'
                          '${plan.transfers.length == 1 ? '' : 's'} and the payment.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final PaymentPlan plan;
  final MoneySnapshot snapshot;

  const _PlanCard({required this.plan, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (color, icon) = plan.isPossible
        ? plan.isClean
            ? (AppColors.seed, Icons.check_circle_outline)
            : (AppColors.warning, Icons.warning_amber_rounded)
        : (AppColors.expense, Icons.block);

    return Card(
      color: color.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: color, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    plan.headline,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),

            // The moves, in the order they have to happen.
            if (plan.transfers.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final t in plan.transfers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.swap_horiz,
                          size: 16, color: AppColors.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${formatMoney(t.amount)}  ${t.from.name} → ${t.to.name}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            if (plan.isSplit) ...[
              const SizedBox(height: 14),
              for (final s in plan.sources)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      const Icon(Icons.arrow_upward,
                          size: 16, color: AppColors.expense),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${formatMoney(s.amount)} from ${s.account.name}',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],

            // What this will cost you, if anything.
            for (final s in plan.sources)
              if (s.caution != null) ...[
                const SizedBox(height: 10),
                Text(
                  s.caution!,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: AppColors.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],

            if (plan.reasoning.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(color: cs.outlineVariant, height: 1),
              const SizedBox(height: 12),
              for (final line in plan.reasoning)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    line,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ),
            ],

            if (plan.isPossible) ...[
              const SizedBox(height: 12),
              _ImpactLine(plan: plan),
            ],
          ],
        ),
      ),
    );
  }
}

/// What the payment leaves behind — the thing worth seeing before you send.
class _ImpactLine extends StatelessWidget {
  final PaymentPlan plan;
  const _ImpactLine({required this.plan});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final impact = plan.impact;
    final shortfall = impact.causesShortfall;

    final text = StringBuffer(
      'Leaves ${formatMoney(impact.safeToSpendAfter)} spendable',
    );
    if (impact.runwayDaysAfter != null && impact.daysUntilIncome != null) {
      text.write(
          ' — about ${impact.runwayDaysAfter!.floor()} days of cash, with income '
          'in ${impact.daysUntilIncome} days.');
    } else {
      text.write('.');
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (shortfall ? AppColors.expense : cs.surfaceContainerHighest)
            .withValues(alpha: shortfall ? 0.12 : 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            shortfall ? Icons.trending_down : Icons.timelapse,
            size: 17,
            color: shortfall ? AppColors.expense : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              shortfall
                  ? '$text You would run short before payday.'
                  : text.toString(),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: shortfall ? FontWeight.w600 : FontWeight.w500,
                color: shortfall ? AppColors.expense : cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
