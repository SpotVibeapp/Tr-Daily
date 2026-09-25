import 'portfolio_analytics.dart';

/// One go-live check and how the paper record measures against it.
class ReadinessCheck {
  const ReadinessCheck({
    required this.label,
    required this.passed,
    required this.detail,
  });

  final String label;
  final bool passed;
  final String detail;
}

/// Whether the paper record is good enough to justify real money.
///
/// These are minimums, not a forecast. Passing them does not mean live
/// trading will make money. Failing them means the paper record has not
/// shown an edge yet, after costs.
class LiveReadiness {
  const LiveReadiness(this.checks);

  /// Enough trades that a result is not just a few lucky ones.
  static const int minTrades = 50;

  /// Gross profit at least 1.2× gross loss, after costs.
  static const double minProfitFactor = 1.2;

  /// Worst fall from a high, as a percent of the balance at that high.
  static const double maxDrawdownPct = 15;

  final List<ReadinessCheck> checks;

  bool get ready => checks.every((c) => c.passed);
  int get passedCount => checks.where((c) => c.passed).length;

  /// One line for the log or a dialog header.
  String get summary => ready
      ? 'Paper record meets all $passedCount go-live checks. This does not '
          'guarantee live results.'
      : 'Paper record meets $passedCount of ${checks.length} go-live checks. '
          'Keep paper trading until all pass.';

  factory LiveReadiness.fromPerformance(
    PortfolioPerformance perf, {
    required double startingEquity,
  }) {
    final n = perf.totalClosedTrades;
    final expectancy = n > 0 ? perf.totalRealizedPnl / n : 0.0;
    final pf = perf.profitFactor;
    final dd = closedTradeDrawdownPct(perf.trades, startingEquity);

    String money(double v) {
      final sign = v > 0 ? '+' : (v < 0 ? '-' : '');
      return '$sign\$${v.abs().toStringAsFixed(2)}';
    }

    return LiveReadiness(<ReadinessCheck>[
      ReadinessCheck(
        label: 'At least $minTrades completed paper trades',
        passed: n >= minTrades,
        detail: '$n of $minTrades',
      ),
      ReadinessCheck(
        label: 'Average trade makes money after costs',
        passed: n > 0 && expectancy > 0,
        detail: n == 0 ? 'no trades yet' : '${money(expectancy)} per trade',
      ),
      ReadinessCheck(
        label: 'Profit factor at least ${minProfitFactor.toStringAsFixed(1)}',
        passed: n > 0 && pf >= minProfitFactor,
        detail: n == 0
            ? 'no trades yet'
            : (pf.isInfinite ? 'no losing trades yet' : pf.toStringAsFixed(2)),
      ),
      ReadinessCheck(
        label: 'Worst drawdown within ${maxDrawdownPct.toStringAsFixed(0)}%',
        passed: n > 0 && dd <= maxDrawdownPct,
        detail: n == 0 ? 'no trades yet' : '${dd.toStringAsFixed(1)}%',
      ),
    ]);
  }
}

/// Largest peak-to-trough fall in balance across closed trades, in exit
/// order, as a percent of the peak. [startingEquity] is the balance before
/// the first trade.
double closedTradeDrawdownPct(
  List<ClosedTradeRecord> trades,
  double startingEquity,
) {
  if (trades.isEmpty || startingEquity <= 0) return 0;
  final ordered = List<ClosedTradeRecord>.from(trades)
    ..sort((a, b) => a.exitTime.compareTo(b.exitTime));
  var equity = startingEquity;
  var peak = startingEquity;
  var worst = 0.0;
  for (final t in ordered) {
    equity += t.realizedPnl;
    if (equity > peak) peak = equity;
    if (peak > 0) {
      final dd = (peak - equity) / peak * 100;
      if (dd > worst) worst = dd;
    }
  }
  return worst;
}
