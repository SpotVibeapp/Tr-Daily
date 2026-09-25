import '../broker/paper_broker.dart';
import '../data/models.dart';

/// Single asset holding breakdown within a portfolio.
class AssetAllocation {
  const AssetAllocation({
    required this.symbol,
    required this.shares,
    required this.avgPrice,
    required this.currentPrice,
    required this.marketValue,
    required this.costBasis,
    required this.unrealizedPnl,
    required this.unrealizedPnlPct,
    required this.portfolioPct,
    required this.isShort,
  });

  final String symbol;
  final double shares;
  final double avgPrice;
  final double currentPrice;
  final double marketValue;
  final double costBasis;
  final double unrealizedPnl;
  final double unrealizedPnlPct;

  /// Percentage of total portfolio equity (0 to 100).
  final double portfolioPct;
  final bool isShort;
}

/// Portfolio exposure and capital allocation snapshot.
class PortfolioBreakdown {
  const PortfolioBreakdown({
    required this.totalEquity,
    required this.cash,
    required this.cashPct,
    required this.investedValue,
    required this.investedPct,
    required this.longExposure,
    required this.shortExposure,
    required this.netExposure,
    required this.grossExposure,
    required this.leverage,
    required this.allocations,
  });

  final double totalEquity;
  final double cash;
  final double cashPct;
  final double investedValue;
  final double investedPct;
  final double longExposure;
  final double shortExposure;
  final double netExposure;
  final double grossExposure;
  final double leverage;
  final List<AssetAllocation> allocations;

  /// Calculates breakdown metrics from current account snapshot and open positions.
  factory PortfolioBreakdown.compute({
    required AccountInfo account,
    required List<Position> positions,
  }) {
    var longVal = 0.0;
    var shortVal = 0.0;

    for (final p in positions) {
      final val = (p.qty * p.currentPrice).abs();
      if (p.short) {
        shortVal += val;
      } else {
        longVal += val;
      }
    }

    final gross = longVal + shortVal;
    final net = longVal - shortVal;
    final effectiveEquity = account.equity > 0 ? account.equity : account.cash;
    final denominator = effectiveEquity > 0 ? effectiveEquity : 1.0;

    final cashClamped = account.cash > 0 ? account.cash : 0.0;
    final cashPct = (cashClamped / denominator * 100).clamp(0.0, 100.0);
    final investedPct = (gross / denominator * 100).clamp(0.0, 100.0);
    final leverage = denominator > 0 ? gross / denominator : 0.0;

    final allocations = <AssetAllocation>[];
    for (final p in positions) {
      final val = (p.qty * p.currentPrice).abs();
      final pct = denominator > 0 ? (val / denominator * 100) : 0.0;
      allocations.add(AssetAllocation(
        symbol: p.symbol,
        shares: p.qty,
        avgPrice: p.avgEntryPrice,
        currentPrice: p.currentPrice,
        marketValue: p.marketValue,
        costBasis: p.costBasis,
        unrealizedPnl: p.unrealizedPnl,
        unrealizedPnlPct: p.unrealizedPnlPct,
        portfolioPct: pct,
        isShort: p.short,
      ));
    }

    // Sort highest allocation first.
    allocations.sort((a, b) => b.marketValue.abs().compareTo(a.marketValue.abs()));

    return PortfolioBreakdown(
      totalEquity: account.equity,
      cash: account.cash,
      cashPct: cashPct,
      investedValue: gross,
      investedPct: investedPct,
      longExposure: longVal,
      shortExposure: shortVal,
      netExposure: net,
      grossExposure: gross,
      leverage: leverage,
      allocations: List<AssetAllocation>.unmodifiable(allocations),
    );
  }
}

/// A completed round-trip trade record reconstructed from fills or logs.
class ClosedTradeRecord {
  const ClosedTradeRecord({
    required this.id,
    required this.symbol,
    required this.side,
    required this.qty,
    required this.entryPrice,
    required this.exitPrice,
    required this.entryTime,
    required this.exitTime,
    required this.realizedPnl,
    required this.pnlPct,
    this.exitReason = 'filled',
  });

  final String id;
  final String symbol;
  final OrderSide side; // Entry side
  final double qty;
  final double entryPrice;
  final double exitPrice;
  final DateTime entryTime;
  final DateTime exitTime;
  final double realizedPnl;
  final double pnlPct;
  final String exitReason;

  Duration get holdDuration => exitTime.difference(entryTime);
  bool get isWin => realizedPnl > 0.00001;
  bool get isLoss => realizedPnl < -0.00001;
}

/// Summary performance statistics across all closed trades.
class PortfolioPerformance {
  const PortfolioPerformance({
    required this.totalClosedTrades,
    required this.winningTrades,
    required this.losingTrades,
    required this.breakEvenTrades,
    required this.winRatePct,
    required this.totalRealizedPnl,
    required this.grossProfit,
    required this.grossLoss,
    required this.profitFactor,
    required this.avgWin,
    required this.avgLoss,
    required this.winLossRatio,
    required this.largestWin,
    required this.largestLoss,
    required this.trades,
  });

  final int totalClosedTrades;
  final int winningTrades;
  final int losingTrades;
  final int breakEvenTrades;
  final double winRatePct;
  final double totalRealizedPnl;
  final double grossProfit;
  final double grossLoss;
  final double profitFactor;
  final double avgWin;
  final double avgLoss;
  final double winLossRatio;
  final double largestWin;
  final double largestLoss;
  final List<ClosedTradeRecord> trades;

