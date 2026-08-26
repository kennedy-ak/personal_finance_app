import 'package:flutter/material.dart';

import '../../../../core/design/components.dart';
import '../../../../core/finance/money_engine.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme.dart';

class _Segment {
  final String label;
  final double amount;
  final Color color;

  const _Segment(this.label, this.amount, this.color);
}

/// Answers "is my money tied up, and where?" — the question a single total
/// balance can never answer.
///
/// Three bands rather than five. Liquid, committed and protected are the only
/// distinctions that change what you can do this week; splitting protected
/// into floors, goals, reserved and locked made a legend nobody read.
class MoneyPlacementBar extends StatelessWidget {
  final MoneySnapshot snapshot;

  const MoneyPlacementBar({super.key, required this.snapshot});

  List<_Segment> _segments(CediTokens t) {
    final s = snapshot;
    final protected = s.floors + s.goalReserve + s.reserved + s.locked;
    // When bills outstrip the cash, every usable cedi is already claimed and
    // nothing is shown as liquid.
    final usable = s.usableCash > 0 ? s.usableCash : 0.0;
    final committed = s.committed < usable ? s.committed : usable;
    final liquid = usable - committed;

    // A band worth nothing is left out entirely. "Liquid GHS 0.00" is not a
    // reassuring line to read, and its absence says the same thing louder.
    return [
      _Segment('Liquid', liquid, t.liquid),
      _Segment('Committed', committed, t.committed),
      _Segment('Protected', protected, t.protected),
    ].where((seg) => seg.amount > 0.005).toList();
  }

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final segments = _segments(t);
    final total = segments.fold<double>(0, (sum, seg) => sum + seg.amount);

    return CediCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where your money sits',
              style: AppType.cardTitle.copyWith(color: t.ink)),
          const SizedBox(height: 13),
          if (total <= 0)
            Text(
              'No balances yet. Add what you actually hold in each account and '
              'this will show what is genuinely spendable.',
              style: AppType.bodySmall.copyWith(color: t.inkMuted),
            )
          else ...[
            StackedBar(
              slices: [
                for (final seg in segments) BarSlice(seg.amount, seg.color),
              ],
            ),
            const SizedBox(height: 13),
            for (var i = 0; i < segments.length; i++) ...[
              if (i > 0) const SizedBox(height: 9),
              LegendLine(
                color: segments[i].color,
                label: segments[i].label,
                trailing: formatMoney(segments[i].amount),
              ),
            ],
            if (snapshot.safeToSpend < 0) ...[
              const SizedBox(height: 12),
              TintCard(
                tint: t.expense,
                radius: Radii.small,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  'Bills exceed your spendable money by '
                  '${formatMoney(-snapshot.safeToSpend)}.',
                  style: AppType.bodySmall.copyWith(color: t.expense.body),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
