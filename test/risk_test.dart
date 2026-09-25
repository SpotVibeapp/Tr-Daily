import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/risk/risk_manager.dart';

AccountInfo acct({double equity = 25000, double bp = 25000, bool blocked = false}) =>
    AccountInfo(
      equity: equity,
      cash: equity,
      buyingPower: bp,
      dayTradeCount: 0,
      isBlocked: blocked,
    );

void main() {
  group('RiskManager.entry', () {
    test('sizes position so stop distance risks ~riskPerTradePct of equity', () {
      final rm = RiskManager(config: const RiskConfig(riskPerTradePct: 1.0));
      final v = rm.entry(
        account: acct(),
        positions: const [],
        price: 100,
        atr: 2, // stop = 1.5 * 2 = 3 dollars away
        stance: Stance.long,
        confidence: 0.8,
        day: DateTime(2026, 6, 10, 10),
      );
      expect(v.allowed, isTrue);
      final qty = v.suggestedQty!;
      // Risk sizing wants ~83 (=$250 / $3 stop) but the default 25%
      // single-position cap limits it to floor(6250/100) = 62 shares.
      expect(qty, 62);
      expect(v.stopPrice, closeTo(97, 1e-9));
      expect(v.targetPrice, closeTo(105, 1e-9));
    });

    test('never exceeds max position %', () {
      final rm = RiskManager(
        config: const RiskConfig(
          riskPerTradePct: 5.0,
          maxPositionPct: 10,
        ),
      );
      final v = rm.entry(
        account: acct(),
        positions: const [],
        price: 100,
        atr: 0.05, // tiny stop → huge qty before cap
        stance: Stance.long,
        confidence: 0.9,
        day: DateTime(2026, 6, 10, 10),
      );
      expect(v.allowed, isTrue);
      // 10% of 25k = $2500 → max 25 shares.
      expect(v.suggestedQty!, lessThanOrEqualTo(25));
    });

    test('100 dollar account cannot buy a share above the 25% cap', () {
      final rm = RiskManager(config: const RiskConfig());
      final v = rm.entry(
        account: acct(equity: 100, bp: 100),
        positions: const [],
        price: 180,
        atr: 2,
        stance: Stance.long,
        confidence: 0.9,
        day: DateTime(2026, 6, 10, 10),
      );
      expect(v.allowed, isFalse);
      expect(v.haltReason, contains('exceeds budget'));
      expect(maxAffordableSharePrice(acct(equity: 100, bp: 100), const RiskConfig()), 25);
    });

    test('100 dollar account can buy a whole share of a 4 dollar name', () {
      final rm = RiskManager(config: const RiskConfig());
      final v = rm.entry(
        account: acct(equity: 100, bp: 100),
        positions: const [],
        price: 4,
        atr: 0.2,
        stance: Stance.long,
        confidence: 0.9,
        day: DateTime(2026, 6, 10, 10),
      );
      expect(v.allowed, isTrue);
      expect(v.suggestedQty, 2);
      expect(v.suggestedQty! * 4, lessThanOrEqualTo(25));
    });

    test('sizes from the day-start equity, not an intraday gain', () {
      final rm = RiskManager(config: const RiskConfig());
      final upOnTheDay = acct(equity: 5000, bp: 5000);
      final v = rm.entry(
        account: upOnTheDay,
        positions: const [],
        price: 400,
        atr: 4,
        stance: Stance.long,
        confidence: 0.9,
        day: DateTime(2026, 6, 10, 10),
        sizingEquity: 1000,
      );
      // 25% of today's start ($1,000) is $250. $400 does not fit, even
      // though the marked equity would allow it.
      expect(v.allowed, isFalse);
      expect(v.haltReason, contains('exceeds budget'));
    });

    test('denies when confidence below threshold', () {
      final rm = RiskManager(
          config: const RiskConfig(minConfidenceToTrade: 0.5));
      final v = rm.entry(
        account: acct(),
        positions: const [],
        price: 100,
        atr: 2,
        stance: Stance.long,
        confidence: 0.3,
        day: DateTime(2026, 6, 10, 10),
      );
      expect(v.allowed, isFalse);
      expect(v.haltReason, contains('confidence'));
    });

    test('denies when max open positions reached', () {
      final rm = RiskManager(config: const RiskConfig(maxOpenPositions: 2));
      const positions = [
        Position(symbol: 'A', qty: 1, avgEntryPrice: 10, currentPrice: 10),
        Position(symbol: 'B', qty: 1, avgEntryPrice: 10, currentPrice: 10),
      ];
      final v = rm.entry(
        account: acct(),
        positions: positions,
        price: 100,
        atr: 2,
        stance: Stance.long,
        confidence: 0.9,
        day: DateTime(2026, 6, 10, 10),
      );
      expect(v.allowed, isFalse);
      expect(v.haltReason, contains('max open positions'));
    });

    test('denies shorts when disabled', () {
      final rm = RiskManager(config: const RiskConfig(allowShort: false));
      final v = rm.entry(
        account: acct(),
        positions: const [],
        price: 100,
        atr: 2,
        stance: Stance.short,
        confidence: 0.9,
        day: DateTime(2026, 6, 10, 10),
      );
      expect(v.allowed, isFalse);
      expect(v.haltReason, contains('short selling disabled'));
    });
  });

  group('daily loss circuit breaker', () {
    test('halts when daily loss exceeds limit', () {
      final rm = RiskManager(config: const RiskConfig(maxDailyLossPct: 2));
      final day = DateTime(2026, 6, 10, 10);
      expect(rm.enforceDailyLoss(dayPnlPct: -1.0, day: day), isFalse);
      expect(rm.isHalted, isFalse);
      expect(rm.enforceDailyLoss(dayPnlPct: -2.5, day: day), isTrue);
      expect(rm.isHalted, isTrue);
      expect(rm.haltReason, contains('daily loss limit'));

      // Entry denied while halted.
      final v = rm.entry(
        account: acct(),
        positions: const [],
        price: 100,
        atr: 2,
        stance: Stance.long,
        confidence: 0.9,
        day: day,
      );
      expect(v.allowed, isFalse);
    });

    test('a profit goal does not halt, even above 30%', () {
      final rm = RiskManager(config: const RiskConfig(dailyProfitGoalPct: 30));
      final day = DateTime(2026, 6, 10, 14);
      expect(rm.enforceDailyLoss(dayPnlPct: 42, day: day), isFalse);
      expect(rm.isHalted, isFalse);
      expect(dailyProfitGoalReached(dayPnlPct: 42, goalPct: 30), isTrue);
      expect(dailyProfitGoalReached(dayPnlPct: 29.9, goalPct: 30), isFalse);
      expect(dailyProfitGoalReached(dayPnlPct: 80, goalPct: 0), isFalse);
    });

    test('profit-point lock does not cap a tighter trail', () {
      expect(
        lockedProfitStop(
          long: true,
          target: 105,
          currentStop: 97,
          targetHit: true,
          allowMore: true,
        ),
        105,
      );
      expect(
        lockedProfitStop(
          long: true,
          target: 105,
          currentStop: 106,
          targetHit: true,
          allowMore: true,
        ),
        isNull,
      );
      expect(
        lockedProfitStop(
          long: false,
          target: 95,
          currentStop: 103,
          targetHit: true,
          allowMore: true,
        ),
        95,
      );
      expect(
        lockedProfitStop(
          long: true,
          target: 105,
          currentStop: 97,
          targetHit: true,
          allowMore: false,
        ),
        isNull,
      );
    });

    test('saved settings pick up the 30% goal default', () {
      final back = RiskConfig.fromJson(const <String, dynamic>{});
      expect(back.dailyProfitGoalPct, 30);
      expect(back.letWinnersRun, isFalse);
      expect(back.maxSpreadOfTarget, 0.25);
      expect(back.maxDailyLossPct, 2);
      final kept = back.copyWith(maxDailyLossPct: 4);
      expect(kept.dailyProfitGoalPct, 30);
      expect(kept.letWinnersRun, isFalse);
    });

    test('re-arms on a new day', () {
      final rm = RiskManager(config: const RiskConfig(maxDailyLossPct: 2));
      final day1 = DateTime(2026, 6, 10, 15);
      expect(rm.enforceDailyLoss(dayPnlPct: -5, day: day1), isTrue);
      final day2 = DateTime(2026, 6, 11, 10);
      rm.enforceDailyLoss(dayPnlPct: 0, day: day2);
      expect(rm.isHalted, isFalse);
    });
  });
}