  /// Reconstructs closed trades and performance metrics from [fills].
  factory PortfolioPerformance.fromFills(List<PaperFill> fills) {
    if (fills.isEmpty) {
      return const PortfolioPerformance(
        totalClosedTrades: 0,
        winningTrades: 0,
        losingTrades: 0,
        breakEvenTrades: 0,
        winRatePct: 0.0,
        totalRealizedPnl: 0.0,
        grossProfit: 0.0,
        grossLoss: 0.0,
        profitFactor: 0.0,
        avgWin: 0.0,
        avgLoss: 0.0,
        winLossRatio: 0.0,
        largestWin: 0.0,
        largestLoss: 0.0,
        trades: <ClosedTradeRecord>[],
      );
    }

    final closedTrades = <ClosedTradeRecord>[];
    // Map symbol to FIFO entries: list of (qty, price, time, side).
    final openLots = <String, List<_Lot>>{};

    // Lots only pair up correctly oldest-first. Callers pass the trade log
    // newest-first, which turned every round trip around (exit before
    // entry). Sort by time, keeping the given order for equal times.
    final indexed = <(int, PaperFill)>[
      for (var i = 0; i < fills.length; i++) (i, fills[i]),
    ]..sort((a, b) {
        final byTime = a.$2.time.compareTo(b.$2.time);
        return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
      });
    final chronological = [for (final e in indexed) e.$2];

    for (final fill in chronological) {
      final sym = fill.symbol.toUpperCase();
      final lots = openLots.putIfAbsent(sym, () => <_Lot>[]);

      if (fill.realizedPnl != 0 || (lots.isNotEmpty && lots.first.side != fill.side)) {
        // This fill closes or reduces an existing lot.
        var remainingCloseQty = fill.qty;
        while (remainingCloseQty > 0.000001 && lots.isNotEmpty) {
          final lot = lots.first;
          final matchedQty = remainingCloseQty < lot.qty ? remainingCloseQty : lot.qty;
          final isShort = lot.side == OrderSide.sell;
          final dir = isShort ? -1.0 : 1.0;
          final pnlPortion = (fill.price - lot.price) * matchedQty * dir;
          final costBasis = lot.price * matchedQty;
          final pnlPct = costBasis > 0 ? (pnlPortion / costBasis * 100) : 0.0;

          closedTrades.add(ClosedTradeRecord(
            id: fill.id,
            symbol: sym,
            side: lot.side,
            qty: matchedQty,
            entryPrice: lot.price,
            exitPrice: fill.price,
            entryTime: lot.time,
            exitTime: fill.time,
            realizedPnl: pnlPortion,
            pnlPct: pnlPct,
          ));

          lot.qty -= matchedQty;
          remainingCloseQty -= matchedQty;
          if (lot.qty <= 0.000001) {
            lots.removeAt(0);
          }
        }

        // Any leftover becomes a new opposite lot.
        if (remainingCloseQty > 0.000001) {
          lots.add(_Lot(
            side: fill.side,
            qty: remainingCloseQty,
            price: fill.price,
            time: fill.time,
          ));
        }
      } else {
        // Adding to position.
        lots.add(_Lot(
          side: fill.side,
          qty: fill.qty,
          price: fill.price,
          time: fill.time,
        ));
      }
    }

    // Sort newest trades first.
    closedTrades.sort((a, b) => b.exitTime.compareTo(a.exitTime));

    var wins = 0;
    var losses = 0;
    var evens = 0;
    var totalPnl = 0.0;
    var grossProfit = 0.0;
    var grossLoss = 0.0;
    var maxWin = 0.0;
    var maxLoss = 0.0;

    for (final t in closedTrades) {
      totalPnl += t.realizedPnl;
      if (t.isWin) {
        wins++;
        grossProfit += t.realizedPnl;
        if (t.realizedPnl > maxWin) maxWin = t.realizedPnl;
      } else if (t.isLoss) {
        losses++;
        final absLoss = t.realizedPnl.abs();
        grossLoss += absLoss;
        if (t.realizedPnl < maxLoss) maxLoss = t.realizedPnl;
      } else {
        evens++;
      }
    }

    final totalTrades = closedTrades.length;
    final winRate = totalTrades > 0 ? (wins / totalTrades * 100) : 0.0;
    final profitFactor = grossLoss > 0
        ? grossProfit / grossLoss
        : (grossProfit > 0 ? double.infinity : 0.0);
    final avgWin = wins > 0 ? grossProfit / wins : 0.0;
    final avgLoss = losses > 0 ? grossLoss / losses : 0.0;
    final winLossRatio = avgLoss > 0 ? avgWin / avgLoss : 0.0;

    return PortfolioPerformance(
      totalClosedTrades: totalTrades,
      winningTrades: wins,
      losingTrades: losses,
      breakEvenTrades: evens,
      winRatePct: winRate,
      totalRealizedPnl: totalPnl,
      grossProfit: grossProfit,
      grossLoss: grossLoss,
      profitFactor: profitFactor,
      avgWin: avgWin,
      avgLoss: avgLoss,
      winLossRatio: winLossRatio,
      largestWin: maxWin,
      largestLoss: maxLoss,
      trades: List<ClosedTradeRecord>.unmodifiable(closedTrades),
    );
  }
}

class _Lot {
  _Lot({
    required this.side,
    required this.qty,
    required this.price,
    required this.time,
  });

  final OrderSide side;
  double qty;
  final double price;
  final DateTime time;
}
