import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

List<double>? normalizeSpark(List<double> series) {
  if (series.length < 2) return null;
  final max = series.reduce((a, b) => a > b ? a : b);
  if (max <= 0) return List<double>.filled(series.length, 0);
  return series.map((value) => value / max).toList();
}

class Sparkline extends StatelessWidget {
  final List<double> series;
  final double height;
  final Color? color;

  const Sparkline({
    super.key,
    required this.series,
    this.height = 64,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final normalized = normalizeSpark(series);
    if (normalized == null) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough data yet',
            style: AppTextStyles.monoData.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: SparklinePainter(normalized, color ?? AppColors.primary),
        size: Size.infinite,
      ),
    );
  }
}

class SparklinePainter extends CustomPainter {
  final List<double> normalized;
  final Color color;

  SparklinePainter(this.normalized, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    const padV = 4.0;
    final points = [
      for (var i = 0; i < normalized.length; i++)
        Offset(
          size.width * i / (normalized.length - 1),
          size.height - padV - normalized[i] * (size.height - padV * 2),
        ),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();

    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(SparklinePainter oldDelegate) =>
      oldDelegate.normalized != normalized || oldDelegate.color != color;
}
