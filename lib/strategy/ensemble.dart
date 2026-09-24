import '../analysis/estimator.dart';
import '../analysis/ml.dart';
import '../data/models.dart';
import 'signals.dart';

/// Weights & thresholds for the ensemble. Serialized in settings.
class EnsembleConfig {
  const EnsembleConfig({
    this.weights = const <String, double>{
      'EMA 9/21': 1.1,
      'MACD': 1.0,
      'RSI': 0.7,
      'Bollinger': 0.8,
      'Breakout': 1.2,
      'VWAP': 1.0,
      'Stochastic': 0.7,
    },
    this.trendWeight = 0.9,
    this.structureWeight = 0.5,
    this.mlWeight = 0.6,
    this.enterThreshold = 0.45,
    this.exitThreshold = 0.10,
    this.minConfidence = 0.35,
    this.useMl = true,
  });

  final Map<String, double> weights;
  final double trendWeight;
  final double structureWeight;
  final double mlWeight;
  final double enterThreshold;
  final double exitThreshold;
  final double minConfidence;
  final bool useMl;

  EnsembleConfig copyWithEntry(double enter) => EnsembleConfig(
        weights: weights,
        trendWeight: trendWeight,
        structureWeight: structureWeight,
        mlWeight: mlWeight,
        enterThreshold: enter,
        exitThreshold: exitThreshold,
        minConfidence: minConfidence,
        useMl: useMl,
      );

  EnsembleConfig copyWithMl(bool use) => EnsembleConfig(
        weights: weights,
        trendWeight: trendWeight,
        structureWeight: structureWeight,
        mlWeight: mlWeight,
        enterThreshold: enterThreshold,
        exitThreshold: exitThreshold,
        minConfidence: minConfidence,
        useMl: use,
      );

  EnsembleConfig copyWithMlWeight(double w) => EnsembleConfig(
        weights: weights,
        trendWeight: trendWeight,
        structureWeight: structureWeight,
        mlWeight: w,
        enterThreshold: enterThreshold,
        exitThreshold: exitThreshold,
        minConfidence: minConfidence,
        useMl: useMl,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'weights': weights,
        'trendWeight': trendWeight,
        'structureWeight': structureWeight,
        'mlWeight': mlWeight,
        'enterThreshold': enterThreshold,
        'exitThreshold': exitThreshold,
        'minConfidence': minConfidence,
        'useMl': useMl,
      };

  factory EnsembleConfig.fromJson(Map<String, dynamic> json) {
    final defaults = const EnsembleConfig();
    final w = json['weights'];
    return EnsembleConfig(
      weights: w is Map<String, dynamic>
          ? w.map((k, v) => MapEntry(k, (v as num).toDouble()))
          : defaults.weights,
      trendWeight: (json['trendWeight'] as num?)?.toDouble() ?? defaults.trendWeight,
      structureWeight:
          (json['structureWeight'] as num?)?.toDouble() ?? defaults.structureWeight,
      mlWeight: (json['mlWeight'] as num?)?.toDouble() ?? defaults.mlWeight,
      enterThreshold:
          (json['enterThreshold'] as num?)?.toDouble() ?? defaults.enterThreshold,
      exitThreshold:
          (json['exitThreshold'] as num?)?.toDouble() ?? defaults.exitThreshold,
      minConfidence:
          (json['minConfidence'] as num?)?.toDouble() ?? defaults.minConfidence,
      useMl: json['useMl'] as bool? ?? defaults.useMl,
    );
  }
}

/// The combined, explainable decision for one symbol at one point in time.
class EnsembleDecision {
  const EnsembleDecision({
    required this.signal,
    required this.action,
    required this.reason,
  });

  final SignalScore signal;

  /// `long`, `short` or `flat` (no new entry).
  final String action;

  final String reason;

  bool get actionable => action != 'flat';
}

/// Fuses chart-trend signals + estimator trend read + (optional) online-ML
/// probability into one score with confidence & reasons.
class SignalEnsemble {
  SignalEnsemble({this.config = const EnsembleConfig()});

  EnsembleConfig config;

  /// Feature order expected by the ML model — must match
  /// [TrendEstimator] output keys.
  static const List<String> featureOrder = <String>[
    'ema_spread',
    'rsi',
    'macd_hist_norm',
    'macd_hist_delta',
    'adx',
    'di_diff',
    'vwap_dist',
    'bb_pctb',
    'slope',
    'roc5',
    'range_pos',
    'stoch_k',
    'pattern',
    'vol_z',
  ];

