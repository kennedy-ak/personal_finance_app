import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme.dart';
import '../data/daily_tip_service.dart';

class DailyTipCard extends ConsumerWidget {
  const DailyTipCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tipAsync = ref.watch(dailyTipProvider);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [AppColors.netGradStart, AppColors.netGradEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.netGradEnd.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 10),
              const Text(
                'Tip of the day',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          tipAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white70),
                  ),
                  SizedBox(width: 10),
                  Text('Generating fresh tips…',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ),
            ),
            error: (e, _) => Text(
              'Tip unavailable. ${_short(e.toString())}',
              style: const TextStyle(color: Colors.white70, fontSize: 12.5, height: 1.4),
            ),
            data: (tip) {
              if (tip == null) {
                return const Text(
                  'Set an OpenAI key in Settings to unlock daily AI-generated tips.',
                  style: TextStyle(color: Colors.white, fontSize: 13.5, height: 1.45),
                );
              }
              return Text(
                tip,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  String _short(String e) {
    if (e.length > 80) return '${e.substring(0, 80)}…';
    return e;
  }
}
