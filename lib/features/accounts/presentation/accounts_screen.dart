import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/design/components.dart';
import '../../../core/formatters.dart';
import '../../../core/theme.dart';
import '../../planning/data/goal_repository.dart';
import '../../planning/data/obligation_repository.dart';
import '../data/account_repository.dart';
import '../domain/account.dart';
import 'account_editor_sheet.dart';

/// Where the money actually is, and how much of it you are allowed to touch.
///
/// Balance alone is the number that misleads. Every card here says what the
/// account is, how fast you can reach it, and what the floor holds back — so
/// the total at the top and the safe-to-spend on the dashboard can differ
/// without either looking wrong.
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final accounts = ref.watch(accountsProvider);

    return Scaffold(
      backgroundColor: t.canvas,
      body: SafeArea(
        bottom: false,
        child: accounts.when(
          loading: () =>
              Center(child: CircularProgressIndicator(color: t.brandInk)),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: ErrorCard(
              title: 'Could not load your accounts',
              message: 'Check your connection and try again.',
              onRetry: () => bumpAccounts(ref),
            ),
          ),
          data: (list) {
            final active = list.where((a) => !a.isArchived).toList();
            if (active.isEmpty) return _FirstRun(onAdd: (kind) => _add(context, kind));

            return RefreshIndicator(
              color: t.brandInk,
              backgroundColor: t.card,
              onRefresh: () async {
                bumpAccounts(ref);
                await ref.read(accountsProvider.future);
              },
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 112),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Accounts',
                            style: AppType.title.copyWith(color: t.ink)),
                      ),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _add(context, null),
                        child: Text('Add',
                            style: AppType.label
                                .copyWith(fontSize: 13, color: t.brandInk)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _Distribution(accounts: active),
                  const SizedBox(height: 18),
                  for (var i = 0; i < active.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _AccountCard(
                      account: active[i],
                      onTap: () =>
                          AccountEditorSheet.show(context, account: active[i]),
                    ),
                  ],
                  if (list.any((a) => a.isArchived)) ...[
                    const SizedBox(height: 18),
                    const SectionRow(title: 'Archived'),
                    const SizedBox(height: 8),
                    for (final a in list.where((a) => a.isArchived))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ArchivedCard(
                          account: a,
                          onTap: () =>
                              AccountEditorSheet.show(context, account: a),
                        ),
                      ),
                  ],
                  const SizedBox(height: 18),
                  _CommitmentsLink(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, AccountKind? kind) =>
      AccountEditorSheet.show(context, initialKind: kind);
}

/// The total, and how it is split between the places it sits.
class _Distribution extends StatelessWidget {
  final List<Account> accounts;
  const _Distribution({required this.accounts});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final total = accounts.fold<double>(0, (s, a) => s + a.balance);
    final withBalance = accounts.where((a) => a.balance > 0).toList()
      ..sort((a, b) => b.balance.compareTo(a.balance));

