import '../analysis/estimator.dart';
import '../analysis/ml.dart';
import '../data/market_data_source.dart';
import '../data/models.dart';
import '../strategy/ensemble.dart';
import '../strategy/signals.dart';

class ScanOutcome {
  const ScanOutcome({
    required this.signals,
    required this.errors,
    required this.at,
    required this.dataSourceId,
  });

  final List<SignalScore> signals;
  final Map<String, String> errors;
  final DateTime at;
  final String dataSourceId;

  bool get hasErrors => errors.isNotEmpty;
}

/// Scans a watchlist and produces explainable ensemble signals. Also owns the
/// per-symbol online-ML model so learning persists between scans.
class MarketScanner {
  MarketScanner({
    required this.source,
    required this.estimator,
    required this.ensemble,
    this.barsPerSymbol = 220,
  });

  MarketDataSource source;
  final TrendEstimator estimator;
  SignalEnsemble ensemble;
  final int barsPerSymbol;

  /// symbol -> model (keyed uppercase).
  final Map<String, OnlineLogistic> models = <String, OnlineLogistic>{};

  /// Feature rows already fed to the model (keyed symbol) to avoid re-training
  /// on the same history every scan.
  final Map<String, int> trainedThrough = <String, int>{};

  OnlineLogistic modelFor(String symbol) =>
      models.putIfAbsent(symbol.toUpperCase(), () => OnlineLogistic(dim: SignalEnsemble.featureOrder.length));

  /// Full scan of [symbols]. Returns scores sorted by |score|.
  Future<ScanOutcome> scan(
    List<String> symbols, {
    BarInterval interval = BarInterval.fiveMin,
    DateTime? now,
    bool train = true,
  }) async {
    final at = now ?? DateTime.now();
    final signals = <SignalScore>[];
    final errors = <String, String>{};

    for (final rawSymbol in symbols) {
      final symbol = rawSymbol.toUpperCase();
      try {
        final bars = await source.getBars(
          symbol: symbol,
          interval: interval,
          limit: barsPerSymbol,
        );
        if (bars.length < 60) {
          errors[symbol] = 'only ${bars.length} bars available';
          continue;
        }
        final bundle = IndicatorBundle(bars);
        final snapshot = estimator.estimate(bars);
        final model = modelFor(symbol);

        if (train) {
          _trainIncremental(symbol, bars, snapshot, model);
        }

        final decision = ensemble.evaluate(
          bars: bars,
          snapshot: snapshot,
          bundle: bundle,
          model: model,
          now: at,
        );
        signals.add(decision.signal);
      } catch (e) {
        errors[symbol] = e.toString();
      }
    }

    signals.sort((a, b) => b.score.abs().compareTo(a.score.abs()));
    return ScanOutcome(
      signals: signals,
      errors: errors,
      at: at,
      dataSourceId: source.id,
    );
  }

  /// Train the model on historical bars with strict causality: each example
  /// uses features computed from bars 0..t and the label from bar t+1, and
  /// at live decision time every such label bar has already closed.
  void _trainIncremental(
    String symbol,
    List<Candle> bars,
    AnalysisSnapshot latestSnapshot,
    OnlineLogistic model,
  ) {
    final order = SignalEnsemble.featureOrder;
    final step = bars.length > 160 ? 2 : 1; // subsample long histories
    for (var t = 40; t < bars.length - 1; t += step) {
      final snap = estimator.estimate(bars.sublist(0, t + 1));
      final x = [for (final f in order) snap.features[f] ?? 0.0];
      final label = bars[t + 1].close > bars[t].close ? 1 : 0;
      model.trainStep(x, label);
    }
    trainedThrough[symbol] = bars.length;
    // Keep the normalizer aware of the latest row too.
    model.predictRaw([
      for (final f in order) latestSnapshot.features[f] ?? 0.0
    ]);
  }

  /// Direct evaluation for a single symbol (used by the chart screen).
  Future<SignalScore?> evaluateSymbol(
    String symbol, {
    BarInterval interval = BarInterval.fiveMin,
    int bars = 220,
    DateTime? now,
  }) async {
    final history = await source.getBars(
      symbol: symbol.toUpperCase(),
      interval: interval,
      limit: bars,
    );
    if (history.length < 60) return null;
    final snapshot = estimator.estimate(history);
    final model = modelFor(symbol);
    _trainIncremental(symbol.toUpperCase(), history, snapshot, model);
    final decision = ensemble.evaluate(
      bars: history,
      snapshot: snapshot,
      bundle: IndicatorBundle(history),
      model: model,
      now: now ?? DateTime.now(),
    );
    return decision.signal;
  }
}
