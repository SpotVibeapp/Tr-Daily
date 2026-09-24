import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/broker/paper_broker.dart';
import 'package:tr_daily/data/models.dart';

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
      expect(positions.first.unrealizedPnl, closeTo(0, 0.01));

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
