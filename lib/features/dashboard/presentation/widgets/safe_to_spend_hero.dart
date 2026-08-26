import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/components.dart';
import '../../../../core/finance/money_engine.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme.dart';

/// The verdict, not the total.
///
/// Total balance is a fact about the past. Safe-to-spend is a decision you can
/// act on: what is left after the floors you set, the goals you protect and the
/// bills that have not left yet.
///
/// It used to be white text on a bright gradient that switched between green,
/// amber and red. The figure is now drawn in a legible tint of the semantic
/// colour on a low-alpha surface of the same hue, so the state still reads at a
/// glance without the screen shouting at night.
class SafeToSpendHero extends StatelessWidget {
  final MoneySnapshot snapshot;

  const SafeToSpendHero({super.key, required this.snapshot});

  /// Three states, and only three. Anything finer is a distinction the user
  /// cannot act on differently.
  _HeroState get _state {
    final s = snapshot;
    if (s.safeToSpend < 0) return _HeroState.shortfall;
    if (s.willFallShort) return _HeroState.tight;
    final days = s.daysUntilIncome;
    if (days != null && days > 0 && s.dailyBurn > 0) {
      if (s.safeToSpend < s.dailyBurn * days * 1.15) return _HeroState.tight;
    }
    return _HeroState.safe;
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final s = snapshot;
    final state = _state;

    final (tint, eyebrow, dotFilled) = switch (state) {
      _HeroState.safe => (t.safe, 'Safe to spend', true),
      _HeroState.tight => (t.warning, 'Tight before payday', false),
      _HeroState.shortfall => (t.expense, 'Short before payday', true),
    };

    final negative = s.safeToSpend < 0;
    final dotColor = state == _HeroState.safe ? t.brandInk : tint.ink;

    return TintCard(
      tint: tint,
      radius: Radii.large,
      padding: const EdgeInsets.all(18),
      onTap: () => context.push('/plan'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: dotFilled ? dotColor : null,
                  border: dotFilled ? null : Border.all(color: dotColor, width: 2),
                ),
              ),
              const SizedBox(width: 8),
              Eyebrow(eyebrow,
                  color: state == _HeroState.safe
                      ? (Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF6FDCBF)
                          : tint.ink)
                      : tint.muted),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                negative ? '-$kCurrencyCode' : kCurrencyCode,
                style: AppType.heroCode.copyWith(color: tint.muted),
              ),
              const SizedBox(width: 7),
              // The figure shrinks rather than truncates. A safe-to-spend
              // number that ends in an ellipsis is worse than useless.
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    moneyDigits(s.safeToSpend.abs()),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.heroFigure.copyWith(color: tint.ink),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(_caption, style: AppType.bodySmall.copyWith(color: tint.body)),
          const SizedBox(height: 16),
          Container(height: 1, color: _ruleColor(context, state)),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: StatColumn(
                  label: 'Total balance',
                  amount: s.totalBalance,
                  labelColor: _statLabel(state, t, tint),
                  codeColor: _statCode(state, t, tint),
                  inkColor: _statInk(state, t, tint),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatColumn(
                  label: 'Committed',
                  amount: s.committed,
                  labelColor: _statLabel(state, t, tint),
                  codeColor: _statCode(state, t, tint),
                  inkColor: _statInk(state, t, tint),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: StatColumn(
                  label: 'Per day',
                  amount: _perDay,
                  labelColor: _statLabel(state, t, tint),
                  codeColor: _statCode(state, t, tint),
                  inkColor: _statInk(state, t, tint),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// What is actually spendable per day between now and payday — zero when
  /// there is nothing to spend, rather than the historical burn rate, which
  /// would read as permission.
  double get _perDay {
    final s = snapshot;
    if (s.safeToSpend <= 0) return 0;
    final days = s.daysUntilIncome;
    if (days == null || days <= 0) return s.safeToSpend / 30;
    return s.safeToSpend / days;
  }

  String get _caption {
    final s = snapshot;

    if (s.safeToSpend < 0) {
      return 'Your bills to ${dayMonthFmt.format(s.horizon)} exceed what you '
          'hold. Something has to move or wait.';
    }
    if (s.willFallShort) {
      return 'At ${formatMoney(s.dailyBurn)} a day this runs out '
          '${s.shortfallDays} days before money arrives.';
    }
    final days = s.daysUntilIncome;
    if (days != null) {
      return 'before your next income on ${dayMonthFmt.format(s.horizon)} · '
          '$days day${days == 1 ? '' : 's'}';
    }
    if (s.runwayDays != null) {
      return 'over the next 30 days · about ${s.runwayDays!.floor()} days of '
          'runway at your current pace';
    }
    return 'over the next 30 days. Log a few expenses and this starts telling '
        'you how long your money lasts.';
  }

  /// The rule under the figure follows the hue of the card it sits on.
  Color _ruleColor(BuildContext context, _HeroState state) =>
      Theme.of(context).brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.09)
          : switch (state) {
              _HeroState.safe => const Color(0xFFC6E1D8),
              _HeroState.tight => const Color(0xFFEFDCB0),
              _HeroState.shortfall => const Color(0xFFEDC9C9),
            };

  /// A safe hero carries neutral stats — the colour has already said its piece
  /// in the eyebrow and the figure. A warning or shortfall hero keeps them
  /// on-hue so the block reads as one thing.
  Color _statLabel(_HeroState state, CediTokens t, SemanticTint tint) =>
      state == _HeroState.safe ? t.inkMuted : tint.muted;

  Color _statCode(_HeroState state, CediTokens t, SemanticTint tint) =>
      state == _HeroState.safe ? t.inkFaint : tint.muted;

  Color _statInk(_HeroState state, CediTokens t, SemanticTint tint) =>
      state == _HeroState.safe ? t.ink : tint.body;
}

enum _HeroState { safe, tight, shortfall }
