import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/core/notifications.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/risk/risk_manager.dart';
import 'package:tr_daily/strategy/ensemble.dart';

void main() {
  group('RiskConfig phase-2 fields', () {
    test('defaults enable trailing stop + scale-out', () {
      const c = RiskConfig();
      expect(c.trailingStopAtrMult, 2.0);
      expect(c.trailingActivateAtrMult, 1.0);
      expect(c.scaleOutEnabled, isTrue);
      expect(c.scaleOutAtAtrMult, 1.5);
      expect(c.scaleOutFraction, 0.5);
    });

    test('json roundtrip preserves new fields', () {
      const c = RiskConfig(
        trailingStopAtrMult: 3.5,
        trailingActivateAtrMult: 0.75,
        scaleOutEnabled: false,
        scaleOutAtAtrMult: 2.0,
        scaleOutFraction: 0.3,
      );
      final back = RiskConfig.fromJson(c.toJson());
      expect(back.trailingStopAtrMult, 3.5);
      expect(back.trailingActivateAtrMult, 0.75);
      expect(back.scaleOutEnabled, isFalse);
      expect(back.scaleOutAtAtrMult, 2.0);
      expect(back.scaleOutFraction, 0.3);
    });

    test('copyWith only touches requested fields', () {
      const c = RiskConfig();
      final n = c.copyWith(scaleOutFraction: 0.7);
      expect(n.scaleOutFraction, 0.7);
      expect(n.trailingStopAtrMult, c.trailingStopAtrMult);
      expect(n.maxOpenPositions, c.maxOpenPositions);
    });

    test('trailing disabled with 0', () {
      const c = RiskConfig(trailingStopAtrMult: 0);
      expect(c.trailingStopAtrMult, 0);
    });
  });

  group('AppSettings phase-2 roundtrip', () {
    test('extendedHours + risk + ensemble survive json', () {
      final s = AppSettings()
        ..extendedHours = true
        ..risk = const RiskConfig(scaleOutFraction: 0.4)
        ..ensemble = const EnsembleConfig(enterThreshold: 0.55)
        ..scanIntervalSeconds = 45
        ..fitToBudget = false
        ..budgetShareCeiling = 8
        ..paperStartingCash = 100;
      final back = AppSettings.fromJson(s.toJson());
      expect(back.extendedHours, isTrue);
      expect(back.fitToBudget, isFalse);
      expect(back.budgetShareCeiling, 8);
      expect(back.paperStartingCash, 100);
      expect(back.risk.scaleOutFraction, 0.4);
      expect(back.ensemble.enterThreshold, 0.55);
      expect(back.scanIntervalSeconds, 45);
      expect(back.interval, BarInterval.fiveMin);
    });

    test('defaults intact for fresh settings', () {
      final back = AppSettings.fromJson(<String, dynamic>{});
      expect(back.extendedHours, isFalse);
      expect(back.brokerMode.name, 'paper');
      expect(back.watchlist, isNotEmpty);
      expect(back.risk.maxDailyLossPct, 2.0);
      expect(back.notifications.enabled, isTrue);
      expect(back.fitToBudget, isTrue);
      expect(back.budgetShareCeiling, 5);
    });

    test('notifications survive json roundtrip', () {
      final s = AppSettings()
        ..notifications = const NotificationConfig(
          enabled: true,
          notifyOnFills: false,
          notifyOnStops: true,
          webhookUrl: 'https://discord.com/webhook/test',
        );
      final back = AppSettings.fromJson(s.toJson());
      expect(back.notifications.enabled, isTrue);
      expect(back.notifications.notifyOnFills, isFalse);
      expect(back.notifications.notifyOnStops, isTrue);
      expect(back.notifications.webhookUrl, 'https://discord.com/webhook/test');
    });
  });
}
