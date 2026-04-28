import 'package:flutter/material.dart';

import '../../core/theme.dart';

class AppLogo extends StatelessWidget {
  final double size;
  final bool onDark;
  const AppLogo({super.key, this.size = 72, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LogoPainter(onDark: onDark)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  final bool onDark;
  _LogoPainter({required this.onDark});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final r = w * 0.26;

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(r),
    );

    final bg = Paint()
      ..shader = const LinearGradient(
        colors: [AppColors.gradStart, AppColors.gradEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawRRect(bgRect, bg);

    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white.withValues(alpha: 0.18),
          Colors.white.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(
        center: Offset(w * 0.78, h * 0.22),
        radius: w * 0.55,
      ));
    canvas.drawRRect(bgRect, glow);

    final barColor = Paint()..color = Colors.white;
    final padX = w * 0.22;
    final baseline = h * 0.74;
    final barW = w * 0.11;
    final gap = w * 0.07;
    final heights = [h * 0.18, h * 0.30, h * 0.46];
    for (var i = 0; i < heights.length; i++) {
      final left = padX + i * (barW + gap);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, baseline - heights[i], barW, heights[i]),
        Radius.circular(barW * 0.45),
      );
      canvas.drawRRect(rect, barColor);
    }

    final arrow = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final p1 = Offset(padX + barW / 2, baseline - heights[0] - h * 0.04);
    final p2 = Offset(padX + (barW + gap) + barW / 2,
        baseline - heights[1] - h * 0.04);
    final p3 = Offset(padX + 2 * (barW + gap) + barW / 2,
        baseline - heights[2] - h * 0.04);
    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy);
    canvas.drawPath(path, arrow);

    final tipSize = w * 0.07;
    final tipPath = Path()
      ..moveTo(p3.dx, p3.dy - tipSize)
      ..lineTo(p3.dx + tipSize, p3.dy)
      ..lineTo(p3.dx - tipSize * 0.2, p3.dy + tipSize * 0.2)
      ..close();
    canvas.drawPath(
        tipPath,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill);

    final dot = Paint()..color = Colors.white;
    canvas.drawCircle(p1, w * 0.038, dot);
    canvas.drawCircle(p2, w * 0.038, dot);
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) =>
      oldDelegate.onDark != onDark;
}
