import 'package:flutter/material.dart';

import '../theme.dart';

/// Equity-curve line chart with gradient fill.
class EquityCurve extends StatelessWidget {
  const EquityCurve({super.key, required this.values, this.height = 180});

  /// (labelTime, value) points.
  final List<(DateTime, double)> values;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _CurvePainter(
          values: values,
          lineColor: TrTheme.accent,
          gridColor: TrTheme.outline,
          muted: TrTheme.textMuted,
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.muted,
  });

  final List<(DateTime, double)> values;
  final Color lineColor;
  final Color gridColor;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2 || size.width < 40) return;
    final padRight = 54.0;
    final padTop = 8.0;
    final padBottom = 8.0;
    final w = size.width - padRight;
    final h = size.height - padTop - padBottom;

    var minV = double.infinity;
    var maxV = -double.infinity;
    for (final (_, v) in values) {
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (maxV - minV < 1e-9) {
      maxV = minV + 1;
    }
    final range = maxV - minV;

    double x(int i) => i / (values.length - 1) * w;
    double y(double v) => padTop + (maxV - v) / range * h;

    final tp = TextPainter(textDirection: TextDirection.ltr);
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var g = 0; g <= 3; g++) {
      final v = minV + range * g / 3;
      final yy = y(v);
      canvas.drawLine(Offset(0, yy), Offset(w, yy), gridPaint);
      tp.text = TextSpan(
        text: '\$${v.toStringAsFixed(0)}',
        style: TextStyle(color: muted, fontSize: 10),
      );
      tp.layout();
      tp.paint(canvas, Offset(w + 6, yy - 6));
    }

    final path = Path()..moveTo(0, y(values.first.$2));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i].$2));
    }
    final fill = Path.from(path)
      ..lineTo(w, padTop + h)
      ..lineTo(0, padTop + h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [lineColor.withOpacity(0.28), lineColor.withOpacity(0.02)],
        ).createShader(Rect.fromLTWH(0, 0, w, size.height)),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..strokeJoin = StrokeJoin.round,
    );

    // End value callout.
    final lastV = values.last.$2;
    final lastX = x(values.length - 1);
    final lastY = y(lastV);
    canvas.drawCircle(Offset(lastX, lastY), 3.2, Paint()..color = lineColor);
    tp.text = TextSpan(
      text: '\$${lastV.toStringAsFixed(0)}',
      style: TextStyle(
        color: lineColor,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    );
    tp.layout();
    tp.paint(canvas, Offset(w + 6, lastY - 7));
  }

  @override
  bool shouldRepaint(_CurvePainter old) => old.values != values;
}
