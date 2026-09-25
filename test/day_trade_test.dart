import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/day_trade.dart';

SignalScore setup({
  required double price,
  required double target,
  double? stop,
  double score = 0.6,
}) {
  return SignalScore(
    symbol: 'TEST',
    score: score,
    confidence: 0.8,
    stance: Stance.long,
    reasons: const <String>[],
    price: price,
    generatedAt: DateTime(2026, 6, 10, 10),
    suggestedStop: stop,
    suggestedTarget: target,
  );
}

void main() {
  test('a quiet target under 1% of price is not a day trade', () {
    final check = checkDayTrade(
      sig: setup(price: 20, target: 20.10, stop: 19.94),
      equity: 100,
      qty: 1,
      stopPrice: 19.94,
      minTargetPct: 1,
      riskPerTradePct: 0.75,
    );
    expect(check.skip, DayTradeSkip.quiet);
    expect(check.detail, contains('under'));
  });

  test('a cheap name with a 5% target fits a 100 dollar account', () {
    // $4 share, target $4.20, stop $3.88. One share risks $0.12 = 0.12%.
    final check = checkDayTrade(
      sig: setup(price: 4, target: 4.20, stop: 3.88),
      equity: 100,
      qty: 1,
      stopPrice: 3.88,
      minTargetPct: 1,
      riskPerTradePct: 0.75,
    );
    expect(check.allowed, isTrue);
    expect(check.targetPct, closeTo(5, 0.01));
  });

  test('one share that blows the risk setting is not forced', () {
    // $8 share, stop $4.80 risks $3.20 = 3.2% of $100.
    // Cap is 0.75 * 2.5 = 1.875%.
    final check = checkDayTrade(
      sig: setup(price: 8, target: 10, stop: 4.8),
      equity: 100,
      qty: 1,
      stopPrice: 4.8,
      minTargetPct: 1,
      riskPerTradePct: 0.75,
    );
    expect(check.skip, DayTradeSkip.oversized);
    expect(check.accountRiskPct, closeTo(3.2, 0.01));
  });

  test('higher percentage targets are tried first', () {
    final quiet = setup(price: 20, target: 20.30, score: 0.9);
    final mover = setup(price: 4, target: 4.40, score: 0.5);
    final ranked = rankForDayTrade(<SignalScore>[quiet, mover]);
    expect(ranked.first.price, 4);
  });
}
