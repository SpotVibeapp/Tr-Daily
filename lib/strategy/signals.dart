import '../analysis/estimator.dart';
import '../analysis/indicators.dart';
import '../data/models.dart';

/// Individual chart-trend signals. Each returns a lean in [-1, 1]
/// (negative = bearish, positive = bullish) plus a human-readable reason.
class SignalRead {
  const SignalRead(this.name, this.value, this.reason);

  final String name;
  final double value;
  final String reason;

  /// Contribution suppressed when the market is choppy for this signal.
  static const SignalRead neutral = SignalRead('neutral', 0, 'no read');
}

/// Precomputed indicator series needed by the signal rules.
class IndicatorBundle {
  IndicatorBundle(this.bars)
      : closes = bars.map((b) => b.close).toList(),
        emaFast = ema(bars.map((b) => b.close).toList(), 9),
        emaSlow = ema(bars.map((b) => b.close).toList(), 21),
        rsiSeries = rsi(bars.map((b) => b.close).toList(), 14),
        macdSeries = macd(bars.map((b) => b.close).toList()),
        bb = bollinger(bars.map((b) => b.close).toList()),
        atrSeries = atr(bars, 14),
        vwapSeries = sessionVwap(bars),
        donchSeries = donchian(bars, period: 20),
        stochSeries = stochastic(bars),
        adxSeries = adx(bars, 14),
        rocSeries = roc(bars.map((b) => b.close).toList(), 5);

  final List<Candle> bars;
  final List<double> closes;
  final List<double?> emaFast;
  final List<double?> emaSlow;
  final List<double?> rsiSeries;
  final MacdResult macdSeries;
  final BollingerResult bb;
  final List<double?> atrSeries;
  final List<double?> vwapSeries;
  final DonchianResult donchSeries;
  final StochasticResult stochSeries;
  final AdxResult adxSeries;
  final List<double?> rocSeries;

  double? get price => bars.isEmpty ? null : bars.last.close;
  int get i => bars.length - 1;
}

/// 9/21 EMA trend-following signal.
SignalRead emaTrendSignal(IndicatorBundle b) {
  final f = b.emaFast[b.i];
  final s = b.emaSlow[b.i];
  if (f == null || s == null || s == 0) return SignalRead.neutral;
  final spread = (f - s) / s;
  final lean = (spread * 60).clamp(-1.0, 1.0);
  return SignalRead(
    'EMA 9/21',
    lean,
    lean > 0
        ? 'fast EMA above slow (+${(spread * 100).toStringAsFixed(2)}%)'
        : 'fast EMA below slow (${(spread * 100).toStringAsFixed(2)}%)',
  );
}

/// MACD histogram direction & acceleration.
SignalRead macdSignal(IndicatorBundle b) {
  final h = b.macdSeries.histogram[b.i];
  final hp = b.i > 0 ? b.macdSeries.histogram[b.i - 1] : null;
  if (h == null || hp == null) return SignalRead.neutral;
  final improving = (h - hp).sign;
  final lean = (0.6 * h.sign + 0.4 * improving).clamp(-1.0, 1.0);
  return SignalRead(
    'MACD',
    lean,
    lean > 0
        ? 'histogram positive${improving > 0 ? ' & rising' : ''}'
        : 'histogram negative${improving < 0 ? ' & falling' : ''}',
  );
}

/// RSI mean-reversion extremes (only acts outside the 30–70 comfort zone).
SignalRead rsiSignal(IndicatorBundle b) {
  final r = b.rsiSeries[b.i];
  if (r == null) return SignalRead.neutral;
  if (r >= 70) {
    return SignalRead('RSI', -((r - 70) / 20).clamp(0.0, 1.0),
        'overbought RSI ${r.toStringAsFixed(0)}');
  }
  if (r <= 30) {
    return SignalRead('RSI', ((30 - r) / 20).clamp(0.0, 1.0),
        'oversold RSI ${r.toStringAsFixed(0)}');
  }
  // Mid-zone: mild momentum lean.
  return SignalRead(
    'RSI',
    ((r - 50) / 50 * 0.4).clamp(-0.4, 0.4),
    'RSI ${r.toStringAsFixed(0)}',
  );
}

