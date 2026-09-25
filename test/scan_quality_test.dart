import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/engine/scan_quality.dart';

void main() {
  test('demo feeds are not treated as a live tape', () {
    expect(isDemoSource('synthetic'), isTrue);
    expect(isDemoSource('bundled'), isTrue);
    expect(isDemoSource('yahoo'), isFalse);
    expect(isDemoSource('alpaca'), isFalse);
    expect(isDemoSource(''), isFalse);
  });

  test('a bar older than three intervals is stale only while the session is live', () {
    final now = DateTime.utc(2026, 6, 10, 15);
    final fresh = now.subtract(const Duration(minutes: 10));
    final old = now.subtract(const Duration(minutes: 20));
    const interval = Duration(minutes: 5);
    expect(
      barIsStale(
        lastBarAt: fresh,
        now: now,
        interval: interval,
        sessionExpectsFreshBars: true,
      ),
      isFalse,
    );
    expect(
      barIsStale(
        lastBarAt: old,
        now: now,
        interval: interval,
        sessionExpectsFreshBars: true,
      ),
      isTrue,
    );
    expect(
      barIsStale(
        lastBarAt: old,
        now: now,
        interval: interval,
        sessionExpectsFreshBars: false,
      ),
      isFalse,
    );
  });
}
