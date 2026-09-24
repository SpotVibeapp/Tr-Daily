import 'dart:math';

import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../theme.dart';

/// Everything the candlestick painter draws.
class ChartFrame {
  const ChartFrame({
    required this.candles,
    this.emaFast,
    this.emaSlow,
    this.vwap,
    this.support,
    this.resistance,
    this.markers = const <(int, String, Color)>[],
  });

  final List<Candle> candles;
  final List<double?>? emaFast;
  final List<double?>? emaSlow;
  final List<double?>? vwap;
  final double? support;
  final double? resistance;

  /// (barIndex, label, color) callouts drawn above/below bars.
  final List<(int, String, Color)> markers;
}

/// Hand-rolled candlestick chart (no external chart dependency).
class CandleChart extends StatelessWidget {
  const CandleChart({super.key, required this.frame, this.height = 320});

  final ChartFrame frame;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: CandlePainter(
          frame: frame,
          gridColor: TrTheme.outline,
          muted: TrTheme.textMuted,
        ),
      ),
    );
  }
}

class CandlePainter extends CustomPainter {
  CandlePainter({
    required this.frame,
    required this.gridColor,
    required this.muted,
  });

  final ChartFrame frame;
  final Color gridColor;
  final Color muted;

  @override
  void paint(Canvas canvas, Size size) {
    final candles = frame.candles;
    if (candles.length < 2 || size.width < 40 || size.height < 40) return;

    final padRight = 56.0;
    final padTop = 12.0;
    final padBottom = 22.0;
    final plotW = size.width - padRight;
    final plotH = size.height - padTop - padBottom;

    var minP = double.infinity;
    var maxP = -double.infinity;
    for (final c in candles) {
      if (c.low < minP) minP = c.low;
      if (c.high > maxP) maxP = c.high;
    }
    final extras = <double?>[
      frame.support,
      frame.resistance,
      ...?frame.emaFast,
      ...?frame.emaSlow,
      ...?frame.vwap,
    ];
    for (final e in extras) {
      if (e == null) continue;
      if (e < minP) minP = e;
      if (e > maxP) maxP = e;
    }
    if (!minP.isFinite || !maxP.isFinite || maxP <= minP) return;
    final span = maxP - minP;
    minP -= span * 0.04;
    maxP += span * 0.04;
    final range = maxP - minP;

    double y(double p) => padTop + (maxP - p) / range * plotH;
    final step = plotW / candles.length;
    double x(int i) => i * step + step / 2;

    // --- grid ---
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );
    const gridLines = 5;
    for (var g = 0; g <= gridLines; g++) {
      final price = minP + range * g / gridLines;
      final yy = y(price);
      canvas.drawLine(Offset(0, yy), Offset(plotW, yy), gridPaint);
      textPainter.text = TextSpan(
        text: price.toStringAsFixed(price >= 1000 ? 0 : 2),
        style: TextStyle(color: muted, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(plotW + 6, yy - 6));
    }

    // --- candles ---
    final bodyW = max(step * 0.62, 1.2);
    for (var i = 0; i < candles.length; i++) {
      final c = candles[i];
      final up = c.close >= c.open;
      final color = up ? TrTheme.up : TrTheme.down;
      final paint = Paint()..color = color;
      final cx = x(i);
      // wick
      canvas.drawLine(
        Offset(cx, y(c.high)),
        Offset(cx, y(c.low)),
        paint..strokeWidth = 1,
      );
      // body
      final top = y(max(c.open, c.close));
      final bottom = y(min(c.open, c.close));
      final rect = Rect.fromLTRB(cx - bodyW / 2, top, cx + bodyW / 2,
          max(bottom, top + 0.8));
      canvas.drawRect(rect, paint);
    }

    // --- overlays ---
    void polyline(List<double?>? values, Color color, double width) {
      if (values == null) return;
      final path = Path();
      var started = false;
      for (var i = 0; i < values.length && i < candles.length; i++) {
        final v = values[i];
        if (v == null) {
          started = false;
          continue;
        }
        final p = Offset(x(i), y(v));
        if (!started) {
          path.moveTo(p.dx, p.dy);
          started = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = width,
      );
    }

    polyline(frame.emaFast, TrTheme.accent, 1.4);
    polyline(frame.emaSlow, TrTheme.warn, 1.4);
    polyline(frame.vwap, const Color(0xFFB388FF), 1.2);

    void level(double? price, Color color, String label) {
      if (price == null) return;
      final yy = y(price);
      final dash = Paint()
        ..color = color
        ..strokeWidth = 1;
      const dashLen = 6.0;
      for (var dx = 0.0; dx < plotW; dx += dashLen * 2) {
        canvas.drawLine(Offset(dx, yy), Offset(dx + dashLen, yy), dash);
      }
      textPainter.text = TextSpan(
        text: ' $label ${price.toStringAsFixed(2)}',
        style: TextStyle(color: color, fontSize: 10),
      );
      textPainter.layout();
      textPainter.paint(canvas, Offset(4, yy - 12));
    }

    level(frame.support, TrTheme.up, 'S');
    level(frame.resistance, TrTheme.down, 'R');

    // --- markers ---
    for (final (idx, label, color) in frame.markers) {
      if (idx < 0 || idx >= candles.length) continue;
      final c = candles[idx];
      final cx = x(idx);
      final isBuy = label == 'BUY' || label == 'LONG';
      final yy = isBuy ? y(c.low) + 14 : y(c.high) - 14;
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      );
      textPainter.layout();
      final tpw = textPainter.width;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(cx, yy), width: tpw + 8, height: 14),
          const Radius.circular(3),
        ),
        Paint()..color = color.withOpacity(0.22),
      );
      textPainter.paint(canvas, Offset(cx - tpw / 2, yy - 7));
    }

    // --- time labels ---
    final labelEvery = max((candles.length / 5).ceil(), 1);
    for (var i = 0; i < candles.length; i += labelEvery) {
      final t = candles[i].time;
      final label =
          '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(color: muted, fontSize: 9),
      );
      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(min(x(i) - 20, plotW - 40), size.height - 14),
      );
    }
  }

  @override
  bool shouldRepaint(CandlePainter old) =>
      old.frame != frame || old.frame.candles != frame.candles;
}
