import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/liquidity.dart';

List<Candle> _bars(int n, {required double price, required double volume}) {
  final start = DateTime(2026, 9, 21, 9, 30);
  return <Candle>[
    for (var i = 0; i < n; i++)
      Candle(
        symbol: 'X',
        time: start.add(Duration(minutes: 5 * i)),
        open: price,
        high: price,
        low: price,
        close: price,
        volume: volume,
      ),
  ];
}

void main() {
  test('a session of 5-minute bars is 78 bars', () {
    expect(barsPerSession(BarInterval.fiveMin), 78);
    expect(barsPerSession(BarInterval.oneDay), 1);
  });

  test('session dollar volume uses the latest session of bars', () {
    // 78 bars × $4 × 5,000 shares = $1.56M.
    final bars = [
      ..._bars(50, price: 4, volume: 1),
      ..._bars(78, price: 4, volume: 5000),
    ];
    expect(
      sessionDollarVolume(bars, BarInterval.fiveMin),
      closeTo(1560000, 1e-6),
    );
    expect(sessionDollarVolume(const <Candle>[], BarInterval.fiveMin), isNull);
  });

  group('liquiditySkipReason', () {
    test('sub-dollar shares are skipped', () {
      final why = liquiditySkipReason(
        price: 0.80,
        sessionDollarVolume: 5e7,
        sourceId: 'yahoo',
        minSharePrice: 1,
        minDollarVolume: 1e6,
      );
      expect(why, contains('under the \$1.00 floor'));
    });

    test('thin names are skipped and liquid ones pass', () {
      expect(
        liquiditySkipReason(
          price: 4,
          sessionDollarVolume: 400000,
          sourceId: 'yahoo',
          minSharePrice: 1,
          minDollarVolume: 1e6,
        ),
        contains('thinly traded'),
      );
      expect(
        liquiditySkipReason(
          price: 4,
          sessionDollarVolume: 2e6,
          sourceId: 'yahoo',
          minSharePrice: 1,
          minDollarVolume: 1e6,
        ),
        isNull,
      );
    });

    test('the IEX-only feed is held to its share of the market', () {
      // $30k on IEX ≈ $1.5M market-wide at a 2% share.
      expect(
        liquiditySkipReason(
          price: 4,
          sessionDollarVolume: 30000,
          sourceId: 'alpaca',
          minSharePrice: 1,
          minDollarVolume: 1e6,
        ),
        isNull,
      );
      expect(
        liquiditySkipReason(
          price: 4,
          sessionDollarVolume: 10000,
          sourceId: 'alpaca',
          minSharePrice: 1,
          minDollarVolume: 1e6,
        ),
        contains('IEX'),
      );
    });

    test('zero floors turn the filter off', () {
      expect(
        liquiditySkipReason(
          price: 0.5,
          sessionDollarVolume: null,
          sourceId: 'yahoo',
          minSharePrice: 0,
          minDollarVolume: 0,
        ),
        isNull,
      );
    });
  });
}