  /// Build the composite score from precomputed indicator reads + snapshot.
  ///
  /// [model] may be null (no ML yet) — the ensemble degrades to pure
  /// heuristics in that case.
  EnsembleDecision evaluate({
    required List<Candle> bars,
    required AnalysisSnapshot snapshot,
    required IndicatorBundle bundle,
    required OnlineLogistic? model,
    DateTime? now,
  }) {
    final price = bars.last.close;
    final reads = allSignals(bundle);
    final gate = adxGate(bundle);

    // 1) Rule signals, weighted.
    var wSum = 0.0;
    var ruleScore = 0.0;
    final breakdown = <String, double>{};
    final reasons = <String>[];
    for (final r in reads) {
      final w = config.weights[r.name] ?? 1.0;
      wSum += w;
      ruleScore += r.value * w;
      breakdown[r.name] = double.parse(r.value.toStringAsFixed(3));
      if (r.value.abs() >= 0.35) {
        reasons.add('${r.name}: ${r.reason}');
      }
    }
    final rules = wSum > 0 ? ruleScore / wSum : 0.0;

    // 2) Estimator trend read (structure-aware).
    final trend = snapshot.trendScore;

    // 3) ML probability (optional).
    double? mlP;
    var mlLean = 0.0;
    final rawFeatures = [
      for (final f in featureOrder) snapshot.features[f] ?? 0.0
    ];
    if (config.useMl && model != null && model.isUsable) {
      mlP = model.predictRaw(rawFeatures);
      mlLean = 2 * mlP - 1;
    }

    // Fusion: heuristic core + trend structure + ML overlay.
    final base = (rules * config.trendWeight * 0.55 +
            trend * config.trendWeight * 0.45 +
            snapshot.patternScore * config.structureWeight * 0.5)
        .clamp(-1.0, 1.0);
    final hasMl = mlP != null;
    final score = hasMl
        ? ((1 - config.mlWeight) * base + config.mlWeight * mlLean).clamp(-1.0, 1.0)
        : base;

    // Confidence: trend quality + signal agreement + ADX gate (+ ML samples).
    var conf = snapshot.trendConfidence * 0.45;
    final avgAbs = reads.isEmpty
        ? 0.0
        : reads.map((r) => r.value.abs()).reduce((a, b) => a + b) / reads.length;
    conf += avgAbs * 0.3;
    conf += gate * 0.15;
    if (hasMl) {
      final p = mlP!;
      final agreement = p > 0.5 ? p : 1 - p; // model's own certainty
      conf += agreement * 0.1 * (model!.samplesSeen / 400).clamp(0.0, 1.0);
    }
    conf = conf.clamp(0.0, 1.0);

    // Stance & action.
    Stance stance = Stance.flat;
    if (score >= config.enterThreshold && conf >= config.minConfidence) {
      stance = Stance.long;
    } else if (score <= -config.enterThreshold && conf >= config.minConfidence) {
      stance = Stance.short;
    }

    reasons.add('composite ${score.toStringAsFixed(2)} · '
        'conf ${(conf * 100).round()}% · ADX gate ${gate.toStringAsFixed(2)}');
    if (hasMl) {
      reasons.add('model P(up)=${mlP!.toStringAsFixed(2)} '
          '(n=${model!.samplesSeen})');
    }
    reasons.add(structureNote(snapshot));

    final atr = snapshot.atrValue ?? price * 0.01;
    final stop = stance == Stance.flat
        ? null
        : stance == Stance.long
            ? price - 1.5 * atr
            : price + 1.5 * atr;
    final target = stance == Stance.flat
        ? null
        : stance == Stance.long
            ? price + 2.5 * atr
            : price - 2.5 * atr;

    final signal = SignalScore(
      symbol: bars.last.symbol,
      score: score,
      confidence: conf,
      stance: stance,
      reasons: reasons,
      price: price,
      generatedAt: now ?? DateTime.now(),
      mlProbability: mlP,
      suggestedStop: stop,
      suggestedTarget: target,
      breakdown: breakdown,
    );

    return EnsembleDecision(
      signal: signal,
      action: switch (stance) {
        Stance.long => 'long',
        Stance.short => 'short',
        Stance.flat => 'flat',
      },
      reason: reasons.first,
    );
  }

  /// Exit check used by the engine: does an open position still have support?
  bool shouldExit({
    required Stance positionStance,
    required double score,
    required double confidence,
    required double entryScore,
  }) {
    if (positionStance == Stance.long) {
      // Longs exit when the score collapses or flips.
      return score <= config.exitThreshold || score < entryScore - 0.6;
    }
    if (positionStance == Stance.short) {
      return score >= -config.exitThreshold || score > entryScore + 0.6;
    }
    return true;
  }
}
