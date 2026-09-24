import '../data/models.dart';
import 'alpaca_broker.dart';

/// Simple in-memory trade record kept by the paper broker (and used as the
/// local trade log).
class PaperFill {
  const PaperFill({
    required this.id,
    required this.symbol,
    required this.side,
    required this.qty,
    required this.price,
    required this.time,
    required this.realizedPnl,
  });

  final String id;
  final String symbol;
  final OrderSide side;
  final double qty;
  final double price;
  final DateTime time;

  /// Realized PnL when this fill closed (or reduced) a position.
  final double realizedPnl;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'symbol': symbol,
        'side': side.name,
        'qty': qty,
        'price': price,
        'time': time.toIso8601String(),
        'realizedPnl': realizedPnl,
      };

  factory PaperFill.fromJson(Map<String, dynamic> json) => PaperFill(
        id: json['id'] as String,
        symbol: json['symbol'] as String,
        side: json['side'] == 'sell' ? OrderSide.sell : OrderSide.buy,
        qty: (json['qty'] as num).toDouble(),
        price: (json['price'] as num).toDouble(),
        time: DateTime.parse(json['time'] as String),
        realizedPnl: (json['realizedPnl'] as num?)?.toDouble() ?? 0,
      );
}

/// Local simulated broker: market orders fill instantly at [lastPrice] plus a
/// configurable slippage; tracks cash, average cost and realized PnL.
///
/// Persisted entirely through [toJson]/[fromJson] by AppState — no platform
/// channels, so it's fully unit-testable.
class PaperBroker implements Broker {
  PaperBroker({
    double startingCash = 25000,
    this.slippagePct = 0.02,
    this.feePerShare = 0.0,
    double? equity,
    List<Position>? positions,
    List<PaperFill>? fills,
    DateTime? lastEquityDay,
  })  : cash = startingCash,
        _equity = equity ?? startingCash,
        _positions = positions ?? <Position>[],
        fills = fills ?? <PaperFill>[],
        _lastEquityDay = lastEquityDay {
    _dayStartEquity = _equity;
  }

  double cash;
  double _equity;
  final double slippagePct;
  final double feePerShare;
  final List<Position> _positions;
  final List<PaperFill> fills;
  DateTime? _lastEquityDay;

  /// Latest known price per symbol (fed by the engine each scan cycle).
  final Map<String, double> lastPrice = <String, double>{};

  double _dayStartEquity = 0;
  int _orderSeq = 0;

  @override
  String get id => 'paper';

  @override
  BrokerMode get mode => BrokerMode.paper;

  void setPrice(String symbol, double price) {
    lastPrice[symbol.toUpperCase()] = price;
    // Mark positions to market.
    for (var i = 0; i < _positions.length; i++) {
      final p = _positions[i];
      if (p.symbol == symbol.toUpperCase()) {
        _positions[i] = Position(
          symbol: p.symbol,
          qty: p.qty,
          avgEntryPrice: p.avgEntryPrice,
          currentPrice: price,
          short: p.short,
          realizedPnl: p.realizedPnl,
        );
      }
    }
    _recomputeEquity();
  }

  void _recomputeEquity() {
    var total = cash;
    for (final p in _positions) {
      // Longs add market value; shorts were already credited to [cash] at
      // entry, so equity is reduced by what it costs to buy them back.
      total += p.short ? -p.marketValue : p.marketValue;
    }
    _equity = total;
  }

  /// Called on day change to refresh the day-PnL baseline.
  void rollDay(DateTime day) {
    final last = _lastEquityDay;
    if (last == null ||
        last.year != day.year ||
        last.month != day.month ||
        last.day != day.day) {
      _lastEquityDay = day;
      _dayStartEquity = _equity;
    }
  }

  @override
  Future<AccountInfo> getAccount() async {
    // Equity already marks positions to market, so day PnL = drift since the
    // day-start baseline (realized + unrealized combined).
    return AccountInfo(
      equity: _equity,
      cash: cash,
      buyingPower: cash, // no margin in the simulator
      dayTradeCount: 0,
      dayPnl: _equity - _dayStartEquity,
      lastEquity: _dayStartEquity,
      isBlocked: false,
    );
  }

