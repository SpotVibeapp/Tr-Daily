import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/live_readiness.dart';
import 'package:tr_daily/analysis/portfolio_analytics.dart';
import 'package:tr_daily/broker/paper_broker.dart';
import 'package:tr_daily/data/models.dart';

/// [pnls] round trips of 10 shares from $10, one per hour.
List<PaperFill> _roundTrips(List<double> pnls) {
  final out = <PaperFill>[];
  var t = DateTime(2026, 9, 1, 10);
  for (var i = 0; i < pnls.length; i++) {
    out.add(PaperFill(
      id: 'b$i',
      symbol: 'X',
      side: OrderSide.buy,
      qty: 10,
      price: 10,
      time: t,
      realizedPnl: 0,
    ));
    t = t.add(const Duration(minutes: 30));
    out.add(PaperFill(
      id: 's$i',
      symbol: 'X',
      side: OrderSide.sell,
      qty: 10,
      price: 10 + pnls[i] / 10,
      time: t,
      realizedPnl: pnls[i],
    ));
    t = t.add(const Duration(minutes: 30));
  }
  return out;
}

LiveReadiness _check(List<double> pnls, {double start = 100}) =>
    LiveReadiness.fromPerformance(
      PortfolioPerformance.fromFills(_roundTrips(pnls)),
      startingEquity: start,
    );

void main() {
  test('no trades is not ready', () {
    final r = _check(const <double>[]);
    expect(r.ready, isFalse);
    expect(r.passedCount, 0);
    expect(r.checks.first.detail, '0 of 50');
  });

  test('a small profitable sample is not enough', () {
    final r = _check(List<double>.filled(10, 1.0));
    expect(r.ready, isFalse);
    expect(r.checks[0].passed, isFalse);
    expect(r.checks[1].passed, isTrue);
  });

  test('50 trades with an edge and a shallow drawdown is ready', () {
    // 30 wins of $1, 20 losses of $0.50: PF 3.0, +$0.40 a trade.
    final pnls = <double>[
      for (var i = 0; i < 50; i++) i.isEven || i % 5 == 1 ? 1.0 : -0.5,
    ];
    final r = _check(pnls);
    expect(r.checks.map((c) => c.passed), everyElement(isTrue));
    expect(r.ready, isTrue);
    expect(r.summary, contains('does not guarantee'));
  });

  test('losing after costs fails', () {
    final r = _check(<double>[
      for (var i = 0; i < 60; i++) i.isEven ? 0.5 : -0.6,
    ]);
    expect(r.checks[1].passed, isFalse);
    expect(r.checks[2].passed, isFalse);
    expect(r.ready, isFalse);
  });

  test('drawdown is measured from the running peak', () {
    final trades = PortfolioPerformance.fromFills(
      _roundTrips(<double>[10, -22, 5]),
    ).trades;
    // 100 → 110 (peak) → 88: 20% down from the peak.
    expect(closedTradeDrawdownPct(trades, 100), closeTo(20, 1e-9));
  });
}
