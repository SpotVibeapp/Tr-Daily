import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/cost_gate.dart';

void main() {
  const tight = BidAsk(bid: 4.00, ask: 4.01);
  const wide = BidAsk(bid: 4.00, ask: 4.04);

  group('spread gate', () {
    test('skips when the spread is a large part of the profit point', () {
      final reason = spreadSkipReason(
        quote: wide,
        price: 4.02,
        targetPrice: 4.08,
        maxSpreadOfTarget: 0.25,
      );
      expect(reason, contains('spread'));
      expect(reason, contains('67%'));
    });

    test('allows a spread that is a small part of the profit point', () {
      expect(
        spreadSkipReason(
          quote: tight,
          price: 4.00,
          targetPrice: 4.08,
          maxSpreadOfTarget: 0.25,
        ),
        isNull,
      );
    });

    test('does not guess when the quote is missing or crossed', () {
      expect(
        spreadSkipReason(
          quote: null,
          price: 4,
          targetPrice: 4.2,
          maxSpreadOfTarget: 0.25,
        ),
        contains('not readable'),
      );
      expect(BidAsk.tryMake(4.05, 4.00), isNull);
      expect(BidAsk.tryMake(0, 4), isNull);
    });

    test('zero limit turns the gate off', () {
      expect(
        spreadSkipReason(
          quote: null,
          price: 4,
          targetPrice: 4.02,
          maxSpreadOfTarget: 0,
        ),
        isNull,
      );
    });
  });

  group('session orders', () {
    test('regular session is a market order and is not marked extended', () {
      final order = sessionOrder(
        symbol: 'AAPL',
        side: OrderSide.buy,
        qty: 2,
        regularSession: true,
        quote: wide,
        allowOutside: true,
        extendedHours: true,
        takeProfit: 110,
        stopLoss: 95,
      );
      expect(order, isNotNull);
      expect(order!.type, OrderType.market);
      expect(order.extendedHours, isFalse);
      expect(order.limitPrice, isNull);
      expect(order.takeProfit, 110);
      // The stop and target keep working after today's close.
      expect(order.timeInForce, TimeInForce.gtc);
    });

    test('a regular-session order without a stop stays a day order', () {
      final order = sessionOrder(
        symbol: 'AAPL',
        side: OrderSide.sell,
        qty: 2,
        regularSession: true,
        quote: null,
        allowOutside: false,
        extendedHours: false,
      );
      expect(order!.type, OrderType.market);
      expect(order.timeInForce, TimeInForce.day);
    });

    test('outside the regular session a buy is a limit at the ask', () {
      final order = sessionOrder(
        symbol: 'NOK',
        side: OrderSide.buy,
        qty: 10,
        regularSession: false,
        quote: wide,
        allowOutside: true,
        extendedHours: true,
        takeProfit: 5,
        stopLoss: 3,
      );
      expect(order, isNotNull);
      expect(order!.type, OrderType.limit);
      expect(order.limitPrice, 4.04);
      expect(order.extendedHours, isTrue);
      expect(order.takeProfit, isNull);
      expect(order.timeInForce, TimeInForce.day);
    });

    test('outside the regular session a sell is a limit at the bid', () {
      final order = sessionOrder(
        symbol: 'NOK',
        side: OrderSide.sell,
        qty: 10,
        regularSession: false,
        quote: wide,
        allowOutside: true,
        extendedHours: true,
      );
      expect(order!.limitPrice, 4.00);
    });

    test('no quote outside the session does not become a market order', () {
      expect(
        sessionOrder(
          symbol: 'NOK',
          side: OrderSide.buy,
          qty: 1,
          regularSession: false,
          quote: null,
          allowOutside: true,
          extendedHours: true,
        ),
        isNull,
      );
      expect(
        sessionOrder(
          symbol: 'NOK',
          side: OrderSide.sell,
          qty: 1,
          regularSession: false,
          quote: wide,
          allowOutside: false,
          extendedHours: false,
        ),
        isNull,
      );
    });
  });

  test('quote parsers ignore a zero or missing spread', () {
    expect(
      parseYahooQuotes(<String, dynamic>{
        'quoteResponse': <String, dynamic>{
          'result': <Map<String, dynamic>>[
            <String, dynamic>{'symbol': 'aapl', 'bid': 200.1, 'ask': 200.2},
            <String, dynamic>{'symbol': 'NOK', 'bid': 0, 'ask': 0},
          ],
        },
      }).keys,
      <String>['AAPL'],
    );
    expect(
      parseAlpacaQuotes(<String, dynamic>{
        'snapshots': <String, dynamic>{
          'MSFT': <String, dynamic>{
            'latestQuote': <String, dynamic>{'bp': 400.0, 'ap': 400.05},
          },
        },
      })['MSFT']!
          .spread,
      closeTo(0.05, 1e-9),
    );
  });
}
