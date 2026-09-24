import '../data/models.dart';

/// Risk parameters — conservative defaults; everything is configurable.
class RiskConfig {
  const RiskConfig({
    this.riskPerTradePct = 0.75,
    this.maxOpenPositions = 3,
    this.maxExposurePct = 60,
    this.maxDailyLossPct = 2.0,
    this.stopLossAtrMult = 1.5,
    this.takeProfitAtrMult = 2.5,
    this.minConfidenceToTrade = 0.35,
    this.maxPositionPct = 25,
    this.allowShort = true,
    this.allowTradingWithoutData = false,
  });

  /// % of equity risked per trade (distance to stop).
  final double riskPerTradePct;

  final int maxOpenPositions;

  /// Max total exposure as % of equity.
  final double maxExposurePct;

  /// Halt for the day after losing this % of equity.
  final double maxDailyLossPct;

  final double stopLossAtrMult;
  final double takeProfitAtrMult;
  final double minConfidenceToTrade;

  /// Max single-position notional as % of equity.
  final double maxPositionPct;

  final bool allowShort;
  final bool allowTradingWithoutData;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'riskPerTradePct': riskPerTradePct,
        'maxOpenPositions': maxOpenPositions,
        'maxExposurePct': maxExposurePct,
        'maxDailyLossPct': maxDailyLossPct,
        'stopLossAtrMult': stopLossAtrMult,
        'takeProfitAtrMult': takeProfitAtrMult,
        'minConfidenceToTrade': minConfidenceToTrade,
        'maxPositionPct': maxPositionPct,
        'allowShort': allowShort,
        'allowTradingWithoutData': allowTradingWithoutData,
      };

  factory RiskConfig.fromJson(Map<String, dynamic> json) {
    const d = RiskConfig();
    return RiskConfig(
      riskPerTradePct:
          (json['riskPerTradePct'] as num?)?.toDouble() ?? d.riskPerTradePct,
      maxOpenPositions:
          (json['maxOpenPositions'] as int?) ?? d.maxOpenPositions,
      maxExposurePct:
          (json['maxExposurePct'] as num?)?.toDouble() ?? d.maxExposurePct,
      maxDailyLossPct:
          (json['maxDailyLossPct'] as num?)?.toDouble() ?? d.maxDailyLossPct,
      stopLossAtrMult:
          (json['stopLossAtrMult'] as num?)?.toDouble() ?? d.stopLossAtrMult,
      takeProfitAtrMult:
          (json['takeProfitAtrMult'] as num?)?.toDouble() ?? d.takeProfitAtrMult,
      minConfidenceToTrade:
          (json['minConfidenceToTrade'] as num?)?.toDouble() ??
              d.minConfidenceToTrade,
      maxPositionPct:
          (json['maxPositionPct'] as num?)?.toDouble() ?? d.maxPositionPct,
      allowShort: json['allowShort'] as bool? ?? d.allowShort,
      allowTradingWithoutData: json['allowTradingWithoutData'] as bool? ??
          d.allowTradingWithoutData,
    );
  }

  RiskConfig copyWith({
    double? riskPerTradePct,
    int? maxOpenPositions,
    double? maxExposurePct,
    double? maxDailyLossPct,
    double? stopLossAtrMult,
    double? takeProfitAtrMult,
    double? minConfidenceToTrade,
    double? maxPositionPct,
    bool? allowShort,
    bool? allowTradingWithoutData,
  }) =>
      RiskConfig(
        riskPerTradePct: riskPerTradePct ?? this.riskPerTradePct,
        maxOpenPositions: maxOpenPositions ?? this.maxOpenPositions,
        maxExposurePct: maxExposurePct ?? this.maxExposurePct,
        maxDailyLossPct: maxDailyLossPct ?? this.maxDailyLossPct,
        stopLossAtrMult: stopLossAtrMult ?? this.stopLossAtrMult,
        takeProfitAtrMult: takeProfitAtrMult ?? this.takeProfitAtrMult,
        minConfidenceToTrade: minConfidenceToTrade ?? this.minConfidenceToTrade,
        maxPositionPct: maxPositionPct ?? this.maxPositionPct,
        allowShort: allowShort ?? this.allowShort,
        allowTradingWithoutData:
            allowTradingWithoutData ?? this.allowTradingWithoutData,
      );
}

class RiskVerdict {
  const RiskVerdict.allowed({this.suggestedQty, this.stopPrice, this.targetPrice})
      : allowed = true,
        haltReason = null;

