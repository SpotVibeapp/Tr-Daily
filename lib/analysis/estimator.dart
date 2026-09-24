import 'dart:math';

import '../data/models.dart';
import 'indicators.dart';
import 'structure.dart';

/// Result of full technical analysis on one symbol's history.
class AnalysisSnapshot {
  const AnalysisSnapshot({
    required this.trendScore,
    required this.trendConfidence,
    required this.patterns,
    required this.patternScore,
    required this.priceToVwapPct,
    required this.features,
    this.support,
    this.resistance,
    this.atrValue,
    this.summary = '',
  });

  /// Trend in [-1, 1]: positive = uptrend.
  final double trendScore;

  /// How trustworthy the trend read is, [0, 1] (regression fit, ADX, EMA order).
  final double trendConfidence;

  final Set<CandlePattern> patterns;

  /// Candle-pattern lean in [-1, 1].
  final double patternScore;

  /// Distance from session VWAP in percent.
  final double priceToVwapPct;

  /// Nearest support/resistance below/above price (null if none nearby).
  final double? support;
  final double? resistance;

  final double? atrValue;

  /// Feature vector for the ML layer (raw, unscaled).
  final Map<String, double> features;

  final String summary;
}

/// Combines indicators, structure and pattern analysis into a single
/// trend read + feature vector. All inputs are causal (no lookahead).
class TrendEstimator {
  const TrendEstimator({
    this.emaFast = 9,
    this.emaSlow = 21,
    this.rsiPeriod = 14,
    this.adxPeriod = 14,
    this.channelPeriod = 20,
    this.pivotK = 3,
  });

  final int emaFast;
  final int emaSlow;
  final int rsiPeriod;
  final int adxPeriod;
  final int channelPeriod;
  final int pivotK;

