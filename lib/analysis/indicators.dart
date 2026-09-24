/// Classic technical indicators. All functions are **causal**: value at index
/// `i` uses only data at `indices <= i` (no lookahead), so they are safe for
/// both live scanning and backtests. Warm-up positions are `null`.
library;

import 'dart:math';

import '../data/models.dart';

/// Simple moving average.
List<double?> sma(List<double> values, int period) {
  _checkPeriod(period, values.length);
  final out = List<double?>.filled(values.length, null);
  if (values.length < period) return out;
  var sum = 0.0;
  for (var i = 0; i < values.length; i++) {
    sum += values[i];
    if (i >= period) sum -= values[i - period];
    if (i >= period - 1) out[i] = sum / period;
  }
  return out;
}

/// Exponential moving average, seeded with the SMA of the first [period] values.
List<double?> ema(List<double> values, int period) {
  _checkPeriod(period, values.length);
  final out = List<double?>.filled(values.length, null);
  if (values.length < period) return out;
  final k = 2 / (period + 1);
  var sum = 0.0;
  for (var i = 0; i < period; i++) {
    sum += values[i];
  }
  var prev = sum / period;
  out[period - 1] = prev;
  for (var i = period; i < values.length; i++) {
    prev = (values[i] - prev) * k + prev;
    out[i] = prev;
  }
  return out;
}

/// Wilder RSI in [0, 100].
List<double?> rsi(List<double> closes, int period) {
  _checkPeriod(period, closes.length);
  final out = List<double?>.filled(closes.length, null);
  if (closes.length <= period) return out;
  var gain = 0.0;
  var loss = 0.0;
  for (var i = 1; i <= period; i++) {
    final ch = closes[i] - closes[i - 1];
    if (ch >= 0) {
      gain += ch;
    } else {
      loss -= ch;
    }
  }
  var avgGain = gain / period;
  var avgLoss = loss / period;
  out[period] = _rsiFrom(avgGain, avgLoss);
  for (var i = period + 1; i < closes.length; i++) {
    final ch = closes[i] - closes[i - 1];
    final g = ch > 0 ? ch : 0.0;
    final l = ch < 0 ? -ch : 0.0;
    avgGain = (avgGain * (period - 1) + g) / period;
    avgLoss = (avgLoss * (period - 1) + l) / period;
    out[i] = _rsiFrom(avgGain, avgLoss);
  }
  return out;
}

double _rsiFrom(double avgGain, double avgLoss) {
  if (avgLoss == 0) return 100;
  final rs = avgGain / avgLoss;
  return 100 - 100 / (1 + rs);
}

class MacdResult {
  const MacdResult({required this.macd, required this.signal, required this.histogram});

  final List<double?> macd;
  final List<double?> signal;
  final List<double?> histogram;
}

/// MACD(12, 26, 9) line, signal line and histogram.
MacdResult macd(List<double> closes, {int fast = 12, int slow = 26, int signalPeriod = 9}) {
  final fastEma = ema(closes, fast);
  final slowEma = ema(closes, slow);
  final line = List<double?>.filled(closes.length, null);
  for (var i = 0; i < closes.length; i++) {
    final f = fastEma[i];
    final s = slowEma[i];
    if (f != null && s != null) line[i] = f - s;
  }
  // Signal = EMA of the MACD line over its non-null stretch.
  final firstIdx = line.indexWhere((v) => v != null);
  final signal = List<double?>.filled(closes.length, null);
  if (firstIdx >= 0) {
    final compact = line.sublist(firstIdx).map((v) => v!).toList();
    final sig = ema(compact, signalPeriod);
    for (var i = 0; i < sig.length; i++) {
      signal[firstIdx + i] = sig[i];
    }
  }
  final hist = List<double?>.filled(closes.length, null);
  for (var i = 0; i < closes.length; i++) {
    final m = line[i];
    final s = signal[i];
    if (m != null && s != null) hist[i] = m - s;
  }
  return MacdResult(macd: line, signal: signal, histogram: hist);
}

class BollingerResult {
  const BollingerResult({
    required this.upper,
    required this.middle,
    required this.lower,
    required this.percentB,
  });

  final List<double?> upper;
  final List<double?> middle;
  final List<double?> lower;

  /// %B in practice: (price - lower) / (upper - lower).
  final List<double?> percentB;
}

