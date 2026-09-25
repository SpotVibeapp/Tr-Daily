import '../core/config.dart';
import '../data/models.dart';
import '../risk/risk_manager.dart';

/// How the account is allowed to trade today, from the session's starting
/// equity — not from a leftover small-account habit, and not from an
/// intraday swing.
enum AccountBand { micro, building, fullDayTrade }

/// Top sizing band. This used to be the pattern-day-trader line. FINRA
/// retired that rule on June 4, 2026, and Alpaca no longer counts day trades,
/// so no balance caps the number of day trades any more.
const double fullDayTradeEquity = 25000;

/// Below this, a short is skipped when fit-to-cash is on.
const double shortEquityFloor = 2000;

class ScalePlan {
  const ScalePlan({
    required this.band,
    required this.dayStartEquity,
    required this.maxSharePrice,
    required this.allowShort,
    required this.keepLowerPriced,
    required this.cheapCeiling,
    required this.opportunityCeiling,
    required this.summary,
  });

  final AccountBand band;
  final double dayStartEquity;
  final double maxSharePrice;
  final bool allowShort;
  final bool keepLowerPriced;
  final double cheapCeiling;
  final double opportunityCeiling;
  final String summary;

  bool get fullDayTrade => band == AccountBand.fullDayTrade;
}

/// Broker `lastEquity` is the previous close. Fall back to current equity
/// only when the broker has not reported a start-of-day figure.
double dayStartEquityOf(AccountInfo account) {
  final last = account.lastEquity;
  if (last != null && last > 0) return last;
  if (account.equity > 0) return account.equity;
  return account.cash > 0 ? account.cash : 0;
}

AccountBand bandForEquity(double equity) {
  if (equity >= fullDayTradeEquity) return AccountBand.fullDayTrade;
  if (equity >= shortEquityFloor) return AccountBand.building;
  return AccountBand.micro;
}

/// How high the extra scan looks, besides the cheap bucket. Grows with the
/// day's starting balance and never exceeds what one share can cost.
double opportunityCeiling({
  required double dayStartEquity,
  required double cheapCeiling,
  required double maxSharePrice,
}) {
  var cap = cheapCeiling + (dayStartEquity > 0 ? dayStartEquity / 500 : 0);
  if (cap < cheapCeiling) cap = cheapCeiling;
  if (cap > 80) cap = 80;
  if (maxSharePrice > 0 && cap > maxSharePrice) cap = maxSharePrice;
  return cap;
}

/// Moderate by default. A clearly larger target with higher confidence may
/// use more of the day's risk budget, never more than 2× the user's setting.
double convictionRiskPct({
  required double basePct,
  required double targetPct,
  required double confidence,
  required double minTargetPct,
  required bool enabled,
}) {
  if (!enabled || basePct <= 0) return basePct;
  var mult = 1.0;
  if (targetPct >= minTargetPct * 2 && confidence >= 0.55) mult = 1.5;
  if (targetPct >= minTargetPct * 3 && confidence >= 0.70) mult = 2.0;
  final boosted = basePct * mult;
  final ceiling = basePct * 2;
  return boosted < ceiling ? boosted : ceiling;
}

ScalePlan scalePlan({
  required AccountInfo account,
  required AppSettings settings,
}) {
  final start = settings.scaleWithBalance
      ? dayStartEquityOf(account)
      : (account.equity > 0 ? account.equity : account.cash);
  final band = bandForEquity(start);
  final maxShare = maxAffordableSharePrice(
    account,
    settings.risk,
    sizingEquity: settings.scaleWithBalance ? start : null,
  );
  final cheap = settings.budgetShareCeiling <= 0 ? 5.0 : settings.budgetShareCeiling;
  final opp = opportunityCeiling(
    dayStartEquity: start,
    cheapCeiling: cheap,
    maxSharePrice: maxShare,
  );
  final allowShort = settings.allowShort &&
      settings.risk.allowShort &&
      !(settings.fitToBudget && start > 0 && start < shortEquityFloor);
  final keepLower = settings.scaleWithBalance &&
      settings.fitToBudget &&
      band != AccountBand.micro;
  return ScalePlan(
    band: settings.scaleWithBalance ? band : AccountBand.building,
    dayStartEquity: start,
    maxSharePrice: maxShare,
    allowShort: allowShort,
    keepLowerPriced: keepLower,
    cheapCeiling: cheap,
    opportunityCeiling: opp,
    summary: settings.scaleWithBalance
        ? describeScale(band: band, dayStartEquity: start)
        : '',
  );
}

String describeScale({
  required AccountBand band,
  required double dayStartEquity,
}) {
  final money = '\$${dayStartEquity.toStringAsFixed(0)}';
  final base = switch (band) {
    AccountBand.micro =>
      'Today\'s start is $money. Sizing stays in the small-account range '
          'until the next session starts higher. Shorts stay off under \$2,000.',
    AccountBand.building =>
      'Today\'s start is $money. Size follows that balance, not a leftover '
          'small-account habit. Lower-priced names stay in the scan beside '
          'names this account can afford.',
    AccountBand.fullDayTrade =>
      'Today\'s start is $money. Lower-priced names are still scanned when '
          'a higher percentage looks better.',
  };
  return '$base Day trades are not capped by count. This does not '
      'guarantee a profit.';
}