    return CediCard(
      radius: 18,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                    moneyDigits(total),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.heroFigure
                        .copyWith(fontSize: 30, letterSpacing: -0.9, color: t.ink),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'across ${accounts.length} '
                'account${accounts.length == 1 ? '' : 's'}',
                style: AppType.rowSub.copyWith(height: 1.0, color: t.inkMuted),
              ),
            ],
          ),
          if (withBalance.isNotEmpty) ...[
            const SizedBox(height: 14),
            StackedBar(
              slices: [
                for (var i = 0; i < withBalance.length; i++)
                  BarSlice(withBalance[i].balance,
                      AppColors.chart[i % AppColors.chart.length]),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                for (var i = 0; i < withBalance.length; i++)
                  _LegendChip(
                    color: AppColors.chart[i % AppColors.chart.length],
                    label: withBalance[i].name,
                    percent: total <= 0
                        ? 0
                        : (withBalance[i].balance / total * 100).round(),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final int percent;

  const _LegendChip(
      {required this.color, required this.label, required this.percent});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Text('$label $percent%',
            style: AppType.rowSub.copyWith(height: 1.0, color: t.inkMuted)),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;

  const _AccountCard({required this.account, required this.onTap});

  /// "BANK · LIQUID IN 1 DAY" — kind and reach, in one mono line. Reach is the
  /// part that decides whether this account can cover something tomorrow.
  String get _kindLine {
    final reach = switch (account.liquidity) {
      Liquidity.liquid =>
        account.kind == AccountKind.bank ? 'liquid in 1 day' : 'instant',
      Liquidity.reserved => 'reserved',
      Liquidity.locked => 'locked',
    };
    return '${account.kind.label} · $reach';
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final hasFloor = account.minBalance > 0;
    final heldBack = account.balance <= 0
        ? 0.0
        : (account.minBalance / account.balance).clamp(0.0, 1.0);

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
                    Text(account.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppType.rowTitle
                            .copyWith(fontSize: 15, color: t.ink)),
                    const SizedBox(height: 6),
                    Eyebrow(_kindLine, color: t.inkMuted),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Text(formatMoney(account.balance),
                  softWrap: false,
                  style: AppType.figureRow.copyWith(
                    fontSize: 17,
                    color: account.isBelowFloor ? t.expense.ink : t.ink,
                  )),
            ],
          ),
          if (hasFloor) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: heldBack,
                minHeight: 5,
                backgroundColor: t.track,
                valueColor: AlwaysStoppedAnimation(
                    account.isBelowFloor ? t.expense.ink : t.committed),
              ),
            ),
            const SizedBox(height: 7),
            Text(
              account.isBelowFloor
                  ? 'Below its floor of ${formatMoney(account.minBalance)}'
                  : 'Floor ${formatMoney(account.minBalance)} · '
                      '${(heldBack * 100).round()}% held back',
              style: AppType.rowSub.copyWith(
                height: 1.0,
                color: account.isBelowFloor ? t.expense.ink : t.inkMuted,
              ),
            ),
          ] else ...[
            const SizedBox(height: 11),
            Text(
              account.liquidity == Liquidity.liquid
                  ? 'No floor set · all of it counts as spendable'
                  : 'Held out of safe-to-spend',
              style: AppType.rowSub.copyWith(height: 1.0, color: t.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArchivedCard extends StatelessWidget {
  final Account account;
  final VoidCallback onTap;

  const _ArchivedCard({required this.account, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final radius = BorderRadius.circular(Radii.medium);

    return Material(
      color: t.recessed,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: t.outline, style: BorderStyle.solid),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(account.name,
                        style:
                            AppType.rowTitle.copyWith(color: t.inkMuted)),
                    const SizedBox(height: 6),
                    Eyebrow('Archived', size: 9, color: t.inkFaint),
                  ],
                ),
              ),
              Text(formatMoney(account.balance),
                  style: AppType.figureRow
                      .copyWith(fontSize: 15, color: t.inkFaint)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommitmentsLink extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final bills = (ref.watch(obligationsProvider).value ?? [])
        .where((o) => o.isActive)
        .length;
    final goals =
        (ref.watch(goalsProvider).value ?? []).where((g) => g.isActive).length;

    return Material(
      color: Colors.transparent,
      borderRadius: Radii.sm,
      child: InkWell(
        borderRadius: Radii.sm,
        onTap: () => context.push('/plan'),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: Radii.sm,
            border: Border.all(color: t.outline),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Commitments & goals',
                        style: AppType.label
                            .copyWith(fontSize: 15, color: t.ink)),
                    const SizedBox(height: 6),
                    Text(
                      bills == 0 && goals == 0
                          ? 'Bills, expected income and money you protect'
                          : '$bills bill${bills == 1 ? '' : 's'} · '
                              '$goals goal${goals == 1 ? '' : 's'}',
                      style: AppType.rowSub
                          .copyWith(height: 1.0, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward, size: 17, color: t.brandInk),
            ],
          ),
        ),
      ),
    );
  }
}

/// Nothing set up yet.
///
/// It does not just say "empty" — it names the three kinds of place a Ghanaian
/// user's money actually sits, so the first tap is obvious.
class _FirstRun extends StatelessWidget {
  final ValueChanged<AccountKind> onAdd;
  const _FirstRun({required this.onAdd});

  static const _kinds = [
    (AccountKind.bank, 'Bank account', 'Fidelity, GCB, Absa', 0),
    (AccountKind.momo, 'Mobile Money', 'MTN, Vodafone Cash, AirtelTigo', 1),
    (AccountKind.cash, 'Cash', 'What is in your pocket', 4),
  ];

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
            children: [
              Text('Accounts', style: AppType.title.copyWith(color: t.ink)),
              const SizedBox(height: 18),
              DottedBorderBox(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 26),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Add where your money actually is',
                        style: AppType.rowTitle
                            .copyWith(fontSize: 17, color: t.ink)),
                    const SizedBox(height: 8),
                    Text(
                      'Nothing can be called safe to spend until the app knows '
                      'your balances. Most people start with one bank and one '
                      'Momo wallet.',
                      style: AppType.body
                          .copyWith(height: 1.55, color: t.inkMuted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              for (final (kind, title, examples, hue) in _kinds)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CediCard(
                    onTap: () => onAdd(kind),
                    child: Row(
                      children: [
                        CategoryGlyph(name: title, hue: hue, size: 34),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(title,
                                  style: AppType.rowTitle
                                      .copyWith(color: t.ink)),
                              const SizedBox(height: 4),
                              Text(examples,
                                  style: AppType.rowSub
                                      .copyWith(color: t.inkMuted)),
                            ],
                          ),
                        ),
                        Icon(Icons.add, size: 18, color: t.brandInk),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 22),
          child: PrimaryButton(
            label: 'Add first account',
            onPressed: () => onAdd(AccountKind.bank),
          ),
        ),
      ],
    );
  }
}