  @override
  Future<List<Position>> getPositions() async => List<Position>.unmodifiable(_positions);

  @override
  Future<List<Order>> getOpenOrders() async => <Order>[];

  /// Paper fills are immediate — reconstructed from the fill log.
  @override
  Future<Order?> getOrder(String orderId) async {
    final fill = fills.where((f) => f.id == orderId).firstOrNull;
    if (fill == null) return null;
    return Order(
      id: fill.id,
      symbol: fill.symbol,
      side: fill.side,
      type: OrderType.market,
      status: OrderStatus.filled,
      qty: fill.qty,
      filledQty: fill.qty,
      filledAvgPrice: fill.price,
      submittedAt: fill.time,
      filledAt: fill.time,
    );
  }

  @override
  Future<void> cancelOrder(String orderId) async {}

  @override
  Future<bool> healthCheck() async => true;

  @override
  Future<void> closePosition(String symbol) async {
    final sym = symbol.toUpperCase();
    final p = _positions.where((p) => p.symbol == sym).firstOrNull;
    if (p == null) return;
    await submitOrder(OrderRequest(
      symbol: sym,
      side: p.short ? OrderSide.buy : OrderSide.sell,
      type: OrderType.market,
      qty: p.qty,
    ));
  }

  @override
  Future<Order> submitOrder(OrderRequest request) async {
    final sym = request.symbol.toUpperCase();
    final px = lastPrice[sym];
    if (px == null) {
      throw StateError('no market price for $sym — engine must scan first');
    }
    final isBuy = request.side == OrderSide.buy;

    // Determine share count (notional orders convert to shares).
    double qty;
    if (request.qty != null && request.qty! > 0) {
      qty = request.qty!;
    } else if (request.notional != null && request.notional! > 0) {
      qty = request.notional! / px;
    } else {
      throw ArgumentError('qty or notional required');
    }
    if (request.type == OrderType.limit && request.limitPrice != null) {
      // Simplified fill: fill limit only when marketable at requested price.
      final lp = request.limitPrice!;
      final marketable = isBuy ? px <= lp : px >= lp;
      if (!marketable) {
        return Order(
          id: _newId(),
          symbol: sym,
          side: request.side,
          type: request.type,
          status: OrderStatus.new_,
          qty: qty,
          limitPrice: lp,
          submittedAt: DateTime.now(),
        );
      }
    }

    final slip = px * slippagePct / 100;
    final fillPx = isBuy ? px + slip : px - slip;
    final notional = fillPx * qty;

    final existing = _positions.where((p) => p.symbol == sym).firstOrNull;
    final goingLong = isBuy;
    var realized = 0.0;

    if (existing != null && existing.short == goingLong) {
      // Increase position.
      final newQty = existing.qty + qty;
      final newAvg =
          (existing.avgEntryPrice * existing.qty + fillPx * qty) / newQty;
      _replacePosition(existing, Position(
        symbol: sym,
        qty: newQty,
        avgEntryPrice: newAvg,
        currentPrice: px,
        short: existing.short,
      ));
      cash = isBuy ? cash - notional : cash + notional;
    } else if (existing != null) {
      // Reduce / flip.
      final closeQty = qty < existing.qty ? qty : existing.qty;
      final dir = existing.short ? 1.0 : -1.0; // profit if price moved against entry
      realized = (fillPx - existing.avgEntryPrice) * closeQty * dir;
      cash += isBuy ? -notional : notional;
      // For a short, entering (sell) credits cash; covering debits.
      if (existing.short) {
        // existing.short && buying to cover: cash decreases by notional (already applied above).
      }
      final remaining = existing.qty - closeQty;
      if (remaining > 0.000001) {
        _replacePosition(existing, Position(
          symbol: sym,
          qty: remaining,
          avgEntryPrice: existing.avgEntryPrice,
          currentPrice: px,
          short: existing.short,
          realizedPnl: existing.realizedPnl + realized,
        ));
      } else if (qty > closeQty + 0.000001) {
        // Flipped: remainder opens the opposite position.
        final flipQty = qty - closeQty;
        _replacePosition(existing, Position(
          symbol: sym,
          qty: flipQty,
          avgEntryPrice: fillPx,
          currentPrice: px,
          short: !goingLong,
          realizedPnl: existing.realizedPnl + realized,
        ));
      } else {
        _positions.remove(existing);
      }
    } else {
      // Fresh position. Short sale credits cash.
      if (!isBuy && !_allowShort) {
        throw StateError('short selling disabled in paper settings');
      }
      cash += isBuy ? -notional : notional;
      _positions.add(Position(
        symbol: sym,
        qty: qty,
        avgEntryPrice: fillPx,
        currentPrice: px,
        short: !goingLong,
      ));
    }

    if (feePerShare > 0) {
      final fees = feePerShare * qty;
      cash -= fees;
    }

    fills.add(PaperFill(
      id: _newId(),
      symbol: sym,
      side: request.side,
      qty: qty,
      price: fillPx,
      time: DateTime.now(),
      realizedPnl: realized,
    ));
    _recomputeEquity();

    return Order(
      id: fills.last.id,
      symbol: sym,
      side: request.side,
      type: request.type,
      status: OrderStatus.filled,
      qty: qty,
      filledQty: qty,
      filledAvgPrice: fillPx,
      clientOrderId: request.clientOrderId,
      submittedAt: DateTime.now(),
      filledAt: DateTime.now(),
    );
  }