  const RiskVerdict.denied(this.haltReason)
      : allowed = false,
        suggestedQty = null,
        stopPrice = null,
        targetPrice = null;

  final bool allowed;
  final String? haltReason;
  final double? suggestedQty;
  final double? stopPrice;
  final double? targetPrice;
}

/// Position sizing (volatility-aware), exposure caps and the daily-loss
/// circuit breaker.
class RiskManager {
  RiskManager({required this.config});

  RiskConfig config;

  bool _haltedToday = false;
  String? _haltReason;
  String? _haltedDay;

  bool get isHalted => _haltedToday;
  String? get haltReason => _haltReason;

  /// Call once when the app day rolls over to re-arm the breaker.
  void checkNewDay(DateTime day) {
    final key = day.toIso8601String().substring(0, 10);
    if (_haltedDay != key) {
      _haltedDay = key;
      _haltedToday = false;
      _haltReason = null;
    }
  }

  /// Halt if today's realized+unrealized drawdown exceeds the limit.
  bool enforceDailyLoss({required double dayPnlPct, required DateTime day}) {
    checkNewDay(day);
    if (dayPnlPct <= -config.maxDailyLossPct) {
      _haltedToday = true;
      _haltReason =
          'daily loss limit hit (${dayPnlPct.toStringAsFixed(2)}% ≤ -${config.maxDailyLossPct}%)';
      return true;
    }
    return false;
  }

  void resetHalt() {
    _haltedToday = false;
    _haltReason = null;
  }

  /// Decide whether a new entry is allowed and compute size/stop/target.
  RiskVerdict entry({
    required AccountInfo account,
    required List<Position> positions,
    required double price,
    required double? atr,
    required Stance stance,
    required double confidence,
    required DateTime day,
  }) {
    checkNewDay(day);
    if (_haltedToday) {
      return RiskVerdict.denied('engine halted: $_haltReason');
    }
    if (account.isBlocked) {
      return RiskVerdict.denied('broker account is blocked');
    }
    if (confidence < config.minConfidenceToTrade) {
      return RiskVerdict.denied(
          'confidence ${(confidence * 100).round()}% below minimum '
          '${(config.minConfidenceToTrade * 100).round()}%');
    }
    if (stance == Stance.short && !config.allowShort) {
      return RiskVerdict.denied('short selling disabled');
    }
    if (positions.length >= config.maxOpenPositions) {
      return RiskVerdict.denied(
          'max open positions reached (${config.maxOpenPositions})');
    }

    final exposure = positions.fold<double>(0, (a, p) => a + p.marketValue);
    if (exposure / (account.equity == 0 ? 1 : account.equity) * 100 >=
        config.maxExposurePct) {
      return RiskVerdict.denied(
          'max exposure reached (${config.maxExposurePct.round()}%)');
    }

    final a = (atr != null && atr > 0) ? atr : price * 0.01;
    final stopDist = config.stopLossAtrMult * a;
    final stopPrice =
        stance == Stance.long ? price - stopDist : price + stopDist;
    final targetPrice = stance == Stance.long
        ? price + config.takeProfitAtrMult * a
        : price - config.takeProfitAtrMult * a;

    // Volatility sizing: risk `riskPerTradePct`% of equity across stop distance.
    final equity = account.equity <= 0 ? account.cash : account.equity;
    final riskDollars = equity * config.riskPerTradePct / 100;
    var qty = riskDollars / stopDist;
    if (qty <= 0) return RiskVerdict.denied('computed qty <= 0');

    // Cap notional: single-position + total exposure + buying power.
    final maxByPosition = (equity * config.maxPositionPct / 100) / price;
    final maxByExposure =
        ((equity * config.maxExposurePct / 100) - exposure) / price;
    final maxByBuyingPower = account.buyingPower / price;
    qty = [
      qty,
      maxByPosition,
      if (maxByExposure > 0) maxByExposure,
      if (maxByBuyingPower > 0) maxByBuyingPower,
    ].reduce((x, y) => x < y ? x : y);

    qty = qty.floorToDouble();
    if (qty < 1) {
      // Fall back to at least 1 share if equity allows (still within caps).
      if (1 <= maxByPosition && 1 <= maxByBuyingPower) {
        qty = 1;
      } else {
        return RiskVerdict.denied(
            'position too small (need ≥1 share within risk caps)');
      }
    }

    return RiskVerdict.allowed(
      suggestedQty: qty,
      stopPrice: stopPrice,
      targetPrice: targetPrice,
    );
  }
}