/// Bollinger Bands(20, 2.0).
BollingerResult bollinger(List<double> closes, {int period = 20, double mult = 2}) {
  final mid = sma(closes, period);
  final upper = List<double?>.filled(closes.length, null);
  final lower = List<double?>.filled(closes.length, null);
  final pctB = List<double?>.filled(closes.length, null);
  for (var i = period - 1; i < closes.length; i++) {
    final m = mid[i]!;
    var sq = 0.0;
    for (var j = i - period + 1; j <= i; j++) {
      sq += (closes[j] - m) * (closes[j] - m);
    }
    final sd = sqrt(sq / period);
    final u = m + mult * sd;
    final l = m - mult * sd;
    upper[i] = u;
    lower[i] = l;
    if (u != l) pctB[i] = (closes[i] - l) / (u - l);
  }
  return BollingerResult(upper: upper, middle: mid, lower: lower, percentB: pctB);
}

/// Wilder ATR(14).
List<double?> atr(List<Candle> candles, int period) {
  _checkPeriod(period, candles.length);
  final out = List<double?>.filled(candles.length, null);
  if (candles.length <= period) return out;
  final tr = <double>[];
  for (var i = 1; i < candles.length; i++) {
    tr.add(_trueRange(candles[i], candles[i - 1]));
  }
  // tr[0] corresponds to candle index 1.
  var sum = 0.0;
  for (var i = 0; i < period; i++) {
    sum += tr[i];
  }
  var prev = sum / period;
  out[period] = prev;
  for (var i = period; i < tr.length; i++) {
    prev = (prev * (period - 1) + tr[i]) / period;
    out[i + 1] = prev;
  }
  return out;
}

double _trueRange(Candle c, Candle prev) {
  final hl = c.high - c.low;
  return max(hl, max((c.high - prev.close).abs(), (c.low - prev.close).abs()));
}

class StochasticResult {
  const StochasticResult({required this.k, required this.d});

  final List<double?> k;
  final List<double?> d;
}

/// Slow stochastic %K / %D (14, 3).
StochasticResult stochastic(List<Candle> candles, {int period = 14, int smooth = 3}) {
  final rawK = List<double?>.filled(candles.length, null);
  for (var i = period - 1; i < candles.length; i++) {
    var hh = -double.infinity;
    var ll = double.infinity;
    for (var j = i - period + 1; j <= i; j++) {
      hh = max(hh, candles[j].high);
      ll = min(ll, candles[j].low);
    }
    rawK[i] = hh == ll ? 50.0 : (candles[i].close - ll) / (hh - ll) * 100;
  }
  final k = sma(rawK.map((v) => v ?? 50.0).toList(), smooth);
  // Only expose K after rawK warms up.
  for (var i = 0; i < candles.length; i++) {
    if (rawK[i] == null) k[i] = null;
  }
  final d = sma(k.map((v) => v ?? 50.0).toList(), smooth);
  for (var i = 0; i < candles.length; i++) {
    if (k[i] == null) d[i] = null;
  }
  return StochasticResult(k: k, d: d);
}

class AdxResult {
  const AdxResult({
    required this.adx,
    required this.plusDi,
    required this.minusDi,
  });

  final List<double?> adx;
  final List<double?> plusDi;
  final List<double?> minusDi;
}

/// Wilder ADX(14) with directional indicators — trend *strength*.
AdxResult adx(List<Candle> candles, int period) {
  final n = candles.length;
  final outAdx = List<double?>.filled(n, null);
  final outPd = List<double?>.filled(n, null);
  final outMd = List<double?>.filled(n, null);
  if (n < 2 * period + 1) return AdxResult(adx: outAdx, plusDi: outPd, minusDi: outMd);

  final trs = <double>[];
  final pdms = <double>[];
  final mdms = <double>[];
  for (var i = 1; i < n; i++) {
    trs.add(_trueRange(candles[i], candles[i - 1]));
    final up = candles[i].high - candles[i - 1].high;
    final down = candles[i - 1].low - candles[i].low;
    pdms.add(up > down && up > 0 ? up : 0);
    mdms.add(down > up && down > 0 ? down : 0);
  }

  // Wilder smoothing.
  double sumTr = 0, sumP = 0, sumM = 0;
  for (var i = 0; i < period; i++) {
    sumTr += trs[i];
    sumP += pdms[i];
    sumM += mdms[i];
  }
  final dxs = <double>[];
  double? adxVal;
  for (var i = period; i < trs.length; i++) {
    if (i > period) {
      sumTr = sumTr - sumTr / period + trs[i];
      sumP = sumP - sumP / period + pdms[i];
      sumM = sumM - sumM / period + mdms[i];
    }
    final pdi = sumTr == 0 ? 0.0 : 100 * sumP / sumTr;
    final mdi = sumTr == 0 ? 0.0 : 100 * sumM / sumTr;
    final denom = pdi + mdi;
    final dx = denom == 0 ? 0.0 : 100 * (pdi - mdi).abs() / denom;
    final bar = i + 1; // trs[i] belongs to candle i+1
    outPd[bar] = pdi;
    outMd[bar] = mdi;
    dxs.add(dx);
    if (dxs.length == period) {
      adxVal = dxs.reduce((a, b) => a + b) / period;
      outAdx[bar] = adxVal;
    } else if (dxs.length > period && adxVal != null) {
      adxVal = (adxVal * (period - 1) + dx) / period;
      outAdx[bar] = adxVal;
    }
  }
  return AdxResult(adx: outAdx, plusDi: outPd, minusDi: outMd);
}

