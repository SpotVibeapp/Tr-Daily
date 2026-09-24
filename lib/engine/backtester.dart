import 'dart:math';

import '../analysis/estimator.dart';
import '../analysis/ml.dart';
import '../data/market_data_source.dart';
import '../data/models.dart';
import '../risk/risk_manager.dart';
import '../strategy/ensemble.dart';
import '../strategy/signals.dart';

class BacktestConfig {
  const BacktestConfig({
    this.startEquity = 25000,
    this.slippagePct = 0.02,
    this.feePerShare = 0,
    this.warmupBars = 60,
    this.useMl = true,
    this.risk = const RiskConfig(),
    this.ensemble = const EnsembleConfig(),
  });

  final double startEquity;
  final double slippagePct;
  final double feePerShare;
  final int warmupBars;
  final bool useMl;
  final RiskConfig risk;
  final EnsembleConfig ensemble;
}

class BacktestMetrics {
  const BacktestMetrics({
    required this.totalPnl,
    required this.returnPct,
    required this.winRate,
    required this.profitFactor,
    required this.maxDrawdownPct,
    required this.sharpe,
    required this.tradeCount,
    required this.avgWin,
    required this.avgLoss,
    required this.expectancy,
    required this.buyHoldPct,
    required this.exposurePct,
  });

  final double totalPnl;
  final double returnPct;
  final double winRate; // 0..100
  final double profitFactor; // grossWin / grossLoss
  final double maxDrawdownPct;
  final double sharpe; // per-bar returns → annualized-ish
  final int tradeCount;
  final double avgWin;
  final double avgLoss;
  final double expectancy; // avg $ per trade
  final double buyHoldPct;
  final double exposurePct;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'totalPnl': totalPnl,
        'returnPct': returnPct,
        'winRate': winRate,
        'profitFactor': profitFactor,
        'maxDrawdownPct': maxDrawdownPct,
        'sharpe': sharpe,
        'tradeCount': tradeCount,
        'avgWin': avgWin,
        'avgLoss': avgLoss,
        'expectancy': expectancy,
        'buyHoldPct': buyHoldPct,
        'exposurePct': exposurePct,
      };
}

class BacktestResult {
  const BacktestResult({
    required this.metrics,
    required this.equityCurve,
    required this.trades,
    required this.equityFinal,
    required this.warnings,
  });

  final BacktestMetrics metrics;

  /// (time, equity) sampled at each bar close.
  final List<(DateTime, double)> equityCurve;
  final List<StrategyTrade> trades;
  final double equityFinal;
  final List<String> warnings;
}

/// Bar-by-bar backtester with strict no-lookahead execution:
/// decisions are made on close of bar t, fills happen at open of bar t+1,
/// stops/targets are checked against the bar's high/low after entry.
class Backtester {
  Backtester({
    required this.source,
    required this.estimator,
    required this.config,
  });

  final MarketDataSource source;
  final TrendEstimator estimator;
  final BacktestConfig config;

