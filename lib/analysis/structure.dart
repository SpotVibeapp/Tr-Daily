import 'dart:math';

import '../data/models.dart';
import 'indicators.dart';

/// Swing pivot (fractal) point.
class Pivot {
  const Pivot({
    required this.index,
    required this.price,
    required this.isHigh,
    required this.confirmIndex,
  });

  final int index;
  final double price;
  final bool isHigh;

  /// Earliest bar index at which this pivot is known (index + k). Only use a
  /// pivot when `confirmIndex <= currentBar` — never look ahead.
  final int confirmIndex;
}

/// Detect confirmed swing highs/lows: bar [i] is a swing high when its high is
/// strictly higher than the k bars on each side.
List<Pivot> findPivots(List<Candle> candles, {int k = 3}) {
  final out = <Pivot>[];
  for (var i = k; i < candles.length - k; i++) {
    var isHigh = true;
    var isLow = true;
    for (var j = 1; j <= k; j++) {
      if (candles[i].high <= candles[i - j].high ||
          candles[i].high <= candles[i + j].high) {
        isHigh = false;
      }
      if (candles[i].low >= candles[i - j].low ||
          candles[i].low >= candles[i + j].low) {
        isLow = false;
      }
      if (!isHigh && !isLow) break;
    }
    if (isHigh) {
      out.add(Pivot(
        index: i,
        price: candles[i].high,
        isHigh: true,
        confirmIndex: i + k,
      ));
    }
    if (isLow) {
      out.add(Pivot(
        index: i,
        price: candles[i].low,
        isHigh: false,
        confirmIndex: i + k,
      ));
    }
  }
  return out;
}

/// A horizontal support/resistance zone.
class PriceLevel {
  const PriceLevel({
    required this.price,
    required this.touches,
    required this.strength,
    required this.isSupport,
  });

  final double price;
  final int touches;

  /// 0..1
  final double strength;
  final bool isSupport;

  String get label => isSupport ? 'S' : 'R';
}

/// Cluster confirmed pivots into S/R levels. Pivots are filtered by
/// [confirmIndex <= upTo] so nothing from the future leaks in.
List<PriceLevel> buildLevels({
  required List<Candle> candles,
  required List<Pivot> pivots,
  required int upTo,
  double? tolerance,
}) {
  final ref = upTo < candles.length ? candles[upTo] : candles.last;
  final atrList = atr(candles.sublist(0, min(upTo + 1, candles.length)), 14);
  final atrNow = atrList.isNotEmpty ? (atrList.last ?? 0) : 0.0;
  final tol = tolerance ??
      (atrNow > 0 ? atrNow * 0.6 : max(ref.close * 0.004, 0.01));

  final usable = pivots
      .where((p) => p.confirmIndex <= upTo && p.index >= upTo - 80)
      .toList();
  if (usable.isEmpty) return <PriceLevel>[];

  final clusters = <List<Pivot>>[];
  final sorted = [...usable]..sort((a, b) => a.price.compareTo(b.price));
  for (final p in sorted) {
    if (clusters.isNotEmpty &&
        (p.price - clusters.last.last.price).abs() <= tol) {
      clusters.last.add(p);
    } else {
      clusters.add(<Pivot>[p]);
    }
  }

  final levels = <PriceLevel>[];
  for (final c in clusters) {
    final price = c.map((p) => p.price).reduce((a, b) => a + b) / c.length;
    final isSupport = price < ref.close;
    // More touches + more recent pivots = stronger.
    final recency = c
        .map((p) => 1.0 - (upTo - p.index) / 80.0)
        .fold<double>(0, (a, b) => a + max(b, 0.05)) /
        c.length;
    final strength =
        (c.length / 6.0).clamp(0.0, 1.0) * 0.6 + recency.clamp(0.0, 1.0) * 0.4;
    levels.add(PriceLevel(
      price: price,
      touches: c.length,
      strength: strength.clamp(0.0, 1.0),
      isSupport: isSupport,
    ));
  }
  levels.sort((a, b) => b.strength.compareTo(a.strength));
  return levels.take(6).toList();
}

