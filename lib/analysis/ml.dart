import 'dart:math';

/// Lightweight, dependency-free machine learning.
///
/// A tiny online logistic-regression model learns the relationship between
/// the estimator's feature vector and the direction of the next bar. It is
/// deliberately simple: fully inspectable, deterministic, cheap to run on a
/// phone, and honest about its confidence (it reports training sample count).
library;

/// Standardizes features with running statistics (Welford).
class FeatureNormalizer {
  FeatureNormalizer(this.dim);

  final int dim;
  final List<double> _mean = [];
  final List<double> _m2 = [];
  int n = 0;

  void _ensure() {
    if (_mean.length != dim) {
      _mean.addAll(List<double>.filled(dim - _mean.length, 0));
      _m2.addAll(List<double>.filled(dim - _m2.length, 0));
    }
  }

  void observe(List<double> x) {
    _ensure();
    n++;
    for (var i = 0; i < dim && i < x.length; i++) {
      final delta = x[i] - _mean[i];
      _mean[i] += delta / n;
      _m2[i] += delta * (x[i] - _mean[i]);
    }
  }

  double? _std(int i) {
    if (n < 2) return null;
    final v = _m2[i] / (n - 1);
    return v <= 0 ? null : sqrt(v);
  }

  List<double> normalize(List<double> x) {
    _ensure();
    final out = List<double>.filled(dim, 0);
    for (var i = 0; i < dim && i < x.length; i++) {
      final sd = _std(i);
      out[i] = sd == null ? 0 : ((x[i] - _mean[i]) / sd).clamp(-6.0, 6.0);
    }
    return out;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'dim': dim,
        'n': n,
        'mean': _mean,
        'm2': _m2,
      };

  void loadJson(Map<String, dynamic> json) {
    if ((json['dim'] as int?) != dim) return;
    n = json['n'] as int? ?? 0;
    _mean
      ..clear()
      ..addAll((json['mean'] as List<dynamic>).map((v) => (v as num).toDouble()));
    _m2
      ..clear()
      ..addAll((json['m2'] as List<dynamic>).map((v) => (v as num).toDouble()));
  }
}

/// Online logistic regression trained with SGD + L2 regularization.
class OnlineLogistic {
  OnlineLogistic({required this.dim, this.learningRate = 0.05, this.l2 = 1e-4})
      : _normalizer = FeatureNormalizer(dim) {
    weights = List<double>.filled(dim, 0);
    bias = 0;
  }

  final int dim;
  final double learningRate;
  final double l2;
  final FeatureNormalizer _normalizer;
  late List<double> weights;
  double bias = 0;
  int samplesSeen = 0;

  /// Probability of "up" for a **raw** feature vector in feature order.
  double predictRaw(List<double> raw) {
    final x = _normalizer.normalize(raw);
    return predict(x);
  }

  /// Probability of "up" for an already-normalized vector.
  double predict(List<double> x) {
    var z = bias;
    for (var i = 0; i < dim && i < x.length; i++) {
      z += weights[i] * x[i];
    }
    return 1 / (1 + exp(-z.clamp(-30, 30)));
  }

  /// One SGD step. [label] = 1 when the next bar closed higher.
  void trainStep(List<double> raw, int label) {
    _normalizer.observe(raw);
    final x = _normalizer.normalize(raw);
    final p = predict(x);
    final err = p - label;
    for (var i = 0; i < dim && i < x.length; i++) {
      weights[i] -= learningRate * (err * x[i] + l2 * weights[i]);
    }
    bias -= learningRate * err;
    samplesSeen++;
  }

  /// Train for [epochs] passes over [dataset].
  void train(List<List<double>> dataset, List<int> labels, {int epochs = 4}) {
    for (var e = 0; e < epochs; e++) {
      for (var i = 0; i < dataset.length; i++) {
        trainStep(dataset[i], labels[i]);
      }
    }
  }

  /// True when there is enough data for the prediction to mean anything.
  bool get isUsable => samplesSeen >= 60;

  /// Map the model's probability for [raw] features to a [-1, 1] lean.
  double leanFor(List<double> raw) =>
      isUsable ? (2 * predictRaw(raw) - 1) : 0;
}

/// Convenience: build a causal (feature_t -> label from t+1) dataset.
(List<List<double>>, List<int>) buildDataset({
  required List<Map<String, double>> featureRows,
  required List<double> closes,
  required List<String> featureOrder,
}) {
  final xs = <List<double>>[];
  final ys = <int>[];
  for (var t = 0; t < featureRows.length - 1 && t < closes.length - 1; t++) {
    final row = featureRows[t];
    xs.add([for (final f in featureOrder) row[f] ?? 0.0]);
    ys.add(closes[t + 1] > closes[t] ? 1 : 0);
  }
  return (xs, ys);
}