  Future<BacktestResult> run({
    required String symbol,
    BarInterval interval = BarInterval.fiveMin,
    int bars = 500,
    DateTime? end,
  }) async {
    final history = await source.getBars(
      symbol: symbol.toUpperCase(),
      interval: interval,
      limit: bars,
      end: end,
    );
    if (history.length < config.warmupBars + 20) {
      throw StateError(
          'need ≥${config.warmupBars + 20} bars, got ${history.length}');
    }

    final ensemble = SignalEnsemble(config: config.ensemble);
    final model =
        config.useMl ? OnlineLogistic(dim: SignalEnsemble.featureOrder.length) : null;
    final order = SignalEnsemble.featureOrder;

    var equity = config.startEquity;
    var peak = equity;
    var maxDrawdownPct = 0.0;
    var barsInMarket = 0;

    final curve = <(DateTime, double)>[];
    final trades = <StrategyTrade>[];
    final warnings = <String>[];

    // Open position state.
    StrategyTrade? open;
    double stop = 0;
    double target = 0;
    double entryScore = 0;

    // Pending orders decided on bar t, filled at open of t+1.
    Stance pendingEntry = Stance.flat;
    double? pendingQty;
    bool pendingExit = false;

    for (var t = config.warmupBars; t < history.length; t++) {
      final bar = history[t];

      // ---- 1) Fill pending orders at this bar's open ----
      if (open != null || pendingEntry != Stance.flat) {
        if (pendingExit && open != null) {
          final exitPrice = _fillPrice(bar.open, short: open!.side == Stance.short, slippage: true);
          equity += _exitAt(open!, bar.time, exitPrice, 'signal exit').grossPnl;
          open = null;
          pendingExit = false;
        }
        if (pendingEntry != Stance.flat && open == null && pendingQty != null) {
          final fillPx =
              _fillPrice(bar.open, short: pendingEntry == Stance.short, slippage: true);
          final qty = pendingQty!;
          final fees = config.feePerShare * qty;
          open = StrategyTrade(
            symbol: symbol.toUpperCase(),
            side: pendingEntry,
            entryTime: bar.time,
            entryPrice: fillPx,
            qty: qty,
            exitTime: null,
            exitPrice: null,
            exitReason: '',
            fees: fees,
          );
          pendingEntry = Stance.flat;
          pendingQty = null;
        }
      }

      // ---- 2) Manage open position against this bar's range ----
      if (open != null) {
        barsInMarket++;
        final hitStop = open!.side == Stance.long
            ? bar.low <= stop
            : bar.high >= stop;
        final hitTarget = open!.side == Stance.long
            ? bar.high >= target
            : bar.low <= target;

        if (hitStop && hitTarget) {
          // Same-bar both-hit: assume stop first (conservative).
          equity += _exitAt(open!, bar.time, stop, 'stop loss').grossPnl;
          open = null;
        } else if (hitStop) {
          // Gap through stop fills at the (worse) open.
          final px = open!.side == Stance.long
              ? (bar.open < stop ? bar.open : stop)
              : (bar.open > stop ? bar.open : stop);
          equity += _exitAt(open!, bar.time, px, 'stop loss').grossPnl;
          open = null;
        } else if (hitTarget) {
          final px = open!.side == Stance.long
              ? (bar.open > target ? bar.open : target)
              : (bar.open < target ? bar.open : target);
          equity += _exitAt(open!, bar.time, px, 'take profit').grossPnl;
          open = null;
        }
      }

      // ---- 3) Learn + decide on close of this bar ----
      final window = history.sublist(0, t + 1);
      final bundle = IndicatorBundle(window);
      final snapshot = estimator.estimate(window);

      double? mlLean;
      if (model != null) {
        final x = [for (final f in order) snapshot.features[f] ?? 0.0];
        mlLean = model.isUsable ? 2 * model.predictRaw(x) - 1 : null;
        // Train on completed example: features up to t-1, label from t.
        if (t > config.warmupBars + 1) {
          final prev = estimator.estimate(history.sublist(0, t));
          final prevX = [for (final f in order) prev.features[f] ?? 0.0];
          final label = history[t].close > history[t - 1].close ? 1 : 0;
          model.trainStep(prevX, label);
        }
      }

      final decision = ensemble.evaluate(
        bars: window,
        snapshot: snapshot,
        bundle: bundle,
        model: model,
        now: bar.time,
      );
      final sig = decision.signal;

      // ---- 4) Risk & order generation ----
      if (open != null) {
        // Exit / flip handling.
        final stanceHeld = open!.side;
        final flipped = (stanceHeld == Stance.long && sig.stance == Stance.short) ||
            (stanceHeld == Stance.short && sig.stance == Stance.long);
        final exitSignal = ensemble.shouldExit(
          positionStance: stanceHeld,
          score: sig.score,
          confidence: sig.confidence,
          entryScore: entryScore,
        );
        if (flipped) {
          pendingExit = true;
          final qty = _size(equity, sig, bar, history, t);
          if (qty != null && qty > 0) {
            pendingEntry = sig.stance;
            pendingQty = qty;
            entryScore = sig.score;
            _armStops(sig.stance, snapshot.atrValue, bar.close);
          } else {
            pendingEntry = Stance.flat;
            pendingQty = null;
          }
        } else if (exitSignal) {
          pendingExit = true;
        }
      } else if (sig.stance != Stance.flat) {
        final qty = _size(equity, sig, bar, history, t);
        if (qty != null && qty > 0) {
          pendingEntry = sig.stance;
          pendingQty = qty;
          entryScore = sig.score;
          _armStops(sig.stance, snapshot.atrValue, bar.close);
        }
      }

      // ---- 5) Mark to market ----
      var mark = equity;
      if (open != null) {
        final dir = open!.side == Stance.short ? -1.0 : 1.0;
        mark += (bar.close - open!.entryPrice) * open!.qty * dir;
      }
      peak = max(peak, mark);
      if (peak > 0) {
        final dd = (peak - mark) / peak * 100;
        if (dd > maxDrawdownPct) maxDrawdownPct = dd;
      }
      curve.add((bar.time, mark));
    }

    // Force-close at the end for honest accounting.
    if (open != null) {
      final lastBar = history.last;
      final px = open!.side == Stance.short
          ? (lastBar.close + lastBar.close * config.slippagePct / 100)
          : (lastBar.close - lastBar.close * config.slippagePct / 100);
      equity += _exitAt(open!, lastBar.time, px, 'end of test').grossPnl;
      open = null;
    }

    final metrics = _metrics(
      equity: equity,
      curve: curve,
      trades: trades,
      history: history,
      startEquity: config.startEquity,
      maxDrawdownPct: maxDrawdownPct,
      barsInMarket: barsInMarket,
      totalBars: history.length - config.warmupBars,
    );
    if (config.useMl) {
      warnings.add('ML model trained walk-forward on ${model?.samplesSeen ?? 0} samples.');
    }
    return BacktestResult(
      metrics: metrics,
      equityCurve: curve,
      trades: trades,
      equityFinal: equity,
      warnings: warnings,
    );
  }

