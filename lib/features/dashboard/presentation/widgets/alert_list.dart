import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/finance/alerts.dart';
import '../../../../core/theme.dart';

/// What the app has noticed, loudest first.
///
/// Every line here was worked out in Dart from real figures, so it can be
/// stated as fact rather than hedged.
class AlertList extends StatefulWidget {
  final List<MoneyAlert> alerts;

  /// How many to show before hiding the rest behind "show more".
  final int collapsedCount;

  const AlertList({super.key, required this.alerts, this.collapsedCount = 2});

  @override
  State<AlertList> createState() => _AlertListState();
}

class _AlertListState extends State<AlertList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final all = widget.alerts;
    if (all.isEmpty) return const SizedBox.shrink();

    final showing =
        _expanded ? all : all.take(widget.collapsedCount).toList();
    final hidden = all.length - showing.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final alert in showing)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AlertCard(alert: alert),
          ),
        if (hidden > 0)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = true),
            icon: const Icon(Icons.expand_more, size: 18),
            label: Text('$hidden more'),
          )
        else if (_expanded && all.length > widget.collapsedCount)
          TextButton.icon(
            onPressed: () => setState(() => _expanded = false),
            icon: const Icon(Icons.expand_less, size: 18),
            label: const Text('Show less'),
          ),
      ],
    );
  }
}

class _AlertCard extends StatelessWidget {
  final MoneyAlert alert;
  const _AlertCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (color, icon) = switch (alert.severity) {
      AlertSeverity.critical => (AppColors.expense, Icons.priority_high),
      AlertSeverity.warning => (AppColors.warning, Icons.warning_amber_rounded),
      AlertSeverity.info => (AppColors.seed, Icons.lightbulb_outline),
    };

    final route = alert.actionRoute;

    return Card(
      color: color.withValues(alpha: 0.07),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: color.withValues(alpha: 0.28)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: route == null ? null : () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      alert.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                alert.detail,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: cs.onSurfaceVariant,
                ),
              ),
              if (alert.actionLabel != null && route != null) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => context.push(route),
                    style: TextButton.styleFrom(foregroundColor: color),
                    child: Text(alert.actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
