import 'package:flutter/material.dart';

class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final List<Color> gradient;
  final String? sub;
  final VoidCallback? onTap;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.gradient,
    this.sub,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: gradient.last.withValues(alpha: 0.25),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 18),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ],
      ),
        ),
      ),
    );
  }
}
