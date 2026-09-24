import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/structure.dart';
import 'package:tr_daily/data/models.dart';

Candle bar(int i, {required double o, required double h, required double l, required double cl}) =>
    Candle(
      symbol: 'T',
      time: DateTime(2026, 1, 5, 9, 30).add(Duration(minutes: i * 5)),
      open: o,
      high: h,
      low: l,
      close: cl,
      volume: 1000,
    );

void main() {
  group('findPivots', () {
    test('detects a swing high only after k confirmations', () {
      // V shape: dip in the middle → swing low at index 3.
      final candles = <Candle>[
        for (var i = 0; i < 15; i++)
          bar(i, o: 100, h: 100 + (i == 3 ? 0 : 5), l: 90 + (i == 3 ? -5 : 0),
              cl: 100),
      ];
      final pivots = findPivots(candles, k: 3);
      final lowPivot = pivots.where((p) => !p.isHigh).firstOrNull;
      expect(lowPivot, isNotNull);
      expect(lowPivot!.index, 3);
      expect(lowPivot.confirmIndex, 6); // known only 3 bars later
      expect(lowPivot.price, candles[3].low);
    });

    test('pivot confirmation prevents lookahead', () {
      final candles = <Candle>[
        for (var i = 0; i < 20; i++)
          bar(i, o: 100, h: 100 + (i == 10 ? 10 : 2), l: 95, cl: 100),
      ];
      final pivots = findPivots(candles, k: 3);
      for (final p in pivots) {
        expect(p.confirmIndex, p.index + 3);
        expect(p.confirmIndex, lessThan(candles.length),
            reason: 'fully-confirmed pivots only in this fixture');
      }
      // Nothing may be confirmed before its index+3.
      final high10 = pivots.where((p) => p.isHigh && p.index == 10).firstOrNull;
      expect(high10, isNotNull);
      expect(high10!.confirmIndex, 13);
    });
  });

  group('buildLevels', () {
    test('clusters repeated touches into stronger levels', () {
      final candles = <Candle>[
        for (var i = 0; i < 40; i++)
          bar(
            i,
            o: 100,
            h: i == 20 ? 110 : 101,
            l: (i == 5 || i == 12 || i == 18) ? 95 : 99,
            cl: i == 20 ? 108 : 100,
          ),
      ];
      final pivots = findPivots(candles, k: 3);
      final levels = buildLevels(
          candles: candles, pivots: pivots, upTo: candles.length - 1);
      expect(levels, isNotEmpty);
      // Support cluster around 95 appears with ≥2 touches.
      final support95 = levels
          .where((l) => l.isSupport && (l.price - 95).abs() < 1.5)
          .firstOrNull;
      expect(support95, isNotNull);
      expect(support95!.touches, greaterThanOrEqualTo(2));
    });
  });

  group('detectPatterns', () {
    test('bullish engulfing', () {
      final candles = [
        bar(0, o: 105, h: 106, l: 100, cl: 101), // red candle
        bar(1, o: 100.5, h: 110, l: 100, cl: 109), // green engulfs it
      ];
      final patterns = detectPatterns(candles, 1);
      expect(patterns.contains(CandlePattern.bullishEngulfing), isTrue);
      expect(patternLean(patterns), greaterThan(0));
    });

    test('shooting star', () {
      final candles = [
        bar(0, o: 100, h: 101, l: 99, cl: 100),
        bar(1, o: 100, h: 108, l: 99.8, cl: 100.4), // long upper wick
      ];
      final patterns = detectPatterns(candles, 1);
      expect(patterns.contains(CandlePattern.shootingStar), isTrue);
      expect(patternLean(patterns), lessThan(0));
    });

    test('inside bar', () {
      final candles = [
        bar(0, o: 100, h: 110, l: 90, cl: 105),
        bar(1, o: 102, h: 108, l: 95, cl: 104),
      ];
      final patterns = detectPatterns(candles, 1);
      expect(patterns.contains(CandlePattern.insideBar), isTrue);
    });
  });

  group('fitTrendline', () {
    test('perfect ascending line has r2 ≈ 1', () {
      final line = fitTrendline([(0, 10), (1, 11), (2, 12), (3, 13)]);
      expect(line, isNotNull);
      expect(line!.ascending, isTrue);
      expect(line.r2, closeTo(1, 1e-9));
      expect(line.valueAt(4), closeTo(14, 1e-9));
    });

    test('needs at least 3 points', () {
      expect(fitTrendline([(0, 1), (1, 2)]), isNull);
    });
  });
}
