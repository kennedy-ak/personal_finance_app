import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design/components.dart';
import '../../../core/theme.dart';
import '../data/daily_tip_service.dart';

/// One observation about today, in the coach's colour.
///
/// It used to be white text on a violet gradient with a drop shadow. Same
/// meaning, same hue, but the tip is now legible at night: a low-alpha violet
/// surface with a matching border and violet ink.
class DailyTipCard extends ConsumerWidget {
  /// Sends the user to the chat with the tip as the opening question.
  final VoidCallback? onAskAboutThis;

  const DailyTipCard({super.key, this.onAskAboutThis});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = CediTokens.of(context);
    final tipAsync = ref.watch(dailyTipProvider);

    return TintCard(
      tint: t.accent,
      radius: 18,
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 5,
                decoration: BoxDecoration(
                  color: t.accent.ink,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Eyebrow('Today', color: t.accent.ink),
            ],
          ),
          const SizedBox(height: 9),
          tipAsync.when(
            loading: () => Row(
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.accent.ink,
                    backgroundColor: t.accent.ink.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(width: 10),
                Text('Reading your position…',
                    style: AppType.bodySmall.copyWith(color: t.accent.muted)),
              ],
            ),
            error: (e, _) => Text(
              'No tip today — the coach could not be reached. Nothing was '
              'charged and your numbers are unchanged.',
              style: AppType.body
                  .copyWith(fontSize: 15, height: 1.5, color: t.accent.body),
            ),
            data: (tip) => Text(
              tip ??
                  'Set an API key in Settings and the coach will read your '
                      'numbers each morning.',
              style: AppType.body
                  .copyWith(fontSize: 15, height: 1.5, color: t.accent.body),
            ),
          ),
          if (onAskAboutThis != null && tipAsync.value != null) ...[
            const SizedBox(height: 12),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAskAboutThis,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Ask about this',
                      style: AppType.label
                          .copyWith(fontSize: 13, color: t.accent.ink)),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 14, color: t.accent.ink),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