  bool _allowShort = true;

  /// Configure shorting (called from settings).
  void setAllowShort(bool allow) => _allowShort = allow;

  void _replacePosition(Position old, Position next) {
    final i = _positions.indexOf(old);
    if (i >= 0) _positions[i] = next;
  }

  String _newId() => 'paper-${DateTime.now().microsecondsSinceEpoch}-${++_orderSeq}';

  // ---- persistence -------------------------------------------------------

  Map<String, dynamic> toJson() => <String, dynamic>{
        'cash': cash,
        'equity': _equity,
        'dayStartEquity': _dayStartEquity,
        'lastEquityDay': _lastEquityDay?.toIso8601String(),
        'slippagePct': slippagePct,
        'feePerShare': feePerShare,
        'lastPrice': lastPrice,
        'positions': _positions
            .map((p) => <String, dynamic>{
                  'symbol': p.symbol,
                  'qty': p.qty,
                  'avgEntryPrice': p.avgEntryPrice,
                  'currentPrice': p.currentPrice,
                  'short': p.short,
                  'realizedPnl': p.realizedPnl,
                })
            .toList(),
        'fills': fills.map((f) => f.toJson()).toList(),
      };

  factory PaperBroker.fromJson(Map<String, dynamic> json) {
    final positions = <Position>[
      for (final p in (json['positions'] as List<dynamic>? ?? <dynamic>[]))
        Position(
          symbol: (p as Map<String, dynamic>)['symbol'] as String,
          qty: (p['qty'] as num).toDouble(),
          avgEntryPrice: (p['avgEntryPrice'] as num).toDouble(),
          currentPrice: (p['currentPrice'] as num).toDouble(),
          short: p['short'] as bool? ?? false,
          realizedPnl: (p['realizedPnl'] as num?)?.toDouble() ?? 0,
        )
    ];
    final fills = <PaperFill>[
      for (final f in (json['fills'] as List<dynamic>? ?? <dynamic>[]))
        PaperFill.fromJson(f as Map<String, dynamic>)
    ];
    final broker = PaperBroker(
      startingCash: (json['cash'] as num?)?.toDouble() ?? 25000,
      equity: (json['equity'] as num?)?.toDouble(),
      positions: positions,
      fills: fills,
      lastEquityDay: json['lastEquityDay'] == null
          ? null
          : DateTime.tryParse(json['lastEquityDay'] as String),
    );
    final lp = json['lastPrice'];
    if (lp is Map<String, dynamic>) {
      lp.forEach((k, v) => broker.lastPrice[k.toString()] = (v as num).toDouble());
    }
    final ds = json['dayStartEquity'];
    if (ds != null) broker._dayStartEquity = (ds as num).toDouble();
    return broker;
  }
}
