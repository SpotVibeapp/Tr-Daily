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
    );
    expect(plan.dayStartEquity, 1500);
    expect(plan.band, AccountBand.micro);
    expect(plan.allowShort, isFalse);
    expect(plan.keepLowerPriced, isFalse);
  });

  test('the top band still keeps cheap names', () {
    final plan = scalePlan(
      account: acct(equity: 26000, lastEquity: 25000),
      settings: AppSettings(),
    );
    expect(plan.fullDayTrade, isTrue);
    expect(plan.keepLowerPriced, isTrue);
    expect(plan.opportunityCeiling, greaterThan(plan.cheapCeiling));
    expect(plan.summary, contains('does not guarantee'));
  });

  test('no balance caps day trades any more (PDT rule retired 2026-06-04)',
      () {
    for (final equity in <double>[100, 1999, 10000, 24999]) {
      final plan = scalePlan(
        account: acct(equity: equity, lastEquity: equity),
        settings: AppSettings(),
      );
      expect(plan.summary, contains('not capped by count'));
      expect(plan.summary, isNot(contains('25,000')));
      expect(plan.summary, isNot(contains('4th day trade')));
    }
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