/// Bollinger %B — breakout (walk-the-band) vs reversion.
SignalRead bollingerSignal(IndicatorBundle b) {
  final pb = b.bb.percentB[b.i];
  if (pb == null) return SignalRead.neutral;
  if (pb > 1.0) {
    return SignalRead('Bollinger', 0.5, 'closed above upper band (breakout)');
  }
  if (pb < 0.0) {
    return SignalRead('Bollinger', -0.5, 'closed below lower band (breakdown)');
  }
  // Inside bands: mild reversion pull toward mid.
  return SignalRead(
    'Bollinger',
    ((0.5 - pb) * 1.2).clamp(-0.6, 0.6),
    '%B ${pb.toStringAsFixed(2)} → reversion lean',
  );
}

/// 20-bar Donchian breakout.
SignalRead breakoutSignal(IndicatorBundle b) {
  final up = b.donchSeries.upper[b.i];
  final lo = b.donchSeries.lower[b.i];
  final price = b.price;
  if (up == null || lo == null || price == null) return SignalRead.neutral;
  if (price > up) {
    return SignalRead('Breakout', 1.0, 'new 20-bar high \$${price.toStringAsFixed(2)}');
  }
  if (price < lo) {
    return SignalRead('Breakout', -1.0, 'new 20-bar low \$${price.toStringAsFixed(2)}');
  }
  return SignalRead('Breakout', 0, 'inside 20-bar range');
}

/// Price vs session VWAP (institutional bias for day trading).
SignalRead vwapSignal(IndicatorBundle b) {
  final v = b.vwapSeries[b.i];
  final price = b.price;
  if (v == null || price == null || v == 0) return SignalRead.neutral;
  final dist = (price - v) / v;
  final lean = (dist * 40).clamp(-0.8, 0.8);
  return SignalRead(
    'VWAP',
    lean,
    dist >= 0
        ? 'price ${dist >= 0 ? '+' : ''}${(dist * 100).toStringAsFixed(2)}% vs VWAP'
        : 'price ${(dist * 100).toStringAsFixed(2)}% vs VWAP',
  );
}

/// Stochastic crossing out of extremes.
SignalRead stochSignal(IndicatorBundle b) {
  final k = b.stochSeries.k[b.i];
  final d = b.stochSeries.d[b.i];
  if (k == null || d == null) return SignalRead.neutral;
  if (k < 25 && k > d) {
    return SignalRead('Stochastic', 0.7, '%K %D bullish cross in oversold zone');
  }
  if (k > 75 && k < d) {
    return SignalRead('Stochastic', -0.7, '%K %D bearish cross in overbought zone');
  }
  return SignalRead(
    'Stochastic',
    ((k - 50) / 100).clamp(-0.3, 0.3),
    'K ${k.toStringAsFixed(0)} / D ${d.toStringAsFixed(0)}',
  );
}

/// ADX gates the ensemble: strong trend ⇒ directional signals count more,
/// chop ⇒ confidence is cut.
double adxGate(IndicatorBundle b) {
  final a = b.adxSeries.adx[b.i];
  if (a == null) return 0.5;
  if (a >= 25) return 1.0;
  if (a >= 18) return 0.7;
  return 0.35;
}

/// One-shot evaluation of every rule on the bundle.
List<SignalRead> allSignals(IndicatorBundle b) => <SignalRead>[
      emaTrendSignal(b),
      macdSignal(b),
      rsiSignal(b),
      bollingerSignal(b),
      breakoutSignal(b),
      vwapSignal(b),
      stochSignal(b),
    ];

/// Structure note (support/resistance touch) folded into reasons.
String structureNote(AnalysisSnapshot snap) {
  final bits = <String>[];
  if (snap.support != null) {
    bits.add('support \$${snap.support!.toStringAsFixed(2)}');
  }
  if (snap.resistance != null) {
    bits.add('resistance \$${snap.resistance!.toStringAsFixed(2)}');
  }
  if (snap.patterns.isNotEmpty) {
    bits.add('patterns: ${snap.patterns.map((p) => p.name).join(', ')}');
  }
  return bits.isEmpty ? 'no key levels nearby' : bits.join(' · ');
}
