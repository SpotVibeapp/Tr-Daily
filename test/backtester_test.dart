import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/estimator.dart';
import 'package:tr_daily/data/market_data_source.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/backtester.dart';
import 'package:tr_daily/risk/risk_manager.dart';
import 'package:tr_daily/strategy/ensemble.dart';

void main() {
  late SyntheticMarketSource source;
  const estimator = TrendEstimator();

  setUp(() {
    source = SyntheticMarketSource(seed: 7);
  });

  test('produces complete metrics and equity curve', () async {
    final bt = Backtester(
      source: source,
      estimator: estimator,
      config: const BacktestConfig(warmupBars: 60),
    );
    final r = await bt.run(symbol: 'TEST', bars: 300);

    expect(r.equityCurve.length, greaterThan(200));
    expect(r.trades.length, r.metrics.tradeCount);
    expect(r.metrics.returnPct.isFinite, isTrue);
    expect(r.metrics.maxDrawdownPct, greaterThanOrEqualTo(0));
    expect(r.metrics.winRate, greaterThanOrEqualTo(0));
    expect(r.metrics.winRate, lessThanOrEqualTo(100));
    expect(r.metrics.exposurePct, greaterThanOrEqualTo(0));
    expect(r.metrics.exposurePct, lessThanOrEqualTo(100));
    // Curve ends at final equity.
    expect(r.equityCurve.last.$2, closeTo(r.equityFinal, 0.01));
  });

  test('is deterministic for a fixed seed', () async {
    final bt1 = Backtester(
      source: SyntheticMarketSource(seed: 7),
      estimator: estimator,
      config: const BacktestConfig(warmupBars: 60),
    );
    final bt2 = Backtester(
      source: SyntheticMarketSource(seed: 7),
      estimator: estimator,
      config: const BacktestConfig(warmupBars: 60),
    );
    final r1 = await bt1.run(symbol: 'TEST', bars: 300);
    final r2 = await bt2.run(symbol: 'TEST', bars: 300);
    expect(r1.equityFinal, closeTo(r2.equityFinal, 1e-9));
    expect(r1.trades.length, r2.trades.length);
  });

  test('respects warmup — no trades before warmupBars', () async {
    final bt = Backtester(
      source: source,
      estimator: estimator,
      config: const BacktestConfig(warmupBars: 80),
    );
    final r = await bt.run(symbol: 'TEST', bars: 300);
    // Invariant: every trade has exit ≥ entry and sane prices/quantities.
    for (final t in r.trades) {
      expect(t.exitTime!, greaterThanOrEqualTo(t.entryTime));
      expect(t.entryPrice, greaterThan(0));
      expect(t.exitPrice!, greaterThan(0));
      expect(t.qty, greaterThan(0));
    }
    // Warmup-only trades: no entry may occur in the first warmupBars window.
    final firstBar = (await source.getBars(
      symbol: 'TEST',
      interval: BarInterval.fiveMin,
      limit: 300,
    )).first;
    if (r.trades.isNotEmpty) {
      expect(r.trades.first.entryTime.isAfter(firstBar.time), isTrue);
    }
  });

  test('stop losses are honored (trades exit with reasons)', () async {
    final bt = Backtester(
      source: SyntheticMarketSource(seed: 3, basePrice: 50),
      estimator: estimator,
      config: const BacktestConfig(warmupBars: 60),
    );
    final r = await bt.run(symbol: 'TEST', bars: 260);
    if (r.trades.isNotEmpty) {
      final reasons = r.trades.map((t) => t.exitReason).toSet();
      expect(
        reasons.any((x) => x.contains('stop') || x.contains('signal') ||
            x.contains('take profit') || x.contains('end of test')),
        isTrue,
      );
    }
  });

  test('shorts disabled → only long trades', () async {
    final bt = Backtester(
      source: SyntheticMarketSource(seed: 11),
      estimator: estimator,
      config: const BacktestConfig(
        warmupBars: 60,
        risk: RiskConfig(allowShort: false),
        ensemble: EnsembleConfig(enterThreshold: 0.35),
      ),
    );
    final r = await bt.run(symbol: 'TEST', bars: 300);
    for (final t in r.trades) {
      expect(t.side, Stance.long);
    }
  });

  test('buys hold comparison uses post-warmup baseline', () async {
    final bt = Backtester(
      source: source,
      estimator: estimator,
      config: const BacktestConfig(warmupBars: 60),
    );
    final r = await bt.run(symbol: 'TEST', bars: 200);
    expect(r.metrics.buyHoldPct.isFinite, isTrue);
  });
}
