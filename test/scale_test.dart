import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/scale.dart';

AccountInfo acct({
  required double equity,
  double? lastEquity,
  double? buyingPower,
}) {
  return AccountInfo(
    equity: equity,
    cash: equity,
    buyingPower: buyingPower ?? equity,
    dayTradeCount: 0,
    lastEquity: lastEquity,
  );
}

void main() {
  test('bands follow the day-start balance, including a setback', () {
    expect(bandForEquity(100), AccountBand.micro);
    expect(bandForEquity(1999), AccountBand.micro);
    expect(bandForEquity(2000), AccountBand.building);
    expect(bandForEquity(24999), AccountBand.building);
    expect(bandForEquity(25000), AccountBand.fullDayTrade);

    final plan = scalePlan(
      account: acct(equity: 8000, lastEquity: 1500),
      settings: AppSettings(),
      dayTradeCount: 0,
    );
    expect(plan.dayStartEquity, 1500);
    expect(plan.band, AccountBand.micro);
    expect(plan.allowShort, isFalse);
    expect(plan.pdtApplies, isTrue);
    expect(plan.keepLowerPriced, isFalse);
  });

  test('full day trading unlocks at 25000 and still keeps cheap names', () {
    final plan = scalePlan(
      account: acct(equity: 26000, lastEquity: 25000),
      settings: AppSettings(),
      dayTradeCount: 6,
    );
    expect(plan.fullDayTrade, isTrue);
    expect(plan.pdtApplies, isFalse);
    expect(plan.pdtBlocked, isFalse);
    expect(plan.keepLowerPriced, isTrue);
    expect(plan.opportunityCeiling, greaterThan(plan.cheapCeiling));
    expect(plan.summary, contains('Full day trading'));
    expect(plan.summary, contains('does not guarantee'));
  });

  test('a fourth day trade is skipped only under 25000', () {
    final small = scalePlan(
      account: acct(equity: 10000, lastEquity: 10000),
      settings: AppSettings(),
      dayTradeCount: 4,
    );
    expect(small.pdtBlocked, isTrue);
    final room = scalePlan(
      account: acct(equity: 10000, lastEquity: 10000),
      settings: AppSettings(),
      dayTradeCount: 3,
    );
    expect(room.pdtBlocked, isFalse);
  });

  test('conviction raises risk only for a strong target', () {
    expect(
      convictionRiskPct(
        basePct: 0.75,
        targetPct: 1.0,
        confidence: 0.9,
        minTargetPct: 1,
        enabled: true,
      ),
      0.75,
    );
    expect(
      convictionRiskPct(
        basePct: 0.75,
        targetPct: 2.1,
        confidence: 0.6,
        minTargetPct: 1,
        enabled: true,
      ),
      closeTo(1.125, 1e-9),
    );
    expect(
      convictionRiskPct(
        basePct: 0.75,
        targetPct: 4,
        confidence: 0.8,
        minTargetPct: 1,
        enabled: true,
      ),
      1.5,
    );
    expect(
      convictionRiskPct(
        basePct: 0.75,
        targetPct: 4,
        confidence: 0.9,
        minTargetPct: 1,
        enabled: false,
      ),
      0.75,
    );
  });
}
