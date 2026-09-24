/// Core data models for Tr-Daily. Pure Dart (no Flutter) so the engine can be
/// reused by a CLI/server later.
library;

/// One OHLCV bar.
class Candle {
  const Candle({
    required this.symbol,
    required this.time,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  final String symbol;
  final DateTime time;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;

  /// Typical price (H+L+C)/3 — used for VWAP & ATR-ish calculations.
  double get typical => (high + low + close) / 3;

  double get range => high - low;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'symbol': symbol,
        'time': time.toIso8601String(),
        'open': open,
        'high': high,
        'low': low,
        'close': close,
        'volume': volume,
      };

  factory Candle.fromJson(Map<String, dynamic> json) => Candle(
        symbol: json['symbol'] as String,
        time: DateTime.parse(json['time'] as String),
        open: (json['open'] as num).toDouble(),
        high: (json['high'] as num).toDouble(),
        low: (json['low'] as num).toDouble(),
        close: (json['close'] as num).toDouble(),
        volume: (json['volume'] as num).toDouble(),
      );
}

/// Bar intervals the app works with.
enum BarInterval {
  oneMin('1m', Duration(minutes: 1)),
  fiveMin('5m', Duration(minutes: 5)),
  fifteenMin('15m', Duration(minutes: 15)),
  oneHour('1h', Duration(hours: 1)),
  oneDay('1d', Duration(days: 1));

  const BarInterval(this.code, this.duration);

  /// Common code used by Yahoo / Alpaca style APIs (day code differs per API,
  /// sources translate as needed).
  final String code;
  final Duration duration;
}

enum OrderSide { buy, sell }

enum OrderType { market, limit, stop, stopLimit }

enum TimeInForce { day, gtc, ioc, fok }

enum OrderStatus {
  new_,
  accepted,
  pendingNew,
  partiallyFilled,
  filled,
  canceled,
  rejected,
  expired,
  replaced,
  pendingCancel,
  unknown;

  static OrderStatus parse(String? raw) {
    switch ((raw ?? '').toLowerCase()) {
      case 'new':
        return OrderStatus.new_;
      case 'accepted':
        return OrderStatus.accepted;
      case 'pending_new':
        return OrderStatus.pendingNew;
      case 'partially_filled':
        return OrderStatus.partiallyFilled;
      case 'filled':
        return OrderStatus.filled;
      case 'canceled':
      case 'cancelled':
        return OrderStatus.canceled;
      case 'rejected':
        return OrderStatus.rejected;
      case 'expired':
        return OrderStatus.expired;
      case 'replaced':
        return OrderStatus.replaced;
      case 'pending_cancel':
        return OrderStatus.pendingCancel;
      default:
        return OrderStatus.unknown;
    }
  }

  bool get isOpen =>
      this == OrderStatus.new_ ||
      this == OrderStatus.accepted ||
      this == OrderStatus.pendingNew ||
      this == OrderStatus.partiallyFilled ||
      this == OrderStatus.pendingCancel;
}

/// Request to place an order. Provide [qty] (shares) or [notional] (dollars).
class OrderRequest {
  const OrderRequest({
    required this.symbol,
    required this.side,
    required this.type,
    this.qty,
    this.notional,
    this.limitPrice,
    this.stopPrice,
    this.timeInForce = TimeInForce.day,
    this.clientOrderId,
    this.takeProfit,
    this.stopLoss,
  });

  final String symbol;
  final OrderSide side;
  final OrderType type;
  final double? qty;
  final double? notional;
  final double? limitPrice;
  final double? stopPrice;
  final TimeInForce timeInForce;
  final String? clientOrderId;

  /// Optional bracket prices — supported natively by Alpaca, emulated by the
  /// paper broker.
  final double? takeProfit;
  final double? stopLoss;
}

/// An order as reported by a broker.
class Order {
  const Order({
    required this.id,
    required this.symbol,
    required this.side,
    required this.type,
    required this.status,
    this.qty,
    this.filledQty = 0,
    this.limitPrice,
    this.stopPrice,
    this.filledAvgPrice,
    this.clientOrderId,
    required this.submittedAt,
    this.filledAt,
  });

  final String id;
  final String symbol;
  final OrderSide side;
  final OrderType type;
  final OrderStatus status;
  final double? qty;
  final double filledQty;
  final double? limitPrice;
  final double? stopPrice;
  final double? filledAvgPrice;
  final String? clientOrderId;
  final DateTime submittedAt;
  final DateTime? filledAt;

  bool get isDone =>
      status == OrderStatus.filled ||
      status == OrderStatus.canceled ||
      status == OrderStatus.rejected ||
      status == OrderStatus.expired;
}

/// An open (or closed) position.
class Position {
  const Position({
    required this.symbol,
    required this.qty,
    required this.avgEntryPrice,
    required this.currentPrice,
    this.short = false,
    this.realizedPnl = 0,
  });

  final String symbol;
  final double qty;
  final double avgEntryPrice;
  final double currentPrice;
  final bool short;
  final double realizedPnl;

