import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/design/sheets.dart';
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
/// declined to use says why. When the money genuinely is not there, the screen
/// refuses and shows where it is tied up instead of failing silently.
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
      final parsed = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
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
        SnackBar(content: Text('Recorded ${formatMoney(plan.amount)}')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not record that. Nothing moved.')),
      );
    }
  }

  Future<void> _pickSource(List<Account> accounts) async {
    final chosen = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'It has to leave from'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              SelectChip(
                label: 'Anywhere — you decide',
                selected: _forcedAccountId == null,
                onTap: () => Navigator.pop(ctx, '__any__'),
              ),
              for (final a in accounts)
                SelectChip(
                  label: a.name,
                  selected: _forcedAccountId == a.id,
                  onTap: () => Navigator.pop(ctx, a.id),
                ),
            ],
          ),
        ],
      ),
    );
    if (chosen == null) return;
    setState(() => _forcedAccountId = chosen == '__any__' ? null : chosen);
  }

  Future<void> _pickCategory() async {
    final categories = ref.read(expenseCategoryNamesProvider);
    final chosen = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'Category'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final c in categories)
                SelectChip(
                  label: c,
                  selected: c == _category,
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ],
      ),
    );
    if (chosen != null) setState(() => _category = chosen);
  }

  Future<void> _pickNote() async {
    final ctrl = TextEditingController(text: _noteCtrl.text);
    final saved = await showEditorSheet<String>(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetHeader(title: 'What is it for?'),
          const SizedBox(height: 16),
          SheetField(
            label: 'Description',
            controller: ctrl,
            hint: 'Sending to Kwame',
            autofocus: true,
          ),
          const SizedBox(height: 20),
          PrimaryButton(
            label: 'Done',
            onPressed: () => Navigator.pop(ctx, ctrl.text),
          ),
        ],
      ),
    );
    if (saved != null) setState(() => _noteCtrl.text = saved);
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final snapshotAsync = ref.watch(moneySnapshotProvider);
    final obligations = ref.watch(obligationsProvider).value ?? const [];
    final accounts =
        ref.watch(activeAccountsProvider).value ?? const <Account>[];

    // The default 'Other' is gone the moment someone hides it, so fall back to
    // whatever their list actually starts with.
    final categories = ref.watch(expenseCategoryNamesProvider);
    if (categories.isNotEmpty && !categories.contains(_category)) {
      _category = categories.first;
    }

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        child: snapshotAsync.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: t.brandInk)),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorCard(
              title: 'Could not work out your position',
              message: 'Check your connection and try again.',
              onRetry: () => bumpAccounts(ref),
            ),
          ),
          data: (snapshot) {
            final plan = planPayment(
              amount: _amount,
              snapshot: snapshot,
              obligations: obligations,
              payFromAccountId: _forcedAccountId,
            );
            final forced =
                accounts.where((a) => a.id == _forcedAccountId).firstOrNull;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          alignment: Alignment.centerLeft,
                          onPressed: () => context.canPop()
                              ? context.pop()
                              : context.go('/'),
                          icon: Icon(Icons.arrow_back,
                              size: 22, color: t.inkMuted),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text('Where should this come from?',
                          style: AppType.title.copyWith(color: t.ink)),
                      const SizedBox(height: 8),
                      Text(
                        _subtitle(),
                        style: AppType.bodySmall
                            .copyWith(height: 1.5, color: t.inkMuted),
                      ),
                      const SizedBox(height: 16),
                      _AmountField(controller: _amountCtrl),
                      const SizedBox(height: 12),
                      RowGroup(
                        children: [
                          PickerRow(
                            label: 'It has to leave from',
                            value: forced?.name ?? 'Anywhere — you decide',
                            onTap: () => _pickSource(accounts),
                          ),
                          PickerRow(
                            label: 'Category',
                            value: _category,
                            onTap: _pickCategory,
                          ),
                          PickerRow(
                            label: 'What is it for?',
                            value: _noteCtrl.text.isEmpty
                                ? 'Optional'
                                : _noteCtrl.text,
                            onTap: _pickNote,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (_amount <= 0)
                        const EmptyCard(
                          title: 'Enter an amount',
                          message: 'Type what you need to send and this works '
                              'out where it should come from.',
                        )
                      else if (plan.isPossible) ...[
                        _Verdict(plan: plan),
                        const SizedBox(height: 16),
                        _WhyNotOthers(
                          plan: plan,
                          snapshot: snapshot,
                          obligations: obligations,
                        ),
                      ] else
                        _Refusal(
                          plan: plan,
                          snapshot: snapshot,
                          onReviewHolds: () => context.push('/plan'),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
                  child: _amount <= 0
                      ? const SizedBox.shrink()
                      : plan.isPossible
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                PrimaryButton(
                                  label: plan.transfers.isEmpty
                                      ? 'Record this payment'
                                      : 'Move the money and record it',
                                  loading: _saving,
                                  onPressed:
                                      _saving ? null : () => _record(plan),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  plan.transfers.isEmpty
                                      ? 'Logs the payment against the account '
                                          'above.'
                                      : 'Logs ${plan.transfers.length} transfer'
                                          '${plan.transfers.length == 1 ? '' : 's'} '
                                          'and the payment.',
                                  textAlign: TextAlign.center,
                                  style: AppType.bodySmall.copyWith(
                                      fontSize: 12, color: t.inkFaint),
                                ),
                              ],
                            )
                          : SecondaryButton(
                              label: 'Try a smaller amount',
                              filled: Theme.of(context).brightness ==
                                  Brightness.light,
                              onPressed: () {
                                _amountCtrl.clear();
                                FocusScope.of(context).requestFocus(FocusNode());
                              },
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  String _subtitle() {
    final note = _noteCtrl.text.trim();
    if (_amount <= 0) {
      return note.isEmpty ? 'Nothing entered yet' : note;
    }
    return note.isEmpty
        ? formatMoney(_amount)
        : '$note · ${formatMoney(_amount)}';
  }
}

class _AmountField extends StatelessWidget {
  final TextEditingController controller;
  const _AmountField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return CediCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: Column(
        children: [
          Eyebrow('Amount', color: t.inkFaint),
          const SizedBox(height: 10),
          MoneyField(
            label: 'Amount',
            controller: controller,
            autofocus: true,
            hero: true,
          ),
        ],
      ),
    );
  }
}

/// The answer: one account, why it, and what the payment leaves behind.
class _Verdict extends StatelessWidget {
  final PaymentPlan plan;
  const _Verdict({required this.plan});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = plan.isClean ? t.safe : t.warning;
    final source = plan.sources.firstOrNull;

    return TintCard(
      tint: tint,
      radius: 20,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: tint.ink, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Eyebrow(
                plan.transfers.isNotEmpty
                    ? 'Move it first'
                    : plan.isSplit
                        ? 'Split it'
                        : 'Pay from',
                color: plan.isClean
                    ? (dark ? const Color(0xFF6FDCBF) : tint.ink)
                    : tint.muted,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            plan.isSplit || plan.transfers.isNotEmpty || source == null
                ? plan.headline
                : source.account.name,
            style: AppType.title.copyWith(
              fontSize: plan.isSplit || plan.transfers.isNotEmpty ? 19 : 24,
              height: plan.isSplit || plan.transfers.isNotEmpty ? 1.35 : 1.2,
              letterSpacing: -0.5,
              color: plan.isClean && dark
                  ? const Color(0xFFBFEEE2)
                  : tint.body,
            ),
          ),
          if (!plan.isSplit &&
              plan.transfers.isEmpty &&
              source != null) ...[
            const SizedBox(height: 8),
            Text(plan.headline,
                style:
                    AppType.bodySmall.copyWith(height: 1.5, color: tint.muted)),
          ],
          if (source?.caution != null) ...[
            const SizedBox(height: 8),
            Text(source!.caution!,
                style:
                    AppType.bodySmall.copyWith(height: 1.5, color: tint.muted)),
          ],
          if (plan.transfers.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final transfer in plan.transfers)
              Text(
                '${transfer.from.name} → ${transfer.to.name} · '
                '${formatMoney(transfer.amount)}',
                style: AppType.bodySmall
                    .copyWith(height: 1.5, color: tint.muted),
              ),
          ],
          const SizedBox(height: 14),
          if (source != null)
            Row(
              children: [
                Expanded(
                  child: _MiniStat(
                    label: 'Balance now',
                    amount: source.account.balance,
                    tint: tint,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniStat(
                    label: 'After paying',
                    amount: source.account.balance - source.amount,
                    tint: tint,
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
          _ImpactLine(plan: plan),
        ],
      ),
    );
  }
}

/// A figure inside a tinted card, on a slightly lifted plate. Never a
/// saturated fill — the plate is a white wash at 5%, so the figure keeps the
/// card's own ink.
class _MiniStat extends StatelessWidget {
  final String label;
  final double amount;
  final SemanticTint tint;

  const _MiniStat(
      {required this.label, required this.amount, required this.tint});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: dark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.white.withValues(alpha: 0.55),
        borderRadius: Radii.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppType.figureLabel.copyWith(color: tint.muted)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(formatMoney(amount),
                maxLines: 1,
                softWrap: false,
                style: AppType.figureRow.copyWith(
                    color: dark ? t.ink : tint.body)),
          ),
        ],
      ),
    );
  }
}