/// Session VWAP (resets each calendar day): sum(typical*vol)/sum(vol).
List<double?> sessionVwap(List<Candle> candles) {
  final out = List<double?>.filled(candles.length, null);
  var pv = 0.0;
  var vol = 0.0;
  DateTime? day;
  for (var i = 0; i < candles.length; i++) {
    final d = DateTime(candles[i].time.year, candles[i].time.month, candles[i].time.day);
    if (day == null || d != day) {
      day = d;
      pv = 0;
      vol = 0;
    }
    final v = candles[i].volume <= 0 ? 1.0 : candles[i].volume;
    pv += candles[i].typical * v;
    vol += v;
    out[i] = pv / vol;
  }
  return out;
}

/// Rate of change in percent: (p[i] - p[i-n]) / p[i-n] * 100.
List<double?> roc(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  for (var i = period; i < values.length; i++) {
    final base = values[i - period];
    if (base != 0) out[i] = (values[i] - base) / base * 100;
  }
  return out;
}

/// Least-squares slope of the last [period] values, normalized by price
/// (per-bar fractional slope * 100 → percent per bar).
List<double?> linregSlope(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (values.length < period) return out;
  var sx = 0.0, sxy = 0.0, sxx = 0.0, sy = 0.0;
  for (var x = 0; x < period; x++) {
    sx += x;
    sxy += x * values[x];
    sxx += x * x;
    sy += values[x];
  }
  final inv = 1 / period;
  final meanX = sx * inv;
  final meanY = sy * inv;
  double cov() => sxy * inv - meanX * meanY;
  double varX() => sxx * inv - meanX * meanX;
  final denom = varX();
  double slope = denom == 0 ? 0 : cov() / denom;
  if (values.length >= period) out[period - 1] = _normSlope(slope, meanY);
  for (var i = period; i < values.length; i++) {
    // Incremental recompute is fine at these scales.
    sx = 0;
    sxy = 0;
    sxx = 0;
    sy = 0;
    for (var x = 0; x < period; x++) {
      final v = values[i - period + 1 + x];
      sx += x;
      sxy += x * v;
      sxx += x * x;
      sy += v;
    }
    final mx = sx * inv;
    final my = sy * inv;
    final cv = sxy * inv - mx * my;
    final vx = sxx * inv - mx * mx;
    slope = vx == 0 ? 0 : cv / vx;
    out[i] = _normSlope(slope, my);
  }
  return out;
}

double _normSlope(double slope, double mean) => mean == 0 ? 0 : slope / mean * 100;

class DonchianResult {
  const DonchianResult({required this.upper, required this.lower, required this.mid});

  final List<double?> upper;
  final List<double?> lower;
  final List<double?> mid;
}

/// Donchian channel over the **previous** [period] bars (current bar excluded)
/// — i.e. a breakout reference: close[i] > upper[i] means a fresh N-bar high.
DonchianResult donchian(List<Candle> candles, {int period = 20}) {
  final n = candles.length;
  final up = List<double?>.filled(n, null);
  final lo = List<double?>.filled(n, null);
  final mid = List<double?>.filled(n, null);
  for (var i = period; i < n; i++) {
    var hh = -double.infinity;
    var ll = double.infinity;
    for (var j = i - period; j < i; j++) {
      hh = max(hh, candles[j].high);
      ll = min(ll, candles[j].low);
    }
    up[i] = hh;
    lo[i] = ll;
    mid[i] = (hh + ll) / 2;
  }
  return DonchianResult(upper: up, lower: lo, mid: mid);
}

void _checkPeriod(int period, int length) {
  if (period <= 0) {
    throw ArgumentError.value(period, 'period', 'must be > 0');
  }
  if (length == 0) {
    throw ArgumentError('empty series');
  }
}
