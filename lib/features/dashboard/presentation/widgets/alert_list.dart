import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/design/components.dart';
import '../../../../core/finance/alerts.dart';
import '../../../../core/theme.dart';

/// What the app has noticed, loudest first.
///
/// Every line here was worked out in Dart from real figures, so it can be
/// stated as fact rather than hedged.
///
/// The severity scale is deliberately not three shades of red. Critical is a
/// red tint with a solid dot, tight is amber with a ring, and information is
/// the plain card with a hairline dot — so a screen with four alerts still has
/// somewhere for the eye to go first.
class AlertList extends StatefulWidget {
  final List<MoneyAlert> alerts;

  /// How many to show before hiding the rest behind "show more".
  final int collapsedCount;

  /// The heading above the stack. The shortfall dashboard calls it
  /// "What closes the gap"; everywhere else it is "Needs a decision".
  final String heading;

  const AlertList({
    super.key,
    required this.alerts,
    this.collapsedCount = 3,
    this.heading = 'Needs a decision',
  });

  @override
  State<AlertList> createState() => _AlertListState();
}

class _AlertListState extends State<AlertList> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final t = CediTokens.of(context);
    final all = widget.alerts;
    if (all.isEmpty) return const SizedBox.shrink();

    final showing = _expanded ? all : all.take(widget.collapsedCount).toList();
    final hidden = all.length - showing.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionRow(title: widget.heading, note: '${all.length}'),
        const SizedBox(height: 8),
        for (var i = 0; i < showing.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _Alert(alert: showing[i]),
        ],
        if (hidden > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = true),
              icon: const Icon(Icons.expand_more, size: 18),
              label: Text('$hidden more',
                  style: AppType.label.copyWith(fontSize: 13, color: t.brandInk)),
            ),
          )
        else if (_expanded && all.length > widget.collapsedCount)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => setState(() => _expanded = false),
              icon: const Icon(Icons.expand_less, size: 18),
              label: Text('Show less',
                  style: AppType.label.copyWith(fontSize: 13, color: t.brandInk)),
            ),
          ),
      ],
    );
  }
}

class _Alert extends StatelessWidget {
  final MoneyAlert alert;
  const _Alert({required this.alert});

  /// The mono line classifies; it never carries information the sentence
  /// below needs. Three words, upper case, always the same three per severity
  /// so the scale is learnable.
  static String _eyebrowFor(AlertSeverity severity) => switch (severity) {
        AlertSeverity.critical => 'Not covered',
        AlertSeverity.warning => 'Tight',
        AlertSeverity.info => 'For info',
      };

  @override
  Widget build(BuildContext context) {
    final route = alert.actionRoute;
    return AlertCard(
      tone: switch (alert.severity) {
        AlertSeverity.critical => AlertTone.critical,
        AlertSeverity.warning => AlertTone.tight,
        AlertSeverity.info => AlertTone.info,
      },
      eyebrow: _eyebrowFor(alert.severity),
      message: alert.title,
      detail: alert.detail,
      actionLabel: alert.actionLabel,
      onTap: route == null ? null : () => context.push(route),
    );
  }
}
