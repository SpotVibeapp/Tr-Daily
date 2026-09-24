/// US equity market session logic (Eastern Time with correct DST rules) and
/// holiday handling. Pure Dart — no timezone database needed.
library;

/// Day-of-week helpers use `DateTime` Mon=1 … Sun=7.

/// Day of month of the [n]th (1-based) weekday [weekday] (Mon=1..Sun=7)
/// in the given month.
int nthWeekdayOfMonth(int year, int month, int weekday, int n) {
  final first = DateTime(year, month, 1);
  final firstDow = first.weekday;
  final firstOccurrence = 1 + ((weekday - firstDow + 7) % 7);
  return firstOccurrence + (n - 1) * 7;
}

/// Day of month of the last [weekday] in [month].
int lastWeekdayOfMonth(int year, int month, int weekday) {
  final last = DateTime(year, month + 1, 0); // day 0 of next month = last day
  final dow = last.weekday;
  return last.day - ((dow - weekday + 7) % 7);
}

/// Easter Sunday (Gregorian, Meeus/Jones/Butcher algorithm).
DateTime easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

/// Whether a UTC instant falls in US Eastern Daylight Time (2nd Sun Mar
/// 07:00 UTC → 1st Sun Nov 06:00 UTC).
bool isEasternDaylightTime(DateTime utc) {
  final t = utc.toUtc();
  final y = t.year;
  final dstStart = DateTime.utc(y, 3, nthWeekdayOfMonth(y, 3, 7, 2), 7);
  final dstEnd = DateTime.utc(y, 11, nthWeekdayOfMonth(y, 11, 7, 1), 6);
  return !t.isBefore(dstStart) && t.isBefore(dstEnd);
}

/// Convert any [time] to wall-clock Eastern Time components.
/// Returned DateTime's [year]/[month]/[day]/[hour]/[minute] fields are ET.
DateTime toEastern(DateTime time) {
  final utc = time.toUtc();
  final offset = isEasternDaylightTime(utc) ? -4 : -5;
  return utc.add(Duration(hours: offset));
}

/// Shift an ET wall-clock time (as constructed locally) back to the UTC
/// instant it represents. [et] fields are interpreted as Eastern clock time.
DateTime easternToUtc(DateTime et) {
  // Two-pass fixed point: guess offset from the ET-as-UTC, then correct.
  var utcGuess = DateTime.utc(et.year, et.month, et.day, et.hour, et.minute, et.second);
  var offset = isEasternDaylightTime(utcGuess) ? -4 : -5;
  utcGuess = DateTime.utc(et.year, et.month, et.day, et.hour, et.minute, et.second)
      .subtract(Duration(hours: offset));
  offset = isEasternDaylightTime(utcGuess) ? -4 : -5;
  return DateTime.utc(et.year, et.month, et.day, et.hour, et.minute, et.second)
      .subtract(Duration(hours: offset));
}

/// All NYSE full-day closures for [year], on their observed dates.
List<DateTime> marketHolidays(int year) {
  DateTime observed(DateTime d) {
    if (d.weekday == DateTime.saturday) return d.subtract(const Duration(days: 1));
    if (d.weekday == DateTime.sunday) return d.add(const Duration(days: 1));
    return d;
  }

  return <DateTime>[
    observed(DateTime(year, 1, 1)), // New Year's Day
    DateTime(year, 1, nthWeekdayOfMonth(year, 1, DateTime.monday, 3)), // MLK
    DateTime(year, 2, nthWeekdayOfMonth(year, 2, DateTime.monday, 3)), // Presidents
    easterSunday(year).subtract(const Duration(days: 2)), // Good Friday
    DateTime(year, 5, lastWeekdayOfMonth(year, 5, DateTime.monday)), // Memorial
    observed(DateTime(year, 6, 19)), // Juneteenth
    observed(DateTime(year, 7, 4)), // Independence Day (observed)
    DateTime(year, 9, nthWeekdayOfMonth(year, 9, DateTime.monday, 1)), // Labor
    DateTime(year, 11, nthWeekdayOfMonth(year, 11, DateTime.thursday, 4)), // Thanksgiving
    observed(DateTime(year, 12, 25)), // Christmas
  ];
}

/// True when [day] (ET calendar day) is a market holiday.
bool isMarketHoliday(DateTime day) {
  for (final h in marketHolidays(day.year)) {
    if (h.month == day.month && h.day == day.day) return true;
  }
  return false;
}

/// Early-close day (13:00 ET): Christmas Eve, day after Thanksgiving,
/// July 3 when July 4 is a weekday, Black Friday.
bool isEarlyCloseDay(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  if (d == DateTime(day.year, 12, 24)) return true;
  if (d == DateTime(day.year, 11, nthWeekdayOfMonth(day.year, 11, DateTime.thursday, 4) + 1)) {
    return true;
  }
  if (d == DateTime(day.year, 7, 3) &&
      DateTime(day.year, 7, 4).weekday != DateTime.saturday &&
      DateTime(day.year, 7, 4).weekday != DateTime.sunday) {
    return true;
  }
  if (d == DateTime(day.year, 11, nthWeekdayOfMonth(day.year, 11, DateTime.thursday, 4) + 2)) {
    return true; // Black Friday
  }
  return false;
}

/// Regular session check for [now] (any tz). True during 09:30–16:00 ET on a
/// trading day (13:00 close on early-close days).
bool isMarketOpen(DateTime now) {
  final et = toEastern(now);
  if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) {
    return false;
  }
  final day = DateTime(et.year, et.month, et.day);
  if (isMarketHoliday(day)) return false;
  final minutes = et.hour * 60 + et.minute;
  final close = isEarlyCloseDay(day) ? 13 * 60 : 16 * 60;
  return minutes >= 9 * 60 + 30 && minutes < close;
}

/// Premarket: 04:00–09:30 ET.
bool isPreMarket(DateTime now) {
  final et = toEastern(now);
  if (et.weekday == DateTime.saturday || et.weekday == DateTime.sunday) {
    return false;
  }
  final day = DateTime(et.year, et.month, et.day);
  if (isMarketHoliday(day)) return false;
  final minutes = et.hour * 60 + et.minute;
  return minutes >= 4 * 60 && minutes < 9 * 60 + 30;
}

/// Next regular session open at or after [now].
DateTime nextMarketOpen(DateTime now) {
  var day = toEastern(now);
  for (var i = 0; i < 10; i++) {
    final date = DateTime(day.year, day.month, day.day + i);
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      continue;
    }
    if (isMarketHoliday(date)) continue;
    final candidate = easternToUtc(DateTime(date.year, date.month, date.day, 9, 30));
    if (!candidate.isBefore(now.toUtc())) return candidate.toLocal();
  }
  return now.add(const Duration(days: 1));
}

/// `HH:mm` in ET for display.
String formatEasternTime(DateTime now) {
  final et = toEastern(now);
  final hh = et.hour.toString().padLeft(2, '0');
  final mm = et.minute.toString().padLeft(2, '0');
  return '$hh:$mm ET';
}

/// Session status label for the UI banner.
String sessionLabel(DateTime now) {
  if (isMarketOpen(now)) return 'MARKET OPEN';
  if (isPreMarket(now)) return 'PRE-MARKET';
  final next = nextMarketOpen(now);
  final et = toEastern(next);
  final names = ['', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final hh = et.hour.toString().padLeft(2, '0');
  final mm = et.minute.toString().padLeft(2, '0');
  return 'CLOSED · next ${names[et.weekday]} $hh:$mm ET';
}
