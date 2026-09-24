import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/estimator.dart';
import 'package:tr_daily/analysis/ml.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/strategy/ensemble.dart';
import 'package:tr_daily/strategy/signals.dart';

/// Deterministic synthetic series with a clear drift so tests are stable.
List<Candle> trendSeries(int n, {required double drift, double start = 100}) {
  var p = start;
  final out = <Candle>[];
  for (var i = 0; i < n; i++) {
    final o = p;
    // Gentle wave + drift keeps indicators away from degenerate flatlines.
    p = p * (1 + drift) + 0.6 * (i % 5 - 2);
    final h = (o > p ? o : p) + 0.5;
    final l = (o < p ? o : p) - 0.5;
    out.add(Candle(
      symbol: 'TEST',
      time: DateTime(2026, 3, 2, 9, 30).add(Duration(minutes: 5 * i)),
      open: o,
      high: h,
      low: l,
      close: p,
      volume: 100000 + i * 100,
    ));
  }
  return out;
}

void main() {
  const estimator = TrendEstimator();
  final ensemble = SignalEnsemble();

  group('SignalEnsemble.evaluate', () {
    test('score ∈ [-1,1], breakdown covers every rule, reasons non-empty', () {
      final bars = trendSeries(120, drift: 0.004);
      final snap = estimator.estimate(bars);
      final bundle = IndicatorBundle(bars);
      final d = ensemble.evaluate(
        bars: bars,
        snapshot: snap,
        bundle: bundle,
        model: null,
      );
      expect(d.signal.score, greaterThanOrEqualTo(-1));
      expect(d.signal.score, lessThanOrEqualTo(1));
      expect(d.signal.breakdown.length, allOf(greaterThan(3)));
      for (final name in ['EMA 9/21', 'MACD', 'VWAP', 'Breakout']) {
        expect(d.signal.breakdown.containsKey(name), isTrue,
            reason: 'rule $name must appear in breakdown');
      }
      expect(d.signal.reasons, isNotEmpty);
      expect(d.signal.confidence, greaterThanOrEqualTo(0));
      expect(d.signal.confidence, lessThanOrEqualTo(1));
      expect(d.action, anyOf('long', 'short', 'flat'));
    });

    test('clear uptrend scores bullish, downtrend bearish', () {
      final up = trendSeries(140, drift: 0.006);
      final upD = ensemble.evaluate(
        bars: up,
        snapshot: estimator.estimate(up),
        bundle: IndicatorBundle(up),
        model: null,
      );
      expect(upD.signal.score, greaterThan(0),
          reason: 'strong uptrend must not read bearish');

      final down = trendSeries(140, drift: -0.006, start: 300);
      final downD = ensemble.evaluate(
        bars: down,
        snapshot: estimator.estimate(down),
        bundle: IndicatorBundle(down),
        model: null,
      );
      expect(downD.signal.score, lessThan(0),
          reason: 'strong downtrend must not read bullish');
    });

    test('suggests ATR-based stop and target consistent with stance', () {
      final bars = trendSeries(120, drift: 0.005);
      final d = ensemble.evaluate(
        bars: bars,
        snapshot: estimator.estimate(bars),
        bundle: IndicatorBundle(bars),
        model: null,
      );
      if (d.signal.stance == Stance.long) {
        expect(d.signal.suggestedStop!, lessThan(d.signal.price));
        expect(d.signal.suggestedTarget!, greaterThan(d.signal.price));
      } else if (d.signal.stance == Stance.short) {
        expect(d.signal.suggestedStop!, greaterThan(d.signal.price));
        expect(d.signal.suggestedTarget!, lessThan(d.signal.price));
      } else {
        expect(d.signal.suggestedStop, isNull);
      }
    });

    test('shouldExit flips logic per stance', () {
      final cfg = const EnsembleConfig(exitThreshold: 0.1);
      expect(
        ensemble.shouldExit(
          positionStance: Stance.long,
          score: -0.3,
          confidence: 0.6,
          entryScore: 0.5,
        ),
        isTrue,
      );
      expect(
        ensemble.shouldExit(
          positionStance: Stance.long,
          score: 0.7,
          confidence: 0.6,
          entryScore: 0.5,
        ),
        isFalse,
      );
      expect(
        ensemble.shouldExit(
          positionStance: Stance.short,
          score: 0.4,
          confidence: 0.6,
          entryScore: -0.5,
        ),
        isTrue,
      );
      expect(cfg.enterThreshold, 0.45); // default untouched
    });
  });

  group('OnlineLogistic', () {
    test('learns a separable 1-D problem', () {
      final model = OnlineLogistic(dim: 2);
      final rnd = _LCG(42);
      for (var i = 0; i < 400; i++) {
        final x1 = rnd.next() * 4 - 2;
        final x2 = rnd.next() * 4 - 2;
        final label = (x1 + 0.5 * x2 > 0) ? 1 : 0;
        model.trainStep([x1, x2], label);
      }
      expect(model.isUsable, isTrue);
      var correct = 0;
      const trials = 200;
      for (var i = 0; i < trials; i++) {
        final x1 = rnd.next() * 4 - 2;
        final x2 = rnd.next() * 4 - 2;
        final label = (x1 + 0.5 * x2 > 0) ? 1 : 0;
        final p = model.predictRaw([x1, x2]);
        if ((p >= 0.5 ? 1 : 0) == label) correct++;
      }
      expect(correct / trials, greaterThan(0.8),
          reason: 'model must learn the obvious rule');
    });

    test('not usable before enough samples', () {
      final model = OnlineLogistic(dim: 2);
      expect(model.isUsable, isFalse);
      for (var i = 0; i < 10; i++) {
        model.trainStep([i.toDouble(), 0], i.isEven ? 1 : 0);
      }
      expect(model.samplesSeen, 10);
      expect(model.isUsable, isFalse);
    });

    test('normalizer standardizes observed data', () {
      final norm = FeatureNormalizer(1);
      for (var i = 0; i < 50; i++) {
        norm.observe([i.toDouble()]);
      }
      final z = norm.normalize([25.0]);
      expect(z[0], closeTo(0, 0.3));
      final zHigh = norm.normalize([60.0]);
      expect(zHigh[0], greaterThan(2));
    });
  });
}

/// Tiny deterministic PRNG (no dart:math Random dependency on seeds).
class _LCG {
  _LCG(this.seed);
  int seed;
  double next() {
    seed = (seed * 1664525 + 1013904223) & 0x7fffffff;
    return seed / 0x7fffffff;
  }
}
