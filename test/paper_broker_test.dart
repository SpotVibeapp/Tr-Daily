import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/broker/paper_broker.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/cost_gate.dart';

void main() {
  group('PaperBroker', () {
    test('buy fills at market, position marked to market', () async {
      final pb = PaperBroker(startingCash: 10000);
      pb.setPrice('AAPL', 100);
      final order = await pb.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 10,
      ));
      expect(order.status, OrderStatus.filled);
      expect(order.filledQty, 10);

      final positions = await pb.getPositions();
      expect(positions, hasLength(1));
      expect(positions.first.symbol, 'AAPL');
      expect(positions.first.qty, 10);

      final acct = await pb.getAccount();
      expect(acct.cash, lessThan(10000));

      // Price rises → positive unrealized PnL.
      pb.setPrice('AAPL', 110);
      final positions2 = await pb.getPositions();
      expect(positions2.first.unrealizedPnl, greaterThan(0));
    });

    test('round trip realizes pnl and removes position', () async {
      final pb = PaperBroker(startingCash: 10000);
      pb.setPrice('AAPL', 100);
      await pb.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 10,
      ));
      pb.setPrice('AAPL', 120);
      await pb.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.sell,
        type: OrderType.market,
        qty: 10,
      ));

      expect(await pb.getPositions(), isEmpty);
      final acct = await pb.getAccount();
      // ~+$200 minus slippage.
      expect(acct.equity, greaterThan(10150));
      expect(acct.equity, lessThan(10210));
      expect(pb.fills, hasLength(2));
      expect(pb.fills.last.realizedPnl, greaterThan(150));
    });

    test('slippage applies against the trader', () async {
      final pb = PaperBroker(startingCash: 10000, slippagePct: 1.0);
      pb.setPrice('AAPL', 100);
      final o = await pb.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 1,
      ));
      expect(o.filledAvgPrice!, greaterThan(100)); // buy pays more
    });

    test('short round trip profits when price falls', () async {
      final pb = PaperBroker(startingCash: 10000, slippagePct: 0);
      pb.setPrice('TSLA', 200);
      await pb.submitOrder(const OrderRequest(
        symbol: 'TSLA',
        side: OrderSide.sell,
        type: OrderType.market,
        qty: 5,
      ));
      var positions = await pb.getPositions();
      expect(positions.first.short, isTrue);
      // Even at 0% slippage a sell pays half a 1¢ tick: 5 × $0.005.
      expect(positions.first.unrealizedPnl, closeTo(-0.025, 0.001));

      pb.setPrice('TSLA', 180);
      positions = await pb.getPositions();
      expect(positions.first.unrealizedPnl, greaterThan(0));

      await pb.submitOrder(const OrderRequest(
        symbol: 'TSLA',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 5,
      ));
      expect(await pb.getPositions(), isEmpty);
      final acct = await pb.getAccount();
      expect(acct.equity, greaterThan(10000));
    });

    test('a cheap stock pays at least half a tick each way', () async {
      final pb = PaperBroker(startingCash: 100);
      pb.setPrice('PLUG', 4);
      final buy = await pb.submitOrder(const OrderRequest(
        symbol: 'PLUG',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 6,
      ));
      // 0.02% of $4 is 0.08¢, less than half of a 1¢ tick.
      expect(buy.filledAvgPrice, closeTo(4.005, 1e-9));
      final sell = await pb.submitOrder(const OrderRequest(
        symbol: 'PLUG',
        side: OrderSide.sell,
        type: OrderType.market,
        qty: 6,
      ));
      expect(sell.filledAvgPrice, closeTo(3.995, 1e-9));
      // A flat round trip loses one tick per share: 6 × $0.01.
      expect((await pb.getAccount()).equity, closeTo(100 - 0.06, 1e-9));
    });

    test('a market order pays the ask and gets the bid when quoted', () async {
      final pb = PaperBroker(startingCash: 1000);
      pb.setPrice('SOFI', 10);
      pb.setQuotes(<String, BidAsk>{
        'sofi': const BidAsk(bid: 9.97, ask: 10.03),
      });
      final buy = await pb.submitOrder(const OrderRequest(
        symbol: 'SOFI',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 10,
      ));
      expect(buy.filledAvgPrice, closeTo(10.03, 1e-9));
      final sell = await pb.submitOrder(const OrderRequest(
        symbol: 'SOFI',
        side: OrderSide.sell,
        type: OrderType.market,
        qty: 10,
      ));
      expect(sell.filledAvgPrice, closeTo(9.97, 1e-9));
    });

    test('a stale quote far from the last price is ignored', () async {
      final pb = PaperBroker(startingCash: 1000);
      pb.setPrice('SOFI', 10);
      pb.setQuotes(<String, BidAsk>{
        'SOFI': const BidAsk(bid: 11.00, ask: 11.02),
      });
      final buy = await pb.submitOrder(const OrderRequest(
        symbol: 'SOFI',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 1,
      ));
      expect(buy.filledAvgPrice, closeTo(10.005, 1e-9));
    });

    test('a marketable limit never fills past its limit', () async {
      final pb = PaperBroker(startingCash: 1000);
      pb.setPrice('SOFI', 10);
      final buy = await pb.submitOrder(const OrderRequest(
        symbol: 'SOFI',
        side: OrderSide.buy,
        type: OrderType.limit,
        qty: 1,
        limitPrice: 10.002,
      ));
      expect(buy.filledAvgPrice, closeTo(10.002, 1e-9));
    });

    test('refuses to fill without a known price', () async {
      final pb = PaperBroker();
      expect(
        () => pb.submitOrder(const OrderRequest(
          symbol: 'UNKNOWN',
          side: OrderSide.buy,
          type: OrderType.market,
          qty: 1,
        )),
        throwsStateError,
      );
    });

    test('toJson/fromJson roundtrip preserves state', () async {
      final pb = PaperBroker(startingCash: 15000);
      pb.setPrice('AAPL', 100);
      await pb.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 7,
      ));
      final restored = PaperBroker.fromJson(pb.toJson());
      expect(restored.cash, pb.cash);
      final pos = await restored.getPositions();
      expect(pos, hasLength(1));
      expect(pos.first.qty, 7);
      expect(restored.fills, hasLength(1));
      expect(restored.lastPrice['AAPL'], 100);
    });

    test('notional orders convert to shares', () async {
      final pb = PaperBroker(startingCash: 5000);
      pb.setPrice('AAPL', 50);
      final o = await pb.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.buy,
        type: OrderType.market,
        notional: 500,
      ));
      expect(o.filledQty, closeTo(10, 0.001));
    });
  });
}
