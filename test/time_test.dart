import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/core/time.dart';

void main() {
  group('DST math', () {
    test('EDT window 2026: Mar 8 → Nov 1', () {
      // Before DST (EST, UTC-5): 16:00 UTC = 11:00 ET.
      final feb = DateTime.utc(2026, 2, 10, 16);
      expect(isEasternDaylightTime(feb), isFalse);
      expect(toEastern(feb).hour, 11);

      // During DST (EDT, UTC-4): 16:00 UTC = 12:00 ET.
      final jul = DateTime.utc(2026, 7, 10, 16);
      expect(isEasternDaylightTime(jul), isTrue);
      expect(toEastern(jul).hour, 12);
    });

    test('easternToUtc round trips', () {
      final et = DateTime(2026, 7, 4, 9, 30); // interpreted as ET wall clock
      final utc = easternToUtc(et);
      final back = toEastern(utc);
      expect(back.hour, 9);
      expect(back.minute, 30);
      expect(utc.isUtc, isTrue);
    });
  });

  group('market hours', () {
    test('open during regular session', () {
      // Wed 2026-06-10 10:30 ET = 14:30 UTC (EDT).
      final open = DateTime.utc(2026, 6, 10, 14, 30);
      expect(isMarketOpen(open), isTrue);
      expect(isMarketOpen(open.add(const Duration(hours: 6))), isFalse); // 16:30
      expect(isMarketOpen(open.subtract(const Duration(hours: 6))), isFalse); // 4:30
    });

    test('flatten window is the last 15 minutes before 16:00 ET', () {
      // Wed 2026-06-10 15:50 ET = 19:50 UTC (EDT). 10 minutes left.
      final late = DateTime.utc(2026, 6, 10, 19, 50);
      expect(minutesUntilClose(late), 10);
      expect(inFlattenWindow(late), isTrue);
      // 15:00 ET = 19:00 UTC. 60 minutes left.
      final mid = DateTime.utc(2026, 6, 10, 19, 0);
      expect(inFlattenWindow(mid), isFalse);
      // 16:05 ET is after the close, not a flatten window.
      final after = DateTime.utc(2026, 6, 10, 20, 5);
      expect(inFlattenWindow(after), isFalse);
    });

    test('closed on weekends', () {
      expect(isMarketOpen(DateTime.utc(2026, 6, 13, 15)), isFalse); // Sat
      expect(isMarketOpen(DateTime.utc(2026, 6, 14, 15)), isFalse); // Sun
    });

    test('closed at 10:00 ET on Good Friday 2026-04-03', () {
      // 10:00 ET (EDT) = 14:00 UTC.
      expect(isMarketOpen(DateTime.utc(2026, 4, 3, 14)), isFalse);
    });

    test('closed on Independence Day observed (Fri Jul 3, 2026)', () {
      expect(isMarketOpen(DateTime.utc(2026, 7, 3, 14)), isFalse);
      expect(isMarketHoliday(DateTime(2026, 7, 3)), isTrue);
      // Jul 4 2026 is a Saturday → observed Friday.
      expect(
        marketHolidays(2026).where((h) => h.month == 7 && h.day == 3),
        isNotEmpty,
      );
    });

    test('open on a normal Wednesday mid-session', () {
      expect(isMarketOpen(DateTime.utc(2026, 6, 10, 15)), isTrue);
    });

    test('premarket recognized', () {
      // 07:00 ET = 11:00 UTC (EDT).
      expect(isPreMarket(DateTime.utc(2026, 6, 10, 11)), isTrue);
      expect(isPreMarket(DateTime.utc(2026, 6, 10, 15)), isFalse); // open
    });
  });

  group('holidays & early closes', () {
    test('Thanksgiving 2026 = Nov 26', () {
      expect(isMarketHoliday(DateTime(2026, 11, 26)), isTrue);
      expect(
        marketHolidays(2026).where((h) => h.month == 11 && h.day == 26),
        isNotEmpty,
      );
    });

    test('early close day after Thanksgiving (Nov 27, 2026)', () {
      expect(isEarlyCloseDay(DateTime(2026, 11, 27)), isTrue);
      // 16:00 UTC = 12:00 ET → open; 18:30 UTC = 13:30 ET → past 13:00 close.
      expect(isMarketOpen(DateTime.utc(2026, 11, 27, 16, 0)), isTrue);
      expect(isMarketOpen(DateTime.utc(2026, 11, 27, 18, 30)), isFalse);
    });

    test('Christmas 2026 (Friday) closed', () {
      expect(isMarketHoliday(DateTime(2026, 12, 25)), isTrue);
    });

    test('MLK 2026 = Jan 19 (3rd Monday)', () {
      expect(isMarketHoliday(DateTime(2026, 1, 19)), isTrue);
    });
  });

  group('next session', () {
    test('next open from Friday evening → Monday', () {
      final friday = DateTime(2026, 6, 12, 17, 0); // treated as local=ET-ish
      final next = nextMarketOpen(DateTime.utc(2026, 6, 12, 21, 0)); // 17:00 ET Fri
      expect(next.isAfter(friday.toUtc()), isTrue);
      final et = toEastern(next);
      expect(et.weekday, DateTime.monday);
      expect(et.hour, 9);
      expect(et.minute, 30);
    });
  });

  group('sessionLabel', () {
    test('reports open and closed states', () {
      expect(sessionLabel(DateTime.utc(2026, 6, 10, 15)), 'MARKET OPEN');
      final closed = sessionLabel(DateTime.utc(2026, 6, 10, 20));
      expect(closed, contains('CLOSED'));
      expect(closed, contains('next'));
    });
  });
}
