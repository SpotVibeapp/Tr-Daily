import '../data/models.dart';

/// Risk parameters — conservative defaults; everything is configurable.
class RiskConfig {
  const RiskConfig({
    this.riskPerTradePct = 0.5,
    this.maxOpenPositions = 1,
    this.maxExposurePct = 60,
    this.maxDailyLossPct = 2.0,
    this.dailyProfitGoalPct = 30.0,
    this.letWinnersRun = false,
    this.maxSpreadOfTarget = 0.25,
    this.stopLossAtrMult = 1.5,
    this.takeProfitAtrMult = 2.5,
    this.minConfidenceToTrade = 0.35,
    this.maxPositionPct = 25,
    this.allowShort = true,
    this.allowTradingWithoutData = false,
    this.trailingStopAtrMult = 2.0,
    this.trailingActivateAtrMult = 1.0,
    this.scaleOutEnabled = true,
    this.scaleOutAtAtrMult = 1.5,
    this.scaleOutFraction = 0.5,
  });

  /// % of equity risked per trade (distance to stop). 0.5% by default: a
  /// small first live account should find out how real fills compare with
  /// paper before it risks more.
  final double riskPerTradePct;

  /// One position at a time by default, for the same reason.
  final int maxOpenPositions;

  /// Max total exposure as % of equity.
  final double maxExposurePct;

  /// Halt for the day after losing this % of equity.
  final double maxDailyLossPct;

  /// A daily profit milestone. Reaching it does not halt, size up, or refuse
  /// a later gain. 0 disables the milestone.
  final double dailyProfitGoalPct;

  /// When true, the profit point locks a stop instead of selling the whole
  /// trade, so a further move can stay open.
  final bool letWinnersRun;

  /// Skip a new trade when the bid-ask spread is at least this fraction of
  /// the profit-point distance. 0 disables the gate.
  final double maxSpreadOfTarget;

  final double stopLossAtrMult;
  final double takeProfitAtrMult;
  final double minConfidenceToTrade;

  /// Max single-position notional as % of equity.
  final double maxPositionPct;

  final bool allowShort;
  final bool allowTradingWithoutData;

  /// Trail price at [trailingStopAtrMult] × ATR behind the best price since
  /// entry, activated once the position is [trailingActivateAtrMult] × ATR
  /// in profit. 0 disables.
  final double trailingStopAtrMult;
  final double trailingActivateAtrMult;

