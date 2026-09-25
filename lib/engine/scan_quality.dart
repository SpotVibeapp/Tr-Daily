/// Demo feeds must not be traded as if they were the market.
bool isDemoSource(String sourceId) {
  final id = sourceId.toLowerCase();
  return id == 'synthetic' || id == 'bundled';
}

/// True when a session that should have fresh bars is still looking at an old one.
/// [maxAge] is how long the last bar may be before a new entry waits.
bool barIsStale({
  required DateTime? lastBarAt,
  required DateTime now,
  required Duration interval,
  required bool sessionExpectsFreshBars,
  int intervalsAllowed = 3,
}) {
  if (!sessionExpectsFreshBars || lastBarAt == null) return false;
  if (interval.inSeconds <= 0) return false;
  return now.difference(lastBarAt) > interval * intervalsAllowed;
}
