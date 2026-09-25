import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/engine/cost_gate.dart';
import 'package:tr_daily/engine/fill_model.dart';

void main() {
  group('sideCost', () {
    test('a cheap stock pays at least half a cent', () {
      // 0.02% of $4 is $0.0008, under half a tick.
      expect(sideCost(4.00, 0.02), closeTo(0.005, 1e-12));
    });

    test('an expensive stock pays the percentage', () {
      expect(sideCost(500, 0.02), closeTo(0.10, 1e-12));
    });

    test('sub-dollar ticks are 0.01¢', () {
      expect(tickSize(0.50), 0.0001);
      expect(sideCost(0.50, 0.0), closeTo(0.00005, 1e-12));
    });
  });

  group('simulatedFill', () {
    test('buys pay the ask and sells get the bid', () {
      const q = BidAsk(bid: 3.99, ask: 4.01);
      expect(
        simulatedFill(last: 4.00, isBuy: true, slippagePct: 0.02, quote: q),
        4.01,
      );
      expect(
        simulatedFill(last: 4.00, isBuy: false, slippagePct: 0.02, quote: q),
        3.99,
      );
    });

    test('a tight quote never beats the cost floor', () {
      const q = BidAsk(bid: 4.00, ask: 4.00);
      expect(
        simulatedFill(last: 4.00, isBuy: true, slippagePct: 0.02, quote: q),
        closeTo(4.005, 1e-12),
      );
    });

    test('a quote far from the last trade is ignored', () {
      const q = BidAsk(bid: 4.50, ask: 4.60);
      expect(
        simulatedFill(last: 4.00, isBuy: true, slippagePct: 0.02, quote: q),
        closeTo(4.005, 1e-12),
      );
    });

    test('no quote falls back to last ± cost', () {
      expect(
        simulatedFill(last: 4.00, isBuy: false, slippagePct: 0.02),
        closeTo(3.995, 1e-12),
      );
    });
  });

  group('fillCostNote', () {
    test('reports what a worse fill cost', () {
      final note = fillCostNote(
        symbol: 'PLUG',
        isBuy: true,
        qty: 6,
        expected: 4.00,
        filled: 4.01,
      );
      expect(note, contains('BUY 6 PLUG'));
      expect(note, contains('\$4.01'));
      expect(note, contains('cost \$0.06'));
    });

    test('a better fill reads as saved', () {
      final note = fillCostNote(
        symbol: 'PLUG',
        isBuy: false,
        qty: 6,
        expected: 4.00,
        filled: 4.01,
      );
      expect(note, contains('saved \$0.06'));
    });
  });
}