  /// Arm stop/target for a pending entry decided at [price] with ATR [a].
  void _armStops(Stance stance, double? a, double price) {
    final atr = (a != null && a > 0) ? a : price * 0.01;
    stop = stance == Stance.long
        ? price - config.risk.stopLossAtrMult * atr
        : price + config.risk.stopLossAtrMult * atr;
    target = stance == Stance.long
        ? price + config.risk.takeProfitAtrMult * atr
        : price - config.risk.takeProfitAtrMult * atr;
  }

  double _fillPrice(double open, {required bool short, required bool slippage}) {
    if (!slippage) return open;
    final slip = open * config.slippagePct / 100;
    return short ? open - slip : open + slip;
  }

  /// Record a completed trade (exit) and add it to the log. Returns the
  /// completed copy so callers can settle its (immutable) PnL.
  StrategyTrade _exitAt(
      StrategyTrade t, DateTime time, double price, String reason) {
    final done = StrategyTrade(
      symbol: t.symbol,
      side: t.side,
      entryTime: t.entryTime,
      entryPrice: t.entryPrice,
      qty: t.qty,
      exitTime: time,
      exitPrice: price,
      exitReason: reason,
      fees: t.fees,
    );
    trades.add(done);
    return done;
  }

  /// Position sizing identical in spirit to RiskManager, simplified for tests.
  double? _size(
    double equity,
    SignalScore sig,
    Candle bar,
    List<Candle> history,
    int t,
  ) {
    final window = history.sublist(max(0, t - 13), t + 1);
    double? a;
    if (window.length >= 14) {
      a = 0.0;
      var prevClose = window.first.close;
      for (var i = 1; i < window.length; i++) {
        final hl = window[i].high - window[i].low;
        final hc = (window[i].high - prevClose).abs();
        final lc = (window[i].low - prevClose).abs();
        a += max(hl, max(hc, lc));
        prevClose = window[i].close;
      }
      a /= (window.length - 1);
    }
    final atr = (a != null && a > 0) ? a : bar.close * 0.01;
    final stopDist = config.risk.stopLossAtrMult * atr;
    if (stopDist <= 0) return null;
    if (sig.confidence < config.risk.minConfidenceToTrade) return null;
    if (sig.stance == Stance.short && !config.risk.allowShort) return null;

    final riskDollars = equity * config.risk.riskPerTradePct / 100;
    var qty = riskDollars / stopDist;
    final maxByPosition = (equity * config.risk.maxPositionPct / 100) / bar.close;
    qty = min(qty, maxByPosition);
    qty = qty.floorToDouble();
    if (qty < 1) {
      if (1 <= maxByPosition) {
        qty = 1;
      } else {
        return null;
      }
    }
    return qty;
  }

  BacktestMetrics _metrics({
    required double equity,
    required List<(DateTime, double)> curve,
    required List<StrategyTrade> trades,
    required List<Candle> history,
    required double startEquity,
    required double maxDrawdownPct,
    required int barsInMarket,
    required int totalBars,
  }) {
    final wins = trades.where((t) => t.grossPnl > 0).toList();
    final losses = trades.where((t) => t.grossPnl <= 0).toList();
    final grossWin = wins.fold<double>(0, (a, t) => a + t.grossPnl);
    final grossLoss = losses.fold<double>(0, (a, t) => a + t.grossPnl).abs();
    final winRate = trades.isEmpty ? 0.0 : wins.length / trades.length * 100;
    final profitFactor =
        grossLoss == 0 ? (grossWin > 0 ? 999.0 : 0.0) : grossWin / grossLoss;

    // Sharpe from equity-curve bar returns.
    final rets = <double>[];
    for (var i = 1; i < curve.length; i++) {
      final prev = curve[i - 1].$2;
      if (prev > 0) rets.add((curve[i].$2 - prev) / prev);
    }
    var sharpe = 0.0;
    if (rets.length > 5) {
      final mean = rets.reduce((a, b) => a + b) / rets.length;
      final varr =
          rets.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) /
              rets.length;
      final sd = sqrt(varr);
      if (sd > 0) {
        // Bars are arbitrary intervals; scale by sqrt(bars/year) ~ sqrt(252)
        // for daily-ish granularity (kept as a rough, clearly-labeled figure).
        sharpe = mean / sd * sqrt(252);
      }
    }

    final buyHoldPct =
        (history.last.close - history[config.warmupBars].close) /
            history[config.warmupBars].close *
            100;
    final avgWin = wins.isEmpty
        ? 0.0
        : grossWin / wins.length;
    final avgLoss =
        losses.isEmpty ? 0.0 : grossLoss / losses.length * -1;

    return BacktestMetrics(
      totalPnl: equity - startEquity,
      returnPct: (equity - startEquity) / startEquity * 100,
      winRate: winRate,
      profitFactor: profitFactor,
      maxDrawdownPct: maxDrawdownPct,
      sharpe: sharpe,
      tradeCount: trades.length,
      avgWin: avgWin,
      avgLoss: avgLoss,
      expectancy: trades.isEmpty
          ? 0.0
          : (equity - startEquity) / trades.length,
      buyHoldPct: buyHoldPct,
      exposurePct: totalBars == 0 ? 0 : barsInMarket / totalBars * 100,
    );
  }
}