  AnalysisSnapshot estimate(List<Candle> bars) {
    if (bars.length < 30) {
      return AnalysisSnapshot(
        trendScore: 0,
        trendConfidence: 0,
        patterns: <CandlePattern>{},
        patternScore: 0,
        priceToVwapPct: 0,
        features: <String, double>{},
        summary: 'insufficient data (${bars.length} bars)',
      );
    }

    final closes = bars.map((b) => b.close).toList();
    final last = bars.length - 1;
    final price = closes[last];

    // --- Indicator reads (all index-causal) ---
    final emaF = ema(closes, emaFast);
    final emaS = ema(closes, emaSlow);
    final rsiSeries = rsi(closes, rsiPeriod);
    final macdSeries = macd(closes);
    final bb = bollinger(closes);
    final atrSeries = atr(bars, adxPeriod);
    final adxSeries = adx(bars, adxPeriod);
    final vwapSeries = sessionVwap(bars);
    final donch = donchian(bars, period: channelPeriod);
    final slope = linregSlope(closes.sublist(max(0, last - channelPeriod + 1)), channelPeriod);
    final stochSeries = stochastic(bars);
    final rocSeries = roc(closes, 5);

    final fast = emaF[last];
    final slow = emaS[last];
    final rsiNow = rsiSeries[last];
    final hist = macdSeries.histogram[last];
    final histPrev = last > 0 ? macdSeries.histogram[last - 1] : null;
    final pctB = bb.percentB[last];
    final atrNow = atrSeries[last];
    final adxNow = adxSeries.adx[last];
    final plusDi = adxSeries.plusDi[last];
    final minusDi = adxSeries.minusDi[last];
    final vwapNow = vwapSeries[last];
    final slopeNow = slope.lastWhere((v) => v != null, orElse: () => null);
    final stochK = stochSeries.k[last];
    final roc5 = rocSeries[last] ?? 0;

    // --- Composite trend score ---
    var trend = 0.0;
    var trendParts = 0;

    if (fast != null && slow != null && slow != 0) {
      // EMA ordering & spread, scaled to a sensible band.
      final spread = (fast - slow) / slow;
      trend += (spread * 50).clamp(-1.0, 1.0);
      trendParts++;
    }
    if (hist != null && histPrev != null) {
      // MACD histogram sign + improving momentum.
      final sign = hist.sign;
      final improving = hist - histPrev;
      trend += 0.5 * sign + 0.5 * (improving.sign);
      trendParts++;
    }
    if (slopeNow != null) {
      trend += (slopeNow * 8).clamp(-1.0, 1.0);
      trendParts++;
    }
    if (plusDi != null && minusDi != null && (plusDi + minusDi) > 0) {
      trend += (plusDi - minusDi) / (plusDi + minusDi);
      trendParts++;
    }
    final trendScore =
        trendParts == 0 ? 0.0 : (trend / trendParts).clamp(-1.0, 1.0);

    // --- Trend confidence: agreement quality ---
    var conf = 0.0;
    if (adxNow != null) {
      // ADX < 15 = chop (low conf), 25+ = established trend.
      conf += ((adxNow - 12) / 20).clamp(0.0, 1.0) * 0.5;
    }
    if (fast != null && slow != null) {
      final aligned =
          (trendScore > 0 && fast > slow) || (trendScore < 0 && fast < slow);
      conf += (aligned ? 0.3 : 0.05);
    }
    if (trendScore.abs() > 0.3) conf += 0.2;
    final trendConfidence = conf.clamp(0.0, 1.0);

    // --- Structure ---
    final pivots = findPivots(bars, k: pivotK);
    final levels = buildLevels(candles: bars, pivots: pivots, upTo: last);
    double? support;
    double? resistance;
    for (final l in levels) {
      if (l.isSupport && l.price < price) {
        support = (support == null || l.price > support) ? l.price : support;
      } else if (!l.isSupport && l.price > price) {
        resistance =
            (resistance == null || l.price < resistance) ? l.price : resistance;
      }
    }

    // Trendline through recent pivot lows/highs (only confirmed pivots).
    final confirmedLow = <(int, double)>[
      for (final p in pivots)
        if (p.confirmIndex <= last && !p.isHigh) (p.index, p.price)
    ];
    final confirmedHigh = <(int, double)>[
      for (final p in pivots)
        if (p.confirmIndex <= last && p.isHigh) (p.index, p.price)
    ];
    final upLine = fitTrendline(confirmedLow.length >= 3
        ? confirmedLow.sublist(max(0, confirmedLow.length - 6))
        : confirmedLow);
    final downLine = fitTrendline(confirmedHigh.length >= 3
        ? confirmedHigh.sublist(max(0, confirmedHigh.length - 6))
        : confirmedHigh);
    var lineLean = 0.0;
    if (upLine != null && upLine.r2 > 0.55 && upLine.ascending) {
      lineLean = 0.4 * upLine.r2;
    }
    if (downLine != null && downLine.r2 > 0.55 && !downLine.ascending) {
      lineLean = -0.4 * downLine.r2;
    }

    // --- Patterns ---
    final patterns = detectPatterns(bars, last);
    final patternScore = patternLean(patterns);

    // --- VWAP ---
    final vwapPct =
        (vwapNow != null && vwapNow != 0) ? (price - vwapNow) / vwapNow * 100 : 0.0;

    // --- Feature vector (for ML + explainability) ---
    final rangeHigh = donch.upper[last];
    final rangeLow = donch.lower[last];
    final positionInRange = (rangeHigh != null && rangeLow != null && rangeHigh > rangeLow)
        ? (price - rangeLow) / (rangeHigh - rangeLow) * 2 - 1
        : 0.0;

    final features = <String, double>{
      'ema_spread': (fast != null && slow != null && slow != 0)
          ? (fast - slow) / slow * 100
          : 0,
      'rsi': rsiNow ?? 50,
      'macd_hist_norm': (hist != null && price != 0) ? hist / price * 1000 : 0,
      'macd_hist_delta': (hist != null && histPrev != null) ? (hist - histPrev) : 0,
      'adx': adxNow ?? 0,
      'di_diff': (plusDi != null && minusDi != null) ? plusDi - minusDi : 0,
      'vwap_dist': vwapPct,
      'bb_pctb': pctB != null ? (pctB - 0.5) * 2 : 0,
      'slope': slopeNow ?? 0,
      'roc5': roc5,
      'range_pos': positionInRange,
      'stoch_k': stochK ?? 50,
      'pattern': patternScore,
      'vol_z': _volumeZ(bars),
    };

    // Weighted final read = structure blend.
    final blended = (trendScore * 0.75 + lineLean + patternScore * 0.25)
        .clamp(-1.0, 1.0);

    final summary = _summary(blended, trendConfidence, price, support, resistance);

    return AnalysisSnapshot(
      trendScore: blended,
      trendConfidence: trendConfidence,
      patterns: patterns,
      patternScore: patternScore,
      priceToVwapPct: vwapPct,
      support: support,
      resistance: resistance,
      atrValue: atrNow,
      features: features,
      summary: summary,
    );
  }

  static double _volumeZ(List<Candle> bars) {
    if (bars.length < 20) return 0;
    final window = bars.sublist(bars.length - 20).map((b) => b.volume).toList();
    final mean = window.reduce((a, b) => a + b) / window.length;
    final varr =
        window.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            window.length;
    final sd = sqrt(varr);
    if (sd == 0) return 0;
    return ((bars.last.volume - mean) / sd).clamp(-3.0, 3.0);
  }

  static String _summary(double score, double conf, double price,
      double? support, double? resistance) {
    final dir = score > 0.25
        ? 'uptrend'
        : score < -0.25
            ? 'downtrend'
            : 'sideways';
    final bits = <String>['$dir (score ${score.toStringAsFixed(2)}, conf ${(conf * 100).round()}%)'];
    if (support != null) {
      bits.add('support \$${support.toStringAsFixed(2)}');
    }
    if (resistance != null) {
      bits.add('resistance \$${resistance.toStringAsFixed(2)}');
    }
    return bits.join(' · ');
  }
}
