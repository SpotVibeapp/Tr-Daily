import '../data/models.dart';
import '../risk/risk_manager.dart';

/// Why a setup was rejected as a day trade, or [ok] when it has enough
/// percentage room without blowing the risk limit.
enum DayTradeSkip { ok, quiet, oversized }

class DayTradeCheck {
  const DayTradeCheck({
    required this.skip,
    required this.targetPct,
    required this.accountRiskPct,
    required this.detail,
  });

  final DayTradeSkip skip;
  final double targetPct;
  final double accountRiskPct;
  final String detail;

  bool get allowed => skip == DayTradeSkip.ok;
}

/// Target distance as a percent of the share price. Null when the signal
/// has no target.
double? targetPctOfPrice(SignalScore sig) {
  final target = sig.suggestedTarget;
  if (target == null || sig.price <= 0) return null;
  return (target - sig.price).abs() / sig.price * 100;
}

/// A day trade has to pay in percent, not just fit in the account.
///
/// Two failures the risk cap alone does not catch:
/// - Quiet name: one share fits, but the target is a fraction of a percent,
///   so the position ties up cash to break even after the spread.
/// - Forced size: the 1-share minimum risks several times the configured
///   risk-per-trade, so a loss is no longer the small paper cut the settings
///   describe.
DayTradeCheck checkDayTrade({
  required SignalScore sig,
  required double equity,
  required double qty,
  required double? stopPrice,
  required double minTargetPct,
  required double riskPerTradePct,
}) {
  final targetPct = targetPctOfPrice(sig) ?? 0;
  if (sig.price <= 0 || targetPct + 1e-9 < minTargetPct) {
    return DayTradeCheck(
      skip: DayTradeSkip.quiet,
      targetPct: targetPct,
      accountRiskPct: 0,
      detail: 'target ${targetPct.toStringAsFixed(2)}% of price is under the '
          '${minTargetPct.toStringAsFixed(1)}% day-trade minimum',
    );
  }

  final stop = stopPrice;
  final base = equity <= 0 ? 0.0 : equity;
  var accountRiskPct = 0.0;
  if (stop != null && base > 0 && qty > 0) {
    accountRiskPct = qty * (sig.price - stop).abs() / base * 100;
  }
  // Share rounding may risk a bit more than the setting. Past 2.5× it is
  // no longer that setting — it is a forced oversized trade.
  final riskCap = riskPerTradePct * 2.5;
  if (accountRiskPct > riskCap + 1e-6) {
    return DayTradeCheck(
      skip: DayTradeSkip.oversized,
      targetPct: targetPct,
      accountRiskPct: accountRiskPct,
      detail: 'this size risks ${accountRiskPct.toStringAsFixed(2)}% of equity, '
          'above ${riskCap.toStringAsFixed(2)}% '
          '(2.5× the ${riskPerTradePct.toStringAsFixed(2)}% risk setting)',
    );
  }

  return DayTradeCheck(
    skip: DayTradeSkip.ok,
    targetPct: targetPct,
    accountRiskPct: accountRiskPct,
    detail: 'target ${targetPct.toStringAsFixed(2)}% · '
        'risk ${accountRiskPct.toStringAsFixed(2)}% of equity',
  );
}

/// Higher percentage targets, then stronger scores. Quiet passes still rank
/// below a name that can actually move.
List<SignalScore> rankForDayTrade(List<SignalScore> signals) {
  final ranked = List<SignalScore>.from(signals);
  ranked.sort((a, b) {
    final edgeA = (targetPctOfPrice(a) ?? 0) * (0.5 + a.confidence) * a.score.abs();
    final edgeB = (targetPctOfPrice(b) ?? 0) * (0.5 + b.confidence) * b.score.abs();
    final byEdge = edgeB.compareTo(edgeA);
    if (byEdge != 0) return byEdge;
    return b.score.abs().compareTo(a.score.abs());
  });
  return ranked;
}

/// Convenience for the engine: run the risk verdict's size through the filter.
DayTradeCheck checkDayTradeVerdict({
  required SignalScore sig,
  required RiskVerdict verdict,
  required double equity,
  required double minTargetPct,
  required double riskPerTradePct,
}) {
  return checkDayTrade(
    sig: sig,
    equity: equity,
    qty: verdict.suggestedQty ?? 0,
    stopPrice: verdict.stopPrice ?? sig.suggestedStop,
    minTargetPct: minTargetPct,
    riskPerTradePct: riskPerTradePct,
  );
}
