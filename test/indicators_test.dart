import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/indicators.dart';
import 'package:tr_daily/data/models.dart';

Candle c(int i, double o, double h, double l, double cl) => Candle(
      symbol: 'T',
      time: DateTime(2026, 1, 1).add(Duration(minutes: i)),
      open: o,
      high: h,
      low: l,
      close: cl,
      volume: 1000,
    );

void main() {
  group('sma', () {
    test('known values with warm-up nulls', () {
      final out = sma([1, 2, 3, 4, 5], 3);
      expect(out[0], isNull);
      expect(out[1], isNull);
      expect(out[2], closeTo(2, 1e-9));
      expect(out[3], closeTo(3, 1e-9));
      expect(out[4], closeTo(4, 1e-9));
    });
  });

  group('ema', () {
    test('seeds with SMA and tracks upward series', () {
      final out = ema([1, 2, 3, 4, 5, 6], 3);
      expect(out[0], isNull);
      expect(out[1], isNull);
      expect(out[2], closeTo(2, 1e-9)); // SMA(1,2,3)
      // EMA with k=0.5: 4 → 3, 5 → 4, 6 → 5
      expect(out[3], closeTo(3, 1e-9));
      expect(out[5], closeTo(5, 1e-9));
    });

    test('is causal — future changes do not alter past values', () {
      final a = ema([1, 2, 3, 4, 5, 6, 7, 8], 3);
      final b = ema([1, 2, 3, 4, 5, 6, 7, 999], 3);
      for (var i = 0; i < 7; i++) {
        expect(a[i], b[i], reason: 'index $i must not depend on future');
      }
    });
  });

  group('rsi', () {
    test('monotonic gains → 100', () {
      final closes = [for (var i = 0; i < 30; i++) 100.0 + i];
      final out = rsi(closes, 14);
      expect(out[29], closeTo(100, 1e-6));
    });

    test('monotonic losses → 0', () {
      final closes = [for (var i = 0; i < 30; i++) 100.0 - i];
      final out = rsi(closes, 14);
      expect(out[29], closeTo(0, 1e-6));
    });

    test('stays within 0..100 on noisy data', () {
      final closes = <double>[];
      var p = 100.0;
      for (var i = 0; i < 60; i++) {
        p += (i % 3 - 1) * 1.7;
        closes.add(p);
      }
      final out = rsi(closes, 14);
      for (final v in out.skip(14)) {
        expect(v, greaterThanOrEqualTo(0));
        expect(v, lessThanOrEqualTo(100));
      }
    });
  });

  group('macd', () {
    test('histogram = macd - signal where defined', () {
      final closes = [for (var i = 0; i < 80; i++) 50.0 + (i % 11)];
      final m = macd(closes);
      for (var i = 0; i < closes.length; i++) {
        if (m.macd[i] != null && m.signal[i] != null) {
          expect(m.histogram[i]!,
              closeTo(m.macd[i]! - m.signal[i]!, 1e-9));
        }
      }
    });
  });

  group('bollinger', () {
    test('bands hug a constant series', () {
      final closes = List<double>.filled(40, 100);
      final b = bollinger(closes);
      expect(b.upper[39], closeTo(100, 1e-9));
      expect(b.lower[39], closeTo(100, 1e-9));
      expect(b.percentB[39], isNotNull);
    });

    test('upper > middle > lower on varying data', () {
      final closes = [for (var i = 0; i < 40; i++) 100.0 + (i % 7) * 2];
      final b = bollinger(closes);
      expect(b.upper[39]!, greaterThan(b.middle[39]!));
      expect(b.middle[39]!, greaterThan(b.lower[39]!));
    });
  });

  group('atr', () {
    test('positive and finite on real-ish candles', () {
      final candles = <Candle>[];
      var p = 50.0;
      for (var i = 0; i < 40; i++) {
        p += (i.isEven ? 1.2 : -0.8);
        candles.add(c(i, p - 0.5, p + 1.5, p - 1.4, p));
      }
      final out = atr(candles, 14);
      expect(out[39], isNotNull);
      expect(out[39]!, greaterThan(0));
      expect(out[39]!.isFinite, isTrue);
    });
  });

  group('session vwap', () {
    test('resets each calendar day', () {
      final candles = [
        Candle(
            symbol: 'T',
            time: DateTime(2026, 3, 2, 9, 30),
            open: 10,
            high: 11,
            low: 9,
            close: 10,
            volume: 100),
        Candle(
            symbol: 'T',
            time: DateTime(2026, 3, 2, 16, 0),
            open: 10,
            high: 12,
            low: 10,
            close: 12,
            volume: 100),
        Candle(
            symbol: 'T',
            time: DateTime(2026, 3, 3, 9, 30),
            open: 8,
            high: 9,
            low: 7,
            close: 8,
            volume: 100),
      ];
      final v = sessionVwap(candles);
      expect(v[0], isNotNull);
      expect(v[1], greaterThan(v[0]!)); // day 1 accumulates upward
      expect(v[2]!, lessThan(v[0]!)); // day 2 resets near its own typical
    });
  });

  group('donchian', () {
    test('excludes current bar (breakout reference)', () {
      final candles = <Candle>[
        for (var i = 0; i < 30; i++) c(i, 100, 100 + i, 99, 100),
      ];
      // Current bar has the highest high (i=29); upper must reflect i<29.
      final d = donchian(candles, period: 20);
      expect(d.upper[29]!, lessThan(candles[29].high));
      expect(d.upper[29]!, greaterThan(100));
    });
  });

  group('linreg slope', () {
    test('positive for rising series, negative for falling', () {
      final up = linregSlope([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 5);
      expect(up.last!, greaterThan(0));
      final down = linregSlope([10, 9, 8, 7, 6, 5, 4, 3, 2, 1], 5);
      expect(down.last!, lessThan(0));
    });
  });
}