/// Least-squares trendline through selected pivot prices.
class Trendline {
  const Trendline({
    required this.slope,
    required this.intercept,
    required this.r2,
    required this.ascending,
  });

  final double slope;
  final double intercept;
  final double r2;
  final bool ascending;

  double valueAt(double x) => slope * x + intercept;
}

/// Fit a line through pivot lows (ascending candidate) or pivot highs.
Trendline? fitTrendline(List<(int, double)> points) {
  if (points.length < 3) return null;
  final n = points.length.toDouble();
  var sx = 0.0, sy = 0.0, sxy = 0.0, sxx = 0.0, syy = 0.0;
  for (final (x, y) in points) {
    sx += x;
    sy += y;
    sxy += x * y;
    sxx += x * x;
    syy += y * y;
  }
  final denom = n * sxx - sx * sx;
  if (denom == 0) return null;
  final slope = (n * sxy - sx * sy) / denom;
  final intercept = (sy - slope * sx) / n;
  final rDenom = sqrt((n * sxx - sx * sx) * (n * syy - sy * sy));
  final r2 = rDenom == 0 ? 0.0 : ((n * sxy - sx * sy) / rDenom);
  return Trendline(
    slope: slope,
    intercept: intercept,
    r2: r2 * r2,
    ascending: slope > 0,
  );
}

enum CandlePattern {
  bullishEngulfing,
  bearingEngulfing,
  hammer,
  shootingStar,
  doji,
  bullishPin,
  bearishPin,
  insideBar,
  strongBullBar,
  strongBearBar,
}

/// Candlestick patterns visible **at bar [i]** (uses bars <= i only).
Set<CandlePattern> detectPatterns(List<Candle> candles, int i) {
  final out = <CandlePattern>{};
  if (i < 1 || candles.length < 2) return out;
  final c = candles[i];
  final p = candles[i - 1];
  final body = (c.close - c.open).abs();
  final range = max(c.high - c.low, 1e-9);
  final upperWick = c.high - max(c.open, c.close);
  final lowerWick = min(c.open, c.close) - c.low;

  final bull = c.close > c.open;
  final bear = c.close < c.open;

  // Engulfing.
  if (bull && p.close < p.open && c.close > p.open && c.open < p.close) {
    out.add(CandlePattern.bullishEngulfing);
  }
  if (bear && p.close > p.open && c.close < p.open && c.open > p.close) {
    out.add(CandlePattern.bearingEngulfing);
  }
  // Hammer / shooting star.
  if (lowerWick >= 2 * body && upperWick <= body && body / range < 0.35 && lowerWick / range > 0.5) {
    out.add(CandlePattern.hammer);
  }
  if (upperWick >= 2 * body && lowerWick <= body && body / range < 0.35 && upperWick / range > 0.5) {
    out.add(CandlePattern.shootingStar);
  }
  // Doji.
  if (body / range < 0.08) out.add(CandlePattern.doji);
  // Pins.
  if (lowerWick / range > 0.65) out.add(CandlePattern.bullishPin);
  if (upperWick / range > 0.65) out.add(CandlePattern.bearishPin);
  // Inside bar.
  if (c.high <= p.high && c.low >= p.low) out.add(CandlePattern.insideBar);
  // Strong directional bars.
  if (bull && body / range > 0.65 && body > 0) out.add(CandlePattern.strongBullBar);
  if (bear && body / range > 0.65 && body > 0) out.add(CandlePattern.strongBearBar);
  return out;
}

/// Overall candle-pattern lean in [-1, 1] for the bar at [i].
double patternLean(Set<CandlePattern> patterns) {
  var s = 0.0;
  for (final p in patterns) {
    switch (p) {
      case CandlePattern.bullishEngulfing:
      case CandlePattern.hammer:
      case CandlePattern.bullishPin:
      case CandlePattern.strongBullBar:
        s += 1;
      case CandlePattern.bearingEngulfing:
      case CandlePattern.shootingStar:
      case CandlePattern.bearishPin:
      case CandlePattern.strongBearBar:
        s -= 1;
      case CandlePattern.doji:
      case CandlePattern.insideBar:
        break;
    }
  }
  return s.clamp(-1.0, 1.0);
}
