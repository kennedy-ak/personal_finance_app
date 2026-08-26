import 'package:flutter/material.dart';

import '../../../../core/design/components.dart';
import '../../../../core/finance/money_engine.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme.dart';

/// This month against last, naming the categories that moved.
///
/// The share of a pie tells you where money went, which you already knew. The
/// delta beside a category tells you whether that is news — which is the part
/// worth acting on. So the chart is gone and the movement is the content.
class SpendingMovement extends StatelessWidget {
  final MoneySnapshot snapshot;

  const SpendingMovement({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final categories = snapshot.categories;

    if (categories.isEmpty) {
      return CediCard(
        child: Text(
          'No spending logged in the last 30 days.',
          style: AppType.bodySmall.copyWith(color: t.inkMuted),
        ),
      );
    }

    // The three that moved most, by size of change rather than size of spend —
    // a category that doubled matters more than the one that always costs
    // the most.
    final moved = [
      for (final c in categories)
        if (c.changeRatio != null && c.changeRatio!.abs() >= 0.1) c,
    ]..sort((a, b) => b.changeRatio!.abs().compareTo(a.changeRatio!.abs()));

    final shown = (moved.isEmpty ? categories.take(3) : moved.take(3)).toList();
    final change = snapshot.spendChangeRatio;

    return CediCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionRow(
            title: 'Spending this month',
            note: change == null
                ? 'LAST 30 DAYS'
                : 'VS ${monthFmt.format(snapshot.asOf.subtract(const Duration(days: 45))).toUpperCase()}',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(kCurrencyCode,
                  style: AppType.heroCode
                      .copyWith(fontSize: 13, color: t.inkMuted)),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    moneyDigits(snapshot.spend30d),
                    maxLines: 1,
                    softWrap: false,
                    style: AppType.heroFigure
                        .copyWith(fontSize: 28, letterSpacing: -0.84, color: t.ink),
                  ),
                ),
              ),
              if (change != null) ...[
                const SizedBox(width: 10),
                Text(
                  _percent(change),
                  style: AppType.label.copyWith(
                    fontSize: 13,
                    color: change > 0 ? t.expense.ink : t.income.ink,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _MovementRow(
              category: shown[i],
              hue: categories.indexOf(shown[i]),
            ),
          ],
        ],
      ),
    );
  }

  /// A minus sign, not a hyphen — it lines up with the digits.
  static String _percent(double ratio) {
    final pct = (ratio.abs() * 100).round();
    return '${ratio > 0 ? '+' : '−'}$pct%';
  }
}

class _MovementRow extends StatelessWidget {
  final CategorySpend category;
  final int hue;

  const _MovementRow({required this.category, required this.hue});

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final ratio = category.changeRatio;

    return Row(
      children: [
        CategoryGlyph(name: category.category, hue: hue, size: 28),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            category.category,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.bodySmall.copyWith(height: 1.0, color: t.inkBody),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          ratio == null
              ? formatMoney(category.amount)
              : SpendingMovement._percent(ratio),
          softWrap: false,
          style: AppType.figureRow.copyWith(
            fontSize: 13,
            color: ratio == null
                ? t.ink
                : ratio > 0
                    ? t.expense.ink
                    : t.income.ink,
          ),
        ),
      ],
    );
  }
}
