/// Pattern Day Trader (PDT) awareness — US margin-account rule: 4+ round-trip
/// day trades within 5 business days triggers restrictions unless equity ≥ $25k.
///
/// Warnings only: this never blocks trading by itself; the broker enforces.
library;

class PdtSnapshot {
  const PdtSnapshot({
    required this.dayTradeCount,
    required this.isRestricted,
    required this.isNearLimit,
    required this.source,
    required this.note,
  });

  /// Round-trip day trades counted in the rolling window.
  final int dayTradeCount;

  /// At/over the 4-trade limit without $25k.
  final bool isRestricted;

  /// One away from the limit (3 trades).
  final bool isNearLimit;

  /// `broker` when the account reports it (live), `estimated` for paper fills.
  final String source;

  final String note;

  static const int limit = 4;
  static const double equityRequirement = 25000;
}

/// Business-day helper (weekends only — holidays are close enough for a
/// warning banner; brokers enforce the exact rule).
bool isBusinessDay(DateTime d) =>
    d.weekday != DateTime.saturday && d.weekday != DateTime.sunday;

/// Start of the rolling 5-business-day window containing [now].
DateTime windowStart(DateTime now) {
  var day = DateTime(now.year, now.month, now.day);
  // The window includes today (when it's a business day) plus prior ones.
  var counted = isBusinessDay(day) ? 1 : 0;
  while (counted < 5) {
    day = day.subtract(const Duration(days: 1));
    if (isBusinessDay(day)) counted++;
  }
  return day;
}

/// Estimate paper day trades from fill pairs: a symbol-day containing both a
/// buy and a sell counts as one round trip (conservative — undercounts
/// multi-flips, which is fine for a warning).
PdtSnapshot estimatePaperPdt({
  required List<({String symbol, DateTime time, bool isBuy})> fills,
  required double equity,
  required DateTime now,
}) {
  final start = windowStart(now);
  final days = <String, Set<String>>{}; // dayKey -> symbols with both sides
  final sides = <String, Map<String, Set<String>>>{}; // dayKey -> symbol -> sides
  for (final f in fills) {
    if (f.time.isBefore(start)) continue;
    final dayKey =
        '${f.time.year}-${f.time.month.toString().padLeft(2, '0')}-${f.time.day.toString().padLeft(2, '0')}';
    final perSymbol = sides.putIfAbsent(dayKey, () => <String, Set<String>>{});
    final set = perSymbol.putIfAbsent(f.symbol, () => <String>{});
    set.add(f.isBuy ? 'B' : 'S');
    if (set.contains('B') && set.contains('S')) {
      days.putIfAbsent(dayKey, () => <String>{}).add(f.symbol);
    }
  }
  var count = 0;
  for (final symbols in days.values) {
    count += symbols.length;
  }
  return _snapshot(count, equity, source: 'estimated');
}

/// Account-reported count (live Alpaca).
PdtSnapshot reportedPdt({required int dayTradeCount, required double equity}) =>
    _snapshot(dayTradeCount, equity, source: 'broker');

PdtSnapshot _snapshot(int count, double equity, {required String source}) {
  final exempt = equity >= PdtSnapshot.equityRequirement;
  final restricted = !exempt && count >= PdtSnapshot.limit;
  final near = !exempt && count == PdtSnapshot.limit - 1;
  String note;
  if (restricted) {
    note = 'PDT limit reached ($count day trades) — new trades may be blocked '
        'until equity ≥ \$25k or the window rolls.';
  } else if (near) {
    note = '$count day trades in the window — 1 more triggers the PDT rule '
        '(needs \$25k to be exempt).';
  } else {
    note = '$count day trades in the rolling window';
  }
  return PdtSnapshot(
    dayTradeCount: count,
    isRestricted: restricted,
    isNearLimit: near,
    source: source,
    note: note,
  );
}
