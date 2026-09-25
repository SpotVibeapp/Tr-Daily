import '../data/models.dart';

/// Minutes in the regular US session (09:30–16:00 ET).
const int regularSessionMinutes = 390;

/// Rough share of US consolidated volume that prints on IEX. Alpaca's free
/// data feed only reports IEX trades, so its volume reads far lower than the
/// whole market's. The dollar-volume floor is scaled by this on that feed.
const double iexVolumeShare = 0.02;

/// Bars that make up one regular session at [interval].
int barsPerSession(BarInterval interval) {
  final minutes = interval.duration.inMinutes;
  if (interval == BarInterval.oneDay || minutes <= 0) return 1;
  final n = (regularSessionMinutes / minutes).round();
  return n < 1 ? 1 : n;
}

/// Estimated dollars traded in one regular session: the average
/// close × volume over the most recent session's worth of bars, times the
/// bars in a session. Null when there is nothing to measure.
double? sessionDollarVolume(List<Candle> bars, BarInterval interval) {
  if (bars.isEmpty) return null;
  final n = barsPerSession(interval);
  final recent = bars.length > n ? bars.sublist(bars.length - n) : bars;
  var total = 0.0;
  for (final b in recent) {
    total += b.close * b.volume;
  }
  return total / recent.length * n;
}

/// $1,234,567 → "$1.2M", $85,000 → "$85k", $950 → "$950".
String compactDollars(double v) {
  final a = v.abs();
  if (a >= 1e9) return '\$${(v / 1e9).toStringAsFixed(1)}B';
  if (a >= 1e6) return '\$${(v / 1e6).toStringAsFixed(1)}M';
  if (a >= 1e3) return '\$${(v / 1e3).toStringAsFixed(0)}k';
  return '\$${v.toStringAsFixed(0)}';
}

/// Why a new trade in this name should be skipped for liquidity, or null.
///
/// Thin names fill badly: wide spreads, gaps, and stops that slip. A price
/// floor also keeps sub-dollar stocks out, where a 1¢ move is a large
/// percentage. Held positions are still managed; this only gates entries.
String? liquiditySkipReason({
  required double price,
  required double? sessionDollarVolume,
  required String sourceId,
  required double minSharePrice,
  required double minDollarVolume,
}) {
  if (minSharePrice > 0 && price < minSharePrice) {
    return 'share price is under the \$${minSharePrice.toStringAsFixed(2)} floor';
  }
  if (minDollarVolume <= 0) return null;
  final iexOnly = sourceId.toLowerCase() == 'alpaca';
  final need = iexOnly ? minDollarVolume * iexVolumeShare : minDollarVolume;
  final seen = sessionDollarVolume;
  if (seen == null) return 'trading volume could not be read';
  if (seen < need) {
    return iexOnly
        ? 'thinly traded (under ${compactDollars(need)} a session on IEX, '
            'about ${compactDollars(minDollarVolume)} market-wide)'
        : 'thinly traded (under ${compactDollars(need)} a session)';
  }
  return null;
}
