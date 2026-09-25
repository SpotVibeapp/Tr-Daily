import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/portfolio_analytics.dart';
import 'package:tr_daily/broker/paper_broker.dart';
import 'package:tr_daily/data/models.dart';

void main() {
  group('PortfolioBreakdown.compute', () {
    test('100% cash when no positions open', () {
      const account = AccountInfo(
        equity: 25000,
        cash: 25000,
        buyingPower: 25000,
        dayTradeCount: 0,
      );
      final b = PortfolioBreakdown.compute(
        account: account,
        positions: const <Position>[],
      );

      expect(b.totalEquity, 25000);
      expect(b.cash, 25000);
      expect(b.cashPct, 100.0);
      expect(b.investedValue, 0.0);
      expect(b.investedPct, 0.0);
      expect(b.longExposure, 0.0);
      expect(b.shortExposure, 0.0);
      expect(b.netExposure, 0.0);
      expect(b.leverage, 0.0);
      expect(b.allocations, isEmpty);
    });

    test('allocations and exposure with mixed long and short positions', () {
      const account = AccountInfo(
        equity: 30000,
        cash: 10000,
        buyingPower: 10000,
        dayTradeCount: 0,
      );
      final positions = <Position>[
        const Position(
          symbol: 'AAPL',
          qty: 50,
          avgEntryPrice: 200,
          currentPrice: 220, // +$1,000 uPnl, mVal: $11,000
          short: false,
        ),
        const Position(
          symbol: 'TSLA',
          qty: 40,
          avgEntryPrice: 250,
          currentPrice: 225, // +$1,000 uPnl for short, mVal: $9,000
          short: true,
        ),
      ];

      final b = PortfolioBreakdown.compute(
        account: account,
        positions: positions,
      );

      expect(b.totalEquity, 30000);
      expect(b.cash, 10000);
      expect(b.cashPct, closeTo(33.33, 0.1));
      expect(b.longExposure, 11000);
      expect(b.shortExposure, 9000);
      expect(b.grossExposure, 20000);
      expect(b.netExposure, 2000); // 11000 - 9000
      expect(b.leverage, closeTo(20000 / 30000, 0.01));
      expect(b.allocations.length, 2);

      // Highest allocation first
      expect(b.allocations[0].symbol, 'AAPL');
      expect(b.allocations[0].portfolioPct, closeTo(11000 / 30000 * 100, 0.1));
      expect(b.allocations[0].unrealizedPnl, 1000.0);
      expect(b.allocations[0].unrealizedPnlPct, 10.0);

      expect(b.allocations[1].symbol, 'TSLA');
      expect(b.allocations[1].isShort, isTrue);
      expect(b.allocations[1].unrealizedPnl, 1000.0);
    });
  });

  group('PortfolioPerformance.fromFills', () {
    test('handles empty fill log', () {
      final perf = PortfolioPerformance.fromFills(const <PaperFill>[]);
      expect(perf.totalClosedTrades, 0);
      expect(perf.winRatePct, 0.0);
      expect(perf.profitFactor, 0.0);
      expect(perf.totalRealizedPnl, 0.0);
      expect(perf.trades, isEmpty);
    });

    test('reconstructs closed round-trips and calculates win rate & metrics', () {
      final t1 = DateTime(2026, 9, 20, 10, 0);
      final t2 = DateTime(2026, 9, 20, 10, 30);
      final t3 = DateTime(2026, 9, 20, 11, 0);
      final t4 = DateTime(2026, 9, 20, 11, 45);

      final fills = <PaperFill>[
        // Trade 1: Long AAPL buy 10 @ $150, sell 10 @ $160 (+100 profit)
        PaperFill(
          id: 'f1',
          symbol: 'AAPL',
          side: OrderSide.buy,
          qty: 10,
          price: 150,
          time: t1,
          realizedPnl: 0,
        ),
        PaperFill(
          id: 'f2',
          symbol: 'AAPL',
          side: OrderSide.sell,
          qty: 10,
          price: 160,
          time: t2,
          realizedPnl: 100,
        ),

        // Trade 2: Long MSFT buy 5 @ $300, sell 5 @ $290 (-50 loss)
        PaperFill(
          id: 'f3',
          symbol: 'MSFT',
          side: OrderSide.buy,
          qty: 5,
          price: 300,
          time: t3,
          realizedPnl: 0,
        ),
        PaperFill(
          id: 'f4',
          symbol: 'MSFT',
          side: OrderSide.sell,
          qty: 5,
          price: 290,
          time: t4,
          realizedPnl: -50,
        ),
      ];

      final perf = PortfolioPerformance.fromFills(fills);

      expect(perf.totalClosedTrades, 2);
      expect(perf.winningTrades, 1);
      expect(perf.losingTrades, 1);
      expect(perf.winRatePct, 50.0);
      expect(perf.totalRealizedPnl, 50.0);
      expect(perf.grossProfit, 100.0);
      expect(perf.grossLoss, 50.0);
      expect(perf.profitFactor, 2.0); // 100 / 50
      expect(perf.avgWin, 100.0);
      expect(perf.avgLoss, 50.0);
      expect(perf.winLossRatio, 2.0);
      expect(perf.largestWin, 100.0);
      expect(perf.largestLoss, -50.0);

      expect(perf.trades.length, 2);
      final aaplTrade = perf.trades.firstWhere((t) => t.symbol == 'AAPL');
      expect(aaplTrade.isWin, isTrue);
      expect(aaplTrade.entryPrice, 150);
      expect(aaplTrade.exitPrice, 160);
      expect(aaplTrade.holdDuration, const Duration(minutes: 30));

      final msftTrade = perf.trades.firstWhere((t) => t.symbol == 'MSFT');
      expect(msftTrade.isLoss, isTrue);
      expect(msftTrade.entryPrice, 300);
      expect(msftTrade.exitPrice, 290);
      expect(msftTrade.holdDuration, const Duration(minutes: 45));
    });

    test('newest-first input (how the trade log is kept) pairs the same', () {
      final buy = PaperFill(
        id: 'b',
        symbol: 'PLUG',
        side: OrderSide.buy,
        qty: 6,
        price: 4.00,
        time: DateTime(2026, 9, 20, 10, 0),
        realizedPnl: 0,
      );
      final sell = PaperFill(
        id: 's',
        symbol: 'PLUG',
        side: OrderSide.sell,
        qty: 6,
        price: 4.10,
        time: DateTime(2026, 9, 20, 10, 20),
        realizedPnl: 0.60,
      );
      final perf = PortfolioPerformance.fromFills(<PaperFill>[sell, buy]);
      final t = perf.trades.single;
      expect(t.side, OrderSide.buy);
      expect(t.entryPrice, 4.00);
      expect(t.exitPrice, 4.10);
      expect(t.holdDuration, const Duration(minutes: 20));
      expect(t.realizedPnl, closeTo(0.60, 1e-9));
    });
  });
}
