import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../../core/finance/money_engine.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme.dart';

/// Spending by category, with what changed against the 30 days before.
///
/// The share of a pie tells you where money went. The delta beside it tells you
/// whether that is news — which is the part worth acting on.
class SpendingMovement extends StatelessWidget {
  final MoneySnapshot snapshot;

  const SpendingMovement({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final categories = snapshot.categories;

    if (categories.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Row(
            children: [
              Icon(Icons.pie_chart_outline, color: cs.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  'No spending logged in the last 30 days.',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final total = categories.fold<double>(0, (s, c) => s + c.amount);
    final shown = categories.take(5).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('Spending — last 30 days',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
                ),
                Text(formatMoney(total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14.5)),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                SizedBox(
                  width: 108,
                  height: 108,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 32,
                      sections: [
                        for (var i = 0; i < categories.length; i++)
                          PieChartSectionData(
                            value: categories[i].amount,
                            showTitle: false,
                            color: AppColors.chart[i % AppColors.chart.length],
                            radius: 20,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < shown.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 9),
                          child: _CategoryRow(
                            category: shown[i],
                            color: AppColors.chart[i % AppColors.chart.length],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  final CategorySpend category;
  final Color color;

  const _CategoryRow({required this.category, required this.color});

  @override
  Widget build(BuildContext context) {
    final ratio = category.changeRatio;

    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            category.category,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        if (ratio != null && ratio.abs() >= 0.1) ...[
          _DeltaChip(ratio: ratio),
          const SizedBox(width: 6),
        ],
        Text(
          formatMoney(category.amount),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// Up is not automatically bad, but it is always worth seeing.
class _DeltaChip extends StatelessWidget {
  final double ratio;
  const _DeltaChip({required this.ratio});

  @override
  Widget build(BuildContext context) {
    final up = ratio > 0;
    final color = up ? AppColors.expense : AppColors.income;
    final pct = (ratio.abs() * 100).round();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
              size: 9, color: color),
          const SizedBox(width: 2),
          Text(
            '$pct%',
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