/// What the payment does to the rest of the month.
class _ImpactLine extends StatelessWidget {
  final PaymentPlan plan;
  const _ImpactLine({required this.plan});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
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

    return Text(
      shortfall ? '$text You would run short before payday.' : text.toString(),
      style: AppType.bodySmall.copyWith(
        height: 1.45,
        fontWeight: shortfall ? FontWeight.w600 : FontWeight.w500,
        color: shortfall ? t.expense.ink : t.inkMuted,
      ),
    );
  }
}

/// Every account that was passed over, with the reason.
///
/// This is what turns a recommendation into a decision the user can check.
class _WhyNotOthers extends StatelessWidget {
  final PaymentPlan plan;
  final MoneySnapshot snapshot;
  final List<dynamic> obligations;

  const _WhyNotOthers({
    required this.plan,
    required this.snapshot,
    required this.obligations,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final lines = plan.reasoning;
    if (lines.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Eyebrow('Why not the others', size: 11, color: t.inkFaint),
        const SizedBox(height: 10),
        CediCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < lines.length; i++) ...[
                if (i > 0)
                  Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 14),
                      color: t.rule),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  child: Text(lines[i],
                      style: AppType.bodySmall
                          .copyWith(height: 1.45, color: t.inkBody)),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The money is not there.
///
/// A refusal is only useful if it says how far short you are and where the
/// rest of the money is sitting, so the user can decide what to release.
class _Refusal extends StatelessWidget {
  final PaymentPlan plan;
  final MoneySnapshot snapshot;
  final VoidCallback onReviewHolds;

  const _Refusal({
    required this.plan,
    required this.snapshot,
    required this.onReviewHolds,
  });

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final free = snapshot.usableCash > 0 ? snapshot.usableCash : 0.0;
    final short = plan.amount - free;
    final holds = <(String, double)>[
      if (snapshot.floors > 0) ('Floors on your accounts', snapshot.floors),
      if (snapshot.goalReserve > 0) ('Money held for goals', snapshot.goalReserve),
      if (snapshot.reserved > 0) ('Reserved accounts', snapshot.reserved),
      if (snapshot.locked > 0) ('Locked accounts', snapshot.locked),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TintCard(
          tint: t.expense,
          radius: 20,
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: t.expense.ink, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Eyebrow('No account can do this', color: t.expense.muted),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'You hold ${formatMoney(snapshot.totalBalance)}, but only '
                '${formatMoney(free)} of it is free. This payment is '
                '${formatMoney(short > 0 ? short : 0)} short.',
                style: AppType.label.copyWith(
                    fontSize: 17, height: 1.4, color: t.expense.body),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _MiniStat(
                        label: 'Free to use', amount: free, tint: t.expense),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MiniStat(
                        label: 'Short by',
                        amount: short > 0 ? short : 0,
                        tint: t.expense),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // The headline the planner produced, kept verbatim so the
              // refusal reads the same wherever it appears.
              Text(plan.headline,
                  style: AppType.bodySmall
                      .copyWith(height: 1.45, color: t.expense.muted)),
            ],
          ),
        ),
        if (holds.isNotEmpty) ...[
          const SizedBox(height: 16),
          TintCard(
            tint: t.warning,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('If you release a hold', color: t.warning.muted),
                const SizedBox(height: 9),
                Text(
                  'Releasing the holds below would free up to '
                  '${formatMoney(holds.fold<double>(0, (s, h) => s + h.$2))}. '
                  'Nothing is released until you say so.',
                  style: AppType.body
                      .copyWith(height: 1.5, color: t.warning.body),
                ),
                const SizedBox(height: 13),
                Material(
                  color: Colors.transparent,
                  borderRadius: Radii.sm,
                  child: InkWell(
                    borderRadius: Radii.sm,
                    onTap: onReviewHolds,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        borderRadius: Radii.sm,
                        border: Border.all(
                            color: t.warning.ink.withValues(alpha: 0.45)),
                      ),
                      child: Text('Review those holds',
                          textAlign: TextAlign.center,
                          style: AppType.button
                              .copyWith(fontSize: 14, color: t.warning.ink)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          CediCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow('Where the money is tied up',
                    size: 11, color: t.inkFaint),
                const SizedBox(height: 10),
                for (var i = 0; i < holds.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(holds[i].$1,
                            style: AppType.bodySmall
                                .copyWith(height: 1.4, color: t.inkBody)),
                      ),
                      const SizedBox(width: 10),
                      Text(formatMoney(holds[i].$2),
                          softWrap: false,
                          style: AppType.figureRow
                              .copyWith(fontSize: 13, color: t.ink)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
