import '../data/models.dart';

/// A real bid and ask. A missing or crossed quote is not treated as a tight spread.
class BidAsk {
  const BidAsk({required this.bid, required this.ask});

  final double bid;
  final double ask;

  double get spread => ask - bid;

  bool get usable =>
      bid > 0 && ask > 0 && ask + 1e-9 >= bid && spread >= 0 && spread < ask;

  static BidAsk? tryMake(num? bid, num? ask) {
    if (bid == null || ask == null) return null;
    final quote = BidAsk(bid: bid.toDouble(), ask: ask.toDouble());
    return quote.usable ? quote : null;
  }
}

/// Skip a new entry when the spread is a large part of the profit-point
/// distance. [maxSpreadOfTarget] is a fraction. 0 turns the gate off.
/// A missing quote is a skip: the app does not guess that the market is tight.
String? spreadSkipReason({
  required BidAsk? quote,
  required double price,
  required double? targetPrice,
  required double maxSpreadOfTarget,
}) {
  if (maxSpreadOfTarget <= 0) return null;
  if (quote == null || !quote.usable) {
    return 'spread not readable, so a wide market was not guessed';
  }
  final distance = targetPrice == null ? 0.0 : (targetPrice - price).abs();
  if (price <= 0 || distance <= 0) {
    return 'no profit-point distance to compare with the spread';
  }
  final fraction = quote.spread / distance;
  if (fraction + 1e-9 >= maxSpreadOfTarget) {
    final pct = (fraction * 100).round();
    final cap = (maxSpreadOfTarget * 100).round();
    return 'spread \$${quote.spread.toStringAsFixed(2)} is $pct% of the '
        '\$${distance.toStringAsFixed(2)} profit-point distance (limit $cap%)';
  }
  return null;
}

/// Buy at the ask, sell at the bid. Null when that price would be a guess.
double? touchLimit({required OrderSide side, required BidAsk? quote}) {
  if (quote == null || !quote.usable) return null;
  return side == OrderSide.buy ? quote.ask : quote.bid;
}

/// Regular session may use a market order, and that order is not marked
/// extended. Outside the regular session a market order is never built.
/// A limit is returned only when a real bid/ask can price it.
OrderRequest? sessionOrder({
  required String symbol,
  required OrderSide side,
  required double qty,
  required bool regularSession,
  required BidAsk? quote,
  required bool allowOutside,
  required bool extendedHours,
  double? takeProfit,
  double? stopLoss,
}) {
  if (qty <= 0) return null;
  if (regularSession) {
    return OrderRequest(
      symbol: symbol,
      side: side,
      type: OrderType.market,
      qty: qty,
      takeProfit: takeProfit,
      stopLoss: stopLoss,
      extendedHours: false,
    );
  }
  if (!allowOutside) return null;
  final limit = touchLimit(side: side, quote: quote);
  if (limit == null) return null;
  return OrderRequest(
    symbol: symbol,
    side: side,
    type: OrderType.limit,
    qty: qty,
    limitPrice: limit,
    timeInForce: TimeInForce.day,
    extendedHours: extendedHours,
  );
}

Map<String, BidAsk> parseYahooQuotes(Object? root) {
  if (root is! Map) return const <String, BidAsk>{};
  final response = root['quoteResponse'];
  final rows = response is Map ? response['result'] : null;
  if (rows is! List) return const <String, BidAsk>{};
  final out = <String, BidAsk>{};
  for (final row in rows) {
    if (row is! Map) continue;
    final symbol = row['symbol']?.toString().toUpperCase();
    final quote = BidAsk.tryMake(_num(row['bid']), _num(row['ask']));
    if (symbol == null || symbol.isEmpty || quote == null) continue;
    out[symbol] = quote;
  }
  return out;
}

Map<String, BidAsk> parseAlpacaQuotes(Object? root) {
  if (root is! Map) return const <String, BidAsk>{};
  final nested = root['snapshots'];
  final raw = nested is Map ? nested : root;
  final out = <String, BidAsk>{};
  raw.forEach((key, value) {
    if (value is! Map) return;
    final latest = value['latestQuote'] ?? value['quote'];
    if (latest is! Map) return;
    final quote = BidAsk.tryMake(
      _num(latest['bp']) ?? _num(latest['bid']),
      _num(latest['ap']) ?? _num(latest['ask']),
    );
    if (quote == null) return;
    out[key.toString().toUpperCase()] = quote;
  });
  return out;
}

num? _num(Object? value) => value is num ? value : null;
