import 'package:flutter/material.dart';

import '../../../../core/finance/money_engine.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme.dart';

class _Segment {
  final String label;
  final String meaning;
  final double amount;
  final Color color;

  const _Segment(this.label, this.meaning, this.amount, this.color);
}

/// Answers "is my money tied up, and where?" — the question a single total
/// balance can never answer.
///
/// The segments always add up to the total balance, including when bills
/// already exceed what is spendable; in that case nothing is shown as safe and
/// the shortfall is called out underneath.
class MoneyPlacementBar extends StatelessWidget {
  final MoneySnapshot snapshot;

  const MoneyPlacementBar({super.key, required this.snapshot});

  List<_Segment> get _segments {
    final s = snapshot;
    final usable = s.usableCash > 0 ? s.usableCash : 0.0;
    final safe = s.safeToSpend > 0 ? s.safeToSpend : 0.0;
    // When bills outstrip the cash, every usable cedi is already claimed.
    final committed = s.committed < usable ? s.committed : usable;

    return [
      _Segment('Spendable', 'yours to use', safe, AppColors.seed),
      _Segment('Bills', 'leaving soon', committed, AppColors.warning),
      _Segment('Protected', 'floors and goals', s.floors + s.goalReserve,
          const Color(0xFF3B82F6)),
      _Segment('Reserved', 'set aside', s.reserved, AppColors.accent),
      _Segment('Locked', 'long-term', s.locked, const Color(0xFF64748B)),
    ].where((seg) => seg.amount > 0.005).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final segments = _segments;
    final total = segments.fold<double>(0, (sum, seg) => sum + seg.amount);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where your money is',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
            const SizedBox(height: 14),
            if (total <= 0)
              Text(
                'No balances yet. Add what you actually hold in each account and '
                'this will show what is genuinely spendable.',
                style: TextStyle(fontSize: 12.5, height: 1.45, color: cs.onSurfaceVariant),
              )
            else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  height: 12,
                  child: Row(
                    children: [
                      for (final seg in segments)
                        Expanded(
                          flex: (seg.amount / total * 10000).round().clamp(1, 100000),
                          child: Container(color: seg.color),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              for (final seg in segments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: seg.color,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(seg.label,
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          seg.meaning,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
                        ),
                      ),
                      Text(formatMoney(seg.amount),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              if (snapshot.safeToSpend < 0)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.expense.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: AppColors.expense, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Bills exceed your spendable money by '
                          '${formatMoney(-snapshot.safeToSpend)}.',
                          style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.expense,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
