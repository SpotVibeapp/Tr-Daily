import 'cost_gate.dart';

/// Smallest price step for a US stock: 1¢ at $1 and up, 0.01¢ below $1.
double tickSize(double price) => price >= 1 ? 0.01 : 0.0001;

/// What one side of a trade costs when no live quote is known: the larger of
/// [slippagePct] of the price and half a tick.
///
/// A flat 0.02% barely registers on a cheap stock. A $4 share that trades in
/// 1¢ steps really costs about half a cent each way (0.125%), and often more.
double sideCost(double price, double slippagePct) {
  if (price <= 0) return 0;
  final pct = price * slippagePct / 100;
  final halfTick = tickSize(price) / 2;
  return pct > halfTick ? pct : halfTick;
}

/// A simulated market fill. A buy pays the ask and a sell gets the bid when
/// [quote] is usable and close to [last]. It is never better than
/// [last] ± [sideCost]. Without a quote it is [last] ± [sideCost].
double simulatedFill({
  required double last,
  required bool isBuy,
  required double slippagePct,
  BidAsk? quote,
}) {
  final cost = sideCost(last, slippagePct);
  final base = isBuy ? last + cost : last - cost;
  if (quote == null || !quote.usable || last <= 0) return base;
  // A quote far from the last trade is stale or for another session. Do not
  // let it decide the fill.
  final mid = (quote.bid + quote.ask) / 2;
  if ((mid - last).abs() / last > 0.02) return base;
  if (isBuy) return quote.ask > base ? quote.ask : base;
  return quote.bid < base ? quote.bid : base;
}

/// One log line comparing a fill with the price the signal saw.
/// A positive cost means the fill was worse than the signal price.
String fillCostNote({
  required String symbol,
  required bool isBuy,
  required double qty,
  required double expected,
  required double filled,
}) {
  final perShare = isBuy ? filled - expected : expected - filled;
  final total = perShare * qty;
  final pct = expected > 0 ? perShare / expected * 100 : 0.0;
  final word = perShare >= 0 ? 'cost' : 'saved';
  final shares = qty == qty.roundToDouble()
      ? qty.toStringAsFixed(0)
      : qty.toStringAsFixed(4);
  return 'Fill ${isBuy ? 'BUY' : 'SELL'} $shares $symbol @ '
      '\$${filled.toStringAsFixed(filled < 1 ? 4 : 2)} vs signal '
      '\$${expected.toStringAsFixed(expected < 1 ? 4 : 2)} · $word '
      '\$${total.abs().toStringAsFixed(2)} (${pct.abs().toStringAsFixed(2)}%)';
}