  double get marketValue => qty * currentPrice;
  double get costBasis => qty * avgEntryPrice;
  double get unrealizedPnl => short ? (avgEntryPrice - currentPrice) * qty : (currentPrice - avgEntryPrice) * qty;
  double get unrealizedPnlPct {
    if (costBasis == 0) return 0;
    return unrealizedPnl / costBasis.abs() * 100;
  }
}

/// Broker account snapshot.
class AccountInfo {
  const AccountInfo({
    required this.equity,
    required this.cash,
    required this.buyingPower,
    required this.dayTradeCount,
    this.dayPnl = 0,
    this.lastEquity,
    this.isBlocked = false,
  });

  final double equity;
  final double cash;
  final double buyingPower;
  final int dayTradeCount;
  final double dayPnl;
  final double? lastEquity;
  final bool isBlocked;

  double get dayPnlPct {
    final base = lastEquity;
    if (base == null || base == 0) return 0;
    return (equity - base) / base * 100;
  }

  AccountInfo copyWith({
    double? equity,
    double? cash,
    double? buyingPower,
    int? dayTradeCount,
    double? dayPnl,
    double? lastEquity,
    bool? isBlocked,
  }) =>
      AccountInfo(
        equity: equity ?? this.equity,
        cash: cash ?? this.cash,
        buyingPower: buyingPower ?? this.buyingPower,
        dayTradeCount: dayTradeCount ?? this.dayTradeCount,
        dayPnl: dayPnl ?? this.dayPnl,
        lastEquity: lastEquity ?? this.lastEquity,
        isBlocked: isBlocked ?? this.isBlocked,
      );
}

/// Trade side used by the strategy engine (long = +1, short = -1, flat = 0).
enum Stance { long, short, flat }

/// A scored, explainable trade signal for one symbol.
class SignalScore {
  const SignalScore({
    required this.symbol,
    required this.score,
    required this.confidence,
    required this.stance,
    required this.reasons,
    required this.price,
    required this.generatedAt,
    this.mlProbability,
    this.suggestedStop,
    this.suggestedTarget,
    this.breakdown = const <String, double>{},
  });

  final String symbol;

  /// Composite score in [-1, 1]: negative = bearish, positive = bullish.
  final double score;

  /// Model/ensemble agreement in [0, 1].
  final double confidence;
  final Stance stance;
  final List<String> reasons;
  final double price;
  final DateTime generatedAt;

  /// Probability that the next bar is up, when the online-ML model has data.
  final double? mlProbability;
  final double? suggestedStop;
  final double? suggestedTarget;

  /// Per-signal contributions for explainability (name -> raw value in [-1,1]).
  final Map<String, double> breakdown;

  int get scorePct => (score * 100).round().clamp(-100, 100);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'symbol': symbol,
        'score': score,
        'confidence': confidence,
        'stance': stance.name,
        'reasons': reasons,
        'price': price,
        'generatedAt': generatedAt.toIso8601String(),
        'mlProbability': mlProbability,
        'suggestedStop': suggestedStop,
        'suggestedTarget': suggestedTarget,
        'breakdown': breakdown,
      };
}

/// A completed (or open) strategy trade used by backtests & the trade log.
class StrategyTrade {
  const StrategyTrade({
    required this.symbol,
    required this.side,
    required this.entryTime,
    required this.entryPrice,
    required this.qty,
    required this.exitTime,
    required this.exitPrice,
    required this.exitReason,
    this.fees = 0,
  });

  final String symbol;
  final Stance side;
  final DateTime entryTime;
  final double entryPrice;
  final double qty;
  final DateTime? exitTime;
  final double? exitPrice;
  final String exitReason;
  final double fees;

  bool get isOpen => exitTime == null;

  double get grossPnl {
    if (exitPrice == null) return 0;
    final dir = side == Stance.short ? -1.0 : 1.0;
    return (exitPrice! - entryPrice) * qty * dir - fees;
  }

  double get pnlPct {
    if (exitPrice == null || entryPrice == 0) return 0;
    return grossPnl / (entryPrice * qty) * 100;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'symbol': symbol,
        'side': side.name,
        'entryTime': entryTime.toIso8601String(),
        'entryPrice': entryPrice,
        'qty': qty,
        'exitTime': exitTime?.toIso8601String(),
        'exitPrice': exitPrice,
        'exitReason': exitReason,
        'fees': fees,
        'pnl': grossPnl,
      };

  factory StrategyTrade.fromJson(Map<String, dynamic> json) => StrategyTrade(
        symbol: json['symbol'] as String,
        side: Stance.values.firstWhere((s) => s.name == json['side']),
        entryTime: DateTime.parse(json['entryTime'] as String),
        entryPrice: (json['entryPrice'] as num).toDouble(),
        qty: (json['qty'] as num).toDouble(),
        exitTime: json['exitTime'] == null
            ? null
            : DateTime.parse(json['exitTime'] as String),
        exitPrice: (json['exitPrice'] as num?)?.toDouble(),
        exitReason: (json['exitReason'] as String?) ?? 'unknown',
        fees: (json['fees'] as num?)?.toDouble() ?? 0,
      );
}