  /// Scale out (take partial profit) at [scaleOutAtAtrMult] × ATR, selling
  /// [scaleOutFraction] of the position.
  final bool scaleOutEnabled;
  final double scaleOutAtAtrMult;
  final double scaleOutFraction;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'riskPerTradePct': riskPerTradePct,
        'maxOpenPositions': maxOpenPositions,
        'maxExposurePct': maxExposurePct,
        'maxDailyLossPct': maxDailyLossPct,
        'dailyProfitGoalPct': dailyProfitGoalPct,
        'letWinnersRun': letWinnersRun,
        'maxSpreadOfTarget': maxSpreadOfTarget,
        'stopLossAtrMult': stopLossAtrMult,
        'takeProfitAtrMult': takeProfitAtrMult,
        'minConfidenceToTrade': minConfidenceToTrade,
        'maxPositionPct': maxPositionPct,
        'allowShort': allowShort,
        'allowTradingWithoutData': allowTradingWithoutData,
        'trailingStopAtrMult': trailingStopAtrMult,
        'trailingActivateAtrMult': trailingActivateAtrMult,
        'scaleOutEnabled': scaleOutEnabled,
        'scaleOutAtAtrMult': scaleOutAtAtrMult,
        'scaleOutFraction': scaleOutFraction,
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
      dailyProfitGoalPct: (json['dailyProfitGoalPct'] as num?)?.toDouble() ??
          d.dailyProfitGoalPct,
      letWinnersRun: json['letWinnersRun'] as bool? ?? d.letWinnersRun,
      maxSpreadOfTarget: (json['maxSpreadOfTarget'] as num?)?.toDouble() ??
          d.maxSpreadOfTarget,
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
      trailingStopAtrMult:
          (json['trailingStopAtrMult'] as num?)?.toDouble() ??
              d.trailingStopAtrMult,
      trailingActivateAtrMult:
          (json['trailingActivateAtrMult'] as num?)?.toDouble() ??
              d.trailingActivateAtrMult,
      scaleOutEnabled: json['scaleOutEnabled'] as bool? ?? d.scaleOutEnabled,
      scaleOutAtAtrMult:
          (json['scaleOutAtAtrMult'] as num?)?.toDouble() ??
              d.scaleOutAtAtrMult,
      scaleOutFraction: (json['scaleOutFraction'] as num?)?.toDouble() ??
          d.scaleOutFraction,
    );
  }

  RiskConfig copyWith({
    double? riskPerTradePct,
    int? maxOpenPositions,
    double? maxExposurePct,
    double? maxDailyLossPct,
    double? dailyProfitGoalPct,
    bool? letWinnersRun,
    double? maxSpreadOfTarget,
    double? stopLossAtrMult,
    double? takeProfitAtrMult,
    double? minConfidenceToTrade,
    double? maxPositionPct,
    bool? allowShort,
    bool? allowTradingWithoutData,
    double? trailingStopAtrMult,
    double? trailingActivateAtrMult,
    bool? scaleOutEnabled,
    double? scaleOutAtAtrMult,
    double? scaleOutFraction,
  }) =>
      RiskConfig(
        riskPerTradePct: riskPerTradePct ?? this.riskPerTradePct,
        maxOpenPositions: maxOpenPositions ?? this.maxOpenPositions,
        maxExposurePct: maxExposurePct ?? this.maxExposurePct,
        maxDailyLossPct: maxDailyLossPct ?? this.maxDailyLossPct,
        dailyProfitGoalPct: dailyProfitGoalPct ?? this.dailyProfitGoalPct,
        letWinnersRun: letWinnersRun ?? this.letWinnersRun,
        maxSpreadOfTarget: maxSpreadOfTarget ?? this.maxSpreadOfTarget,
        stopLossAtrMult: stopLossAtrMult ?? this.stopLossAtrMult,
        takeProfitAtrMult: takeProfitAtrMult ?? this.takeProfitAtrMult,
        minConfidenceToTrade: minConfidenceToTrade ?? this.minConfidenceToTrade,
        maxPositionPct: maxPositionPct ?? this.maxPositionPct,
        allowShort: allowShort ?? this.allowShort,
        allowTradingWithoutData:
            allowTradingWithoutData ?? this.allowTradingWithoutData,
        trailingStopAtrMult:
            trailingStopAtrMult ?? this.trailingStopAtrMult,
        trailingActivateAtrMult:
            trailingActivateAtrMult ?? this.trailingActivateAtrMult,
        scaleOutEnabled: scaleOutEnabled ?? this.scaleOutEnabled,
        scaleOutAtAtrMult: scaleOutAtAtrMult ?? this.scaleOutAtAtrMult,
        scaleOutFraction: scaleOutFraction ?? this.scaleOutFraction,
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

/// Highest price at which one whole share still fits the single-position
/// cap and the broker's buying power. Zero means "do not open a new share".
///
/// Buying power of zero is not replaced with equity — a broker that reports
/// no buying power will reject the order, and sizing as if it wouldn't is
/// how a small account gets a surprise rejection (or, worse, a size the
/// cash cannot cover).
double maxAffordableSharePrice(
  AccountInfo account,
  RiskConfig config, {
  double? sizingEquity,
}) {
  final equity = (sizingEquity != null && sizingEquity > 0)
      ? sizingEquity
      : (account.equity <= 0 ? account.cash : account.equity);
  if (equity <= 0 || config.maxPositionPct <= 0) return 0;
  if (account.buyingPower <= 0) return 0;
  final byPosition = equity * config.maxPositionPct / 100;
  return byPosition < account.buyingPower ? byPosition : account.buyingPower;
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
    double? sizingEquity,
    double? riskPerTradePct,
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

    // Same gate as the 1-share fallback below, but with a reason a person
    // can act on: the name is too expensive for this account, not "qty <= 0".
    final maxShare = maxAffordableSharePrice(
      account,
      config,
      sizingEquity: sizingEquity,
    );
    if (maxShare <= 0) {
      return RiskVerdict.denied('no buying power for a new share');
    }
    if (price > maxShare + 1e-6) {
      return RiskVerdict.denied(
        'one share (\$${price.toStringAsFixed(2)}) exceeds budget '
        '(max \$${maxShare.toStringAsFixed(2)}, '
        '${config.maxPositionPct.round()}% of equity or buying power)',
      );
    }

    final a = (atr != null && atr > 0) ? atr : price * 0.01;
    final stopDist = config.stopLossAtrMult * a;
    final stopPrice =
        stance == Stance.long ? price - stopDist : price + stopDist;
    final targetPrice = stance == Stance.long
        ? price + config.takeProfitAtrMult * a
        : price - config.takeProfitAtrMult * a;

    // Volatility sizing: risk `riskPerTradePct`% of equity across stop distance.
    final equity = (sizingEquity != null && sizingEquity > 0)
        ? sizingEquity
        : (account.equity <= 0 ? account.cash : account.equity);
    final riskPct = riskPerTradePct ?? config.riskPerTradePct;
    final riskDollars = equity * riskPct / 100;
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

/// True when today's gain has reached the goal. This is a milestone, not a halt.
bool dailyProfitGoalReached({
  required double dayPnlPct,
  required double goalPct,
}) {
  if (goalPct <= 0) return false;
  return dayPnlPct + 1e-9 >= goalPct;
}

/// Once the planned profit price is reached, move the stop to that price so
/// the planned gain is locked and a further move can stay open.
/// Returns null when the stop should not change.
double? lockedProfitStop({
  required bool long,
  required double target,
  required double currentStop,
  required bool targetHit,
  required bool allowMore,
}) {
  if (!targetHit || !allowMore) return null;
  if (long) return target > currentStop ? target : null;
  return target < currentStop ? target : null;
}
