import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/estimator.dart';
import 'package:tr_daily/data/market_data_source.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/strategy/ensemble.dart';
import 'package:tr_daily/strategy/signals.dart';

void main() {
  test('estimator emits features, trend read and levels on synthetic data', () async {
    final source = SyntheticMarketSource(seed: 5);
    final bars = await source.getBars(
      symbol: 'T',
      interval: BarInterval.fiveMin,
      limit: 200,
    );
    const estimator = TrendEstimator();
    final snap = estimator.estimate(bars);

    expect(snap.features.length, SignalEnsemble.featureOrder.length);
    for (final key in SignalEnsemble.featureOrder) {
      expect(snap.features.containsKey(key), isTrue,
          reason: 'missing ML feature: $key');
      expect(snap.features[key]!.isFinite, isTrue);
    }
    expect(snap.trendScore, greaterThanOrEqualTo(-1));
    expect(snap.trendScore, lessThanOrEqualTo(1));
    expect(snap.trendConfidence, inInclusiveRange(0, 1));
    expect(snap.atrValue, greaterThan(0));
    expect(snap.summary, isNotEmpty);
  });

  test('insufficient data returns neutral snapshot', () {
    const estimator = TrendEstimator();
    final snap = estimator.estimate(const []);
    expect(snap.trendScore, 0);
    expect(snap.trendConfidence, 0);
    expect(snap.summary, contains('insufficient'));
  });

  test('IndicatorBundle exposes aligned series', () async {
    final bars = await SyntheticMarketSource(seed: 9).getBars(
      symbol: 'T',
      interval: BarInterval.fiveMin,
      limit: 120,
    );
    final b = IndicatorBundle(bars);
    expect(b.emaFast.length, bars.length);
    expect(b.emaSlow.length, bars.length);
    expect(b.rsiSeries.length, bars.length);
    expect(b.macdSeries.histogram.length, bars.length);
    expect(b.i, bars.length - 1);
    expect(allSignals(b).length, 7);
    expect(adxGate(b), inInclusiveRange(0.35, 1.0));
  });
}
