import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/data/csv_parser.dart';
import 'package:tr_daily/data/models.dart';

void main() {
  group('CsvParser', () {
    test('parses a standard header', () {
      const csv = '''
date,open,high,low,close,volume
2026-01-05,100.0,102.5,99.5,101.25,1000000
2026-01-06,101.25,103.0,100.0,102.5,1200000
''';
      final out = CsvParser.parse(csv, symbol: 'TEST');
      expect(out, hasLength(2));
      expect(out.first.open, 100.0);
      expect(out.last.close, 102.5);
      expect(out.last.volume, 1200000);
      expect(out.first.symbol, 'TEST');
    });

    test('skips comment lines and blank lines', () {
      const csv = '''
# synthetic demo, not real data
time,open,high,low,close,volume

2026-01-05T09:30:00,10,11,9,10.5,500
2026-01-05T09:35:00,10.5,11,10,10.8,600
''';
      final out = CsvParser.parse(csv, symbol: 'X');
      expect(out, hasLength(2));
      expect(out.first.time.hour, 9);
    });

    test('rejects malformed header', () {
      expect(
        () => CsvParser.parse('foo,bar\n1,2', symbol: 'X'),
        throwsFormatException,
      );
    });

    test('skips rows with unparsable numbers', () {
      const csv = '''
date,open,high,low,close
2026-01-05,100,101,99,100
2026-01-06,bad,101,99,100
2026-01-07,101,102,100,101
''';
      expect(CsvParser.parse(csv, symbol: 'X'), hasLength(2));
    });

    test('reads bundled demo files (assets/sample_data)', () {
      final f = File('assets/sample_data/AAPL_demo.csv');
      expect(f.existsSync(), isTrue,
          reason: 'run scripts/gen_sample_data.py if missing');
      final out = CsvParser.parse(f.readAsStringSync(), symbol: 'AAPL');
      expect(out.length, greaterThan(400));
      // OHLC sanity: high ≥ max(open, close), low ≤ min(open, close).
      for (final c in out.take(50)) {
        expect(c.high, greaterThanOrEqualTo(c.open));
        expect(c.high, greaterThanOrEqualTo(c.close));
        expect(c.low, lessThanOrEqualTo(c.open));
        expect(c.low, lessThanOrEqualTo(c.close));
      }
    });
  });

  group('BundledCsvSource-like fallback behavior', () {
    test('lastPrice helper semantics via simple candle list', () {
      // Chart last-price choice = last close (mirrors source contracts).
      final out = CsvParser.parse(
        'date,open,high,low,close\n2026-01-05,1,1,1,42\n',
        symbol: 'Y',
      );
      expect(out.last.close, 42);
    });
  });

  group('models', () {
    test('Position pnl math long & short', () {
      const long = Position(
        symbol: 'A',
        qty: 10,
        avgEntryPrice: 100,
        currentPrice: 110,
      );
      expect(long.unrealizedPnl, closeTo(100, 1e-9));
      expect(long.unrealizedPnlPct, closeTo(10, 1e-9));

      const short = Position(
        symbol: 'A',
        qty: 10,
        avgEntryPrice: 100,
        currentPrice: 90,
        short: true,
      );
      expect(short.unrealizedPnl, closeTo(100, 1e-9));
    });

    test('StrategyTrade pnl honors side', () {
      final long = StrategyTrade(
        symbol: 'A',
        side: Stance.long,
        entryTime: DateTime(2026, 1, 1),
        entryPrice: 100,
        qty: 5,
        exitTime: DateTime(2026, 1, 2),
        exitPrice: 110,
        exitReason: 'test',
      );
      expect(long.grossPnl, closeTo(50, 1e-9));

      final short = StrategyTrade(
        symbol: 'A',
        side: Stance.short,
        entryTime: DateTime(2026, 1, 1),
        entryPrice: 100,
        qty: 5,
        exitTime: DateTime(2026, 1, 2),
        exitPrice: 90,
        exitReason: 'test',
      );
      expect(short.grossPnl, closeTo(50, 1e-9));
    });

    test('OrderStatus.parse handles Alpaca strings', () {
      expect(OrderStatus.parse('filled'), OrderStatus.filled);
      expect(OrderStatus.parse('canceled'), OrderStatus.canceled);
      expect(OrderStatus.parse(null), OrderStatus.unknown);
      expect(OrderStatus.new_.isOpen, isTrue);
      expect(OrderStatus.filled.isOpen, isFalse);
    });
  });
}
