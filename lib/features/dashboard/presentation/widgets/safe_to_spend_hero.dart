import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/finance/money_engine.dart';
import '../../../../core/formatters.dart';
import '../../../../core/theme.dart';

/// The number the old dashboard should have been showing all along.
///
/// Total balance is a fact about the past. Safe-to-spend is a decision you can
/// act on: what is left after the floors you set, the goals you protect and the
/// bills that have not left yet.
class SafeToSpendHero extends StatelessWidget {
  final MoneySnapshot snapshot;

  const SafeToSpendHero({super.key, required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final s = snapshot;
    final radius = BorderRadius.circular(22);
    final (start, end) = _gradient;

    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: () => context.push('/plan'),
        child: Ink(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [start, end],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: end.withValues(alpha: 0.3),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_moon_outlined,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _label,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                formatMoney(s.safeToSpend),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _verdict,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 10),
              Divider(color: Colors.white.withValues(alpha: 0.22), height: 18),
              Row(
                children: [
                  Expanded(
                    child: _Stat(
                      label: 'Total balance',
                      value: formatMoney(s.totalBalance),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Committed',
                      value: formatMoney(s.committed),
                    ),
                  ),
                  Expanded(
                    child: _Stat(
                      label: 'Per day',
                      value: formatMoney(s.dailyBurn),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String get _label {
    final s = snapshot;
    if (s.daysUntilIncome == null) {
      return 'Safe to spend over the next 30 days';
    }
    return 'Safe to spend before your next income';
  }

  /// One sentence saying whether things are fine, tight, or about to break.
  String get _verdict {
    final s = snapshot;

    if (s.safeToSpend < 0) {
      return 'Your bills come to ${formatMoney(-s.safeToSpend)} more than you '
          'have spare. Something needs to move.';
    }
    if (s.willFallShort) {
      return 'At ${formatMoney(s.dailyBurn)} a day this runs out '
          '${s.shortfallDays} days before money arrives.';
    }
    if (s.daysUntilIncome != null) {
      final days = s.daysUntilIncome!;
      return 'Income lands in $days day${days == 1 ? '' : 's'}. '
          '${_paceLine(s, days)}';
    }
    if (s.runwayDays != null) {
      return 'At ${formatMoney(s.dailyBurn)} a day this lasts about '
          '${s.runwayDays!.floor()} days.';
    }
    return 'Log a few expenses and this will start telling you how long your '
        'money lasts.';
  }

  String _paceLine(MoneySnapshot s, int days) {
    if (days <= 0 || s.safeToSpend <= 0) return '';
    final perDay = s.safeToSpend / days;
    return 'That is ${formatMoney(perDay)} a day until then.';
  }

  /// Green when comfortable, amber when tight, red when it will not work.
  (Color, Color) get _gradient {
    final s = snapshot;
    if (s.safeToSpend < 0 || s.willFallShort) {
      return (AppColors.expenseGradStart, AppColors.expenseGradEnd);
    }
    final days = s.daysUntilIncome;
    if (days != null && days > 0 && s.dailyBurn > 0) {
      final needed = s.dailyBurn * days;
      if (s.safeToSpend < needed * 1.15) {
        return (const Color(0xFFB45309), AppColors.warning);
      }
    }
    return (AppColors.gradStart, AppColors.gradEnd);
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 10.5)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
}
