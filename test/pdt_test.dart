import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/core/pdt.dart';

void main() {
  group('window & business days', () {
    test('windowStart spans 5 business days backwards', () {
      // Wed 2026-06-10 → window starts Thu 2026-06-04 (skip weekend).
      final start = windowStart(DateTime(2026, 6, 10, 15));
      expect(start.weekday, DateTime.thursday);
      expect(start.day, 4);
    });

    test('weekend day counts are skipped', () {
      // From Monday 2026-06-08 the window is {8,5,4,3,2} → starts Tue Jun 2.
      final start = windowStart(DateTime(2026, 6, 8, 12));
      expect(start.month, 6);
      expect(start.day, 2);
      expect(start.weekday, DateTime.tuesday);
    });

    test('isBusinessDay', () {
      expect(isBusinessDay(DateTime(2026, 6, 10)), isTrue);
      expect(isBusinessDay(DateTime(2026, 6, 13)), isFalse);
      expect(isBusinessDay(DateTime(2026, 6, 14)), isFalse);
    });
  });

  group('estimatePaperPdt', () {
    List<({String symbol, DateTime time, bool isBuy})> mk(List<List<Object>> rows) => [
          for (final r in rows)
            (symbol: r[0] as String, time: r[1] as DateTime, isBuy: r[2] as bool),
        ];

    test('same-day round trip counts as one day trade', () {
      final snap = estimatePaperPdt(
        fills: mk([
          ['AAPL', DateTime(2026, 6, 10, 10), true],
          ['AAPL', DateTime(2026, 6, 10, 15), false],
        ]),
        equity: 10000,
        now: DateTime(2026, 6, 10, 16),
      );
      expect(snap.dayTradeCount, 1);
      expect(snap.isNearLimit, isFalse);
      expect(snap.source, 'estimated');
    });

    test('overnight position is NOT a day trade', () {
      final snap = estimatePaperPdt(
        fills: mk([
          ['AAPL', DateTime(2026, 6, 10, 10), true],
          ['AAPL', DateTime(2026, 6, 11, 15), false],
        ]),
        equity: 10000,
        now: DateTime(2026, 6, 11, 16),
      );
      expect(snap.dayTradeCount, 0);
    });

    test('approaching limit flags near-limit at 3', () {
      // Business days only: Thu 4th, Fri 5th, Mon 8th of June 2026.
      final fills = <({String symbol, DateTime time, bool isBuy})>[];
      for (final d in [4, 5, 8]) {
        fills.add((symbol: 'S$d', time: DateTime(2026, 6, d, 10), isBuy: true));
        fills.add((symbol: 'S$d', time: DateTime(2026, 6, d, 15), isBuy: false));
      }
      final snap = estimatePaperPdt(
        fills: fills,
        equity: 10000,
        now: DateTime(2026, 6, 8, 16),
      );
      expect(snap.dayTradeCount, 3);
      expect(snap.isNearLimit, isTrue);
      expect(snap.isRestricted, isFalse);
      expect(snap.note, contains('1 more'));
    });

    test('restricted at 4 without \$25k, exempt with \$25k', () {
      // Window {9,8,5,4,3} June 2026 → four round trips on business days.
      final fills = <({String symbol, DateTime time, bool isBuy})>[];
      for (final d in [3, 4, 5, 8]) {
        fills.add((symbol: 'S$d', time: DateTime(2026, 6, d, 10), isBuy: true));
        fills.add((symbol: 'S$d', time: DateTime(2026, 6, d, 15), isBuy: false));
      }
      final poor = estimatePaperPdt(
          fills: fills, equity: 10000, now: DateTime(2026, 6, 9, 16));
      expect(poor.dayTradeCount, 4);
      expect(poor.isRestricted, isTrue);

      final rich = estimatePaperPdt(
          fills: fills, equity: 40000, now: DateTime(2026, 6, 9, 16));
      expect(rich.isRestricted, isFalse);
      expect(rich.isNearLimit, isFalse);
      expect(rich.note, contains('window'));
    });

    test('fills outside the rolling window are ignored', () {
      final snap = estimatePaperPdt(
        fills: mk([
          ['OLD', DateTime(2026, 5, 1, 10), true],
          ['OLD', DateTime(2026, 5, 1, 15), false],
        ]),
        equity: 10000,
        now: DateTime(2026, 6, 10, 16),
      );
      expect(snap.dayTradeCount, 0);
    });
  });

  group('reportedPdt', () {
    test('broker counts flow through', () {
      final snap = reportedPdt(dayTradeCount: 2, equity: 8000);
      expect(snap.dayTradeCount, 2);
      expect(snap.isNearLimit, isFalse);
      final snap3 = reportedPdt(dayTradeCount: 3, equity: 8000);
      expect(snap3.isNearLimit, isTrue);
      final big = reportedPdt(dayTradeCount: 6, equity: 30000);
      expect(big.isRestricted, isFalse);
    });
  });
}
