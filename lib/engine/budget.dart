import '../core/config.dart';
import '../data/market_data_source.dart';
import '../data/models.dart';
import '../risk/risk_manager.dart';
import 'scale.dart';

/// Listed names the engine may scan when the user's watchlist does not fit
/// the account. This is a candidate pool, not a buy list and not a search of
/// OTC penny stocks — live price still has to fit one share.
///
/// Prices move. A name in [oftenUnderFive] is only used when a live quote is
/// at or under the account's cap (and, by default, at or under $5).
class AffordableUniverse {
  const AffordableUniverse._();

  /// Liquid listed names that often trade above $5 but can still fit a
  /// small account's one-share cap.
  static const List<String> core = <String>[
    'F',
    'T',
    'PFE',
    'INTC',
    'SOFI',
    'SNAP',
    'AAL',
    'CCL',
    'NCLH',
    'WBD',
    'LYFT',
    'GOLD',
    'NLY',
    'AGNC',
    'VALE',
    'PBR',
    'ITUB',
    'ABEV',
    'TEVA',
    'NU',
    'KMI',
    'KEY',
  ];

  /// Listed names that have often traded at or under $5. Sub-$1 and OTC
  /// symbols are intentionally absent — Alpaca usually rejects them.
  static const List<String> oftenUnderFive = <String>[
    'NOK',
    'ERIC',
    'BBD',
    'GRAB',
    'JBLU',
    'PLUG',
    'NIO',
    'OPEN',
    'AMC',
    'BB',
    'SOUN',
    'CHPT',
    'LCID',
    'RIVN',
    'MARA',
    'RIOT',
    'CLSK',
    'FCEL',
    'BBAI',
    'UWMC',
  ];

  static List<String> get all {
    final seen = <String>{};
    final out = <String>[];
    for (final symbol in <String>[...core, ...oftenUnderFive]) {
      if (seen.add(symbol)) out.add(symbol);
    }
    return out;
  }
}

/// What the engine should do with the current account and watchlist.
class BudgetSnapshot {
  const BudgetSnapshot({
    required this.maxSharePrice,
    required this.sleeve,
    required this.skipped,
    required this.summary,
    required this.active,
    this.quotedAt,
  });

  static const BudgetSnapshot idle = BudgetSnapshot(
    maxSharePrice: 0,
    sleeve: <String>[],
    skipped: <String>[],
    summary: '',
    active: false,
  );

  /// Highest price of one new share that still fits the risk cap.
  final double maxSharePrice;

  /// Extra symbols to scan because the watchlist does not fit. Empty when
  /// the user's own list already has an affordable name.
  final List<String> sleeve;

  /// Watchlist symbols one share cannot buy.
  final List<String> skipped;

  final String summary;

  /// True when budget mode changed what will be traded (skips or a sleeve).
  final bool active;

  final DateTime? quotedAt;
}

/// Picks backup symbols and remembers live quotes so a small account is not
/// re-screened on every 60-second tick.
class BudgetSession {
  BudgetSession({
    this.quotesFor,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Test hook. Production leaves this null and uses [liveQuotes].
  final Future<Map<String, double>> Function(List<String> symbols)? quotesFor;

  final DateTime Function() _clock;

  static const Duration quoteTtl = Duration(minutes: 15);
  static const double minSharePrice = 1.0;
  static const int maxSleeve = 8;
  static const double defaultPreferredCeiling = 5;

  BudgetSnapshot last = BudgetSnapshot.idle;

  DateTime? _quotedAt;
  double? _quotedMax;
  Map<String, double> _quotes = <String, double>{};

  void clear() {
    last = BudgetSnapshot.idle;
    _quotedAt = null;
    _quotedMax = null;
    _quotes = <String, double>{};
  }

  bool needsQuoteRefresh(double maxSharePrice, DateTime now) {
    final quotedAt = _quotedAt;
    final quotedMax = _quotedMax;
    if (quotedAt == null || quotedMax == null || _quotes.isEmpty) return true;
    if (now.difference(quotedAt) > quoteTtl) return true;
    final moved = (maxSharePrice - quotedMax).abs();
    return moved > 0.25 && moved > quotedMax * 0.1;
  }

  /// True when the next [advise] call will hit the network for backup names.
  bool shouldScreen({
    required AppSettings settings,
    required AccountInfo account,
    required Iterable<SignalScore> watchlistSignals,
    DateTime? now,
    ScalePlan? plan,
  }) {
    if (!settings.fitToBudget) return false;
    final maxPx = plan?.maxSharePrice ??
        maxAffordableSharePrice(account, settings.risk);
    if (maxPx < minSharePrice) return false;
    final keepLower = plan?.keepLowerPriced ?? false;
    if (!keepLower && _watchlistFits(settings, watchlistSignals, maxPx)) {
      return false;
    }
    return needsQuoteRefresh(maxPx, now ?? _clock());
  }

  Future<BudgetSnapshot> advise({
    required AppSettings settings,
    required AccountInfo account,
    required Iterable<SignalScore> watchlistSignals,
    required MarketDataSource source,
    DateTime? now,
    ScalePlan? plan,
  }) async {
    final clock = now ?? _clock();
    if (!settings.fitToBudget) {
      last = BudgetSnapshot.idle;
      return last;
    }

    final maxPx = plan?.maxSharePrice ??
        maxAffordableSharePrice(account, settings.risk);
    final prices = _watchlistPrices(settings, watchlistSignals);
    final skipped = <String>[];
    final affordable = <String>[];
    for (final raw in settings.watchlist) {
      final symbol = raw.toUpperCase();
      final px = prices[symbol];
      if (px == null) continue;
      if (px <= maxPx + 1e-9) {
        affordable.add(symbol);
      } else {
        skipped.add(symbol);
      }
    }

    final equity = plan != null && plan.dayStartEquity > 0
        ? plan.dayStartEquity
        : (account.equity > 0 ? account.equity : account.cash);
    final keepLower = plan?.keepLowerPriced ?? false;
    final shortNote = equity > 0 && equity < 2000
        ? ' Shorts are skipped under \$2,000 equity.'
        : '';

    if (maxPx < minSharePrice) {
      last = BudgetSnapshot(
        maxSharePrice: maxPx,
        sleeve: const <String>[],
        skipped: List<String>.unmodifiable(skipped),
        summary: 'Budget fit: buying power is too small for 1 share of a '
            'listed stock (max \$${maxPx.toStringAsFixed(2)}).$shortNote',
        active: true,
        quotedAt: clock,
      );
      return last;
    }

    // The user's list already has something this account can buy. Do not
    // replace it. A larger balance still adds lower-priced names so a
    // higher-percentage setup is not ignored just because the account grew.
    if (affordable.isNotEmpty && !keepLower) {
      final parts = <String>[];
      if (skipped.isNotEmpty) {
        parts.add(
          'Budget fit: skipped ${skipped.join(', ')} — one share is over '
          '\$${maxPx.toStringAsFixed(2)}. Trading ${affordable.join(', ')}.',
        );
      }
      if (shortNote.isNotEmpty) parts.add(shortNote.trim());
      last = BudgetSnapshot(
        maxSharePrice: maxPx,
        sleeve: const <String>[],
        skipped: List<String>.unmodifiable(skipped),
        summary: parts.join(' '),
        active: skipped.isNotEmpty || shortNote.isNotEmpty,
        quotedAt: clock,
      );
      return last;
    }

    if (needsQuoteRefresh(maxPx, clock)) {
      final loader = quotesFor;
      _quotes = loader != null
          ? await loader(AffordableUniverse.all)
          : await liveQuotes(source, AffordableUniverse.all);
      _quotedAt = clock;
      _quotedMax = maxPx;
    }

    final preferred = plan?.cheapCeiling ??
        (settings.budgetShareCeiling <= 0
            ? defaultPreferredCeiling
            : settings.budgetShareCeiling);
    final exclude = settings.watchlist.map((s) => s.toUpperCase()).toSet();
    final sleeve = keepLower && affordable.isNotEmpty
        ? pickBalancedSleeve(
            quotes: _quotes,
            maxSharePrice: maxPx,
            cheapCeiling: preferred,
            opportunityCeiling: plan?.opportunityCeiling ?? preferred,
            exclude: exclude,
          )
        : pickSleeve(
            quotes: _quotes,
            maxSharePrice: maxPx,
            preferredCeiling: preferred,
            exclude: exclude,
          );

    final String summary;
    if (keepLower && affordable.isNotEmpty) {
      if (_quotes.isEmpty) {
        summary = 'Today\'s start can trade ${affordable.join(', ')}. '
            'Lower-priced quotes were unavailable, so only the watchlist '
            'is in this scan.$shortNote';
      } else if (sleeve.isEmpty) {
        summary = 'Today\'s start can trade ${affordable.join(', ')}. '
            'No extra lower-priced name currently fits.$shortNote';
      } else {
        summary = 'Today\'s start can trade ${affordable.join(', ')}. '
            'Still scanning lower-priced names: ${sleeve.join(', ')}.'
            '$shortNote';
      }
    } else if (_quotes.isEmpty) {
      summary = 'Watchlist is too expensive for this account (max one share '
          '\$${maxPx.toStringAsFixed(2)}), and live prices for lower-priced '
          'names were unavailable. No new entries from those names.$shortNote';
    } else if (sleeve.isEmpty) {
      summary = 'Watchlist is too expensive (max one share '
          '\$${maxPx.toStringAsFixed(2)}). No listed backup name currently '
          'fits that cap.$shortNote';
    } else {
      summary = 'Watchlist too expensive for \$${maxPx.toStringAsFixed(2)}'
          '/share. Scanning listed names that fit: ${sleeve.join(', ')}.'
          '$shortNote';
    }

    last = BudgetSnapshot(
      maxSharePrice: maxPx,
      sleeve: List<String>.unmodifiable(sleeve),
      skipped: List<String>.unmodifiable(
        // Only fill this in when no watchlist price fit. An empty skip list
        // on a large account means the watchlist is still eligible.
        skipped.isEmpty && affordable.isEmpty
            ? settings.watchlist.map((s) => s.toUpperCase()).toList()
            : skipped,
      ),
      summary: summary,
      active: true,
      quotedAt: _quotedAt,
    );
    return last;
  }

  static bool _watchlistFits(
    AppSettings settings,
    Iterable<SignalScore> signals,
    double maxSharePrice,
  ) {
    final prices = _watchlistPrices(settings, signals);
    for (final px in prices.values) {
      if (px <= maxSharePrice + 1e-9) return true;
    }
    return false;
  }

  static Map<String, double> _watchlistPrices(
    AppSettings settings,
    Iterable<SignalScore> signals,
  ) {
    final wanted = settings.watchlist.map((s) => s.toUpperCase()).toSet();
    final prices = <String, double>{};
    for (final sig in signals) {
      final symbol = sig.symbol.toUpperCase();
      if (!wanted.contains(symbol) || sig.price <= 0) continue;
      prices[symbol] = sig.price;
    }
    return prices;
  }
}

/// Cheap names plus a higher bucket that grows with the account. A large
/// balance still sees lower-priced stocks; it does not drop them, and it
/// does not ignore names it can now afford.
List<String> pickBalancedSleeve({
  required Map<String, double> quotes,
  required double maxSharePrice,
  required double cheapCeiling,
  required double opportunityCeiling,
  Set<String> exclude = const <String>{},
  int cheapCount = 4,
  int opportunityCount = 4,
}) {
  bool inRange(String symbol, double minPx, double maxPx) {
    if (exclude.contains(symbol)) return false;
    final px = quotes[symbol];
    if (px == null || px < BudgetSession.minSharePrice) return false;
    if (px > maxSharePrice + 1e-9) return false;
    if (px + 1e-9 < minPx) return false;
    return px <= maxPx + 1e-9;
  }

  final cheapCap =
      cheapCeiling < maxSharePrice ? cheapCeiling : maxSharePrice;
  final cheap = <String>[];
  for (final symbol in <String>[
    ...AffordableUniverse.oftenUnderFive,
    ...AffordableUniverse.core,
  ]) {
    if (cheap.contains(symbol)) continue;
    if (!inRange(symbol, BudgetSession.minSharePrice, cheapCap)) continue;
    cheap.add(symbol);
    if (cheap.length >= cheapCount) break;
  }

  final oppCap = opportunityCeiling < maxSharePrice
      ? opportunityCeiling
      : maxSharePrice;
  final extra = <String>[];
  if (oppCap > cheapCap + 0.5) {
    for (final symbol in <String>[
      ...AffordableUniverse.core,
      ...AffordableUniverse.oftenUnderFive,
    ]) {
      if (cheap.contains(symbol) || extra.contains(symbol)) continue;
      if (!inRange(symbol, cheapCap + 0.01, oppCap)) continue;
      extra.add(symbol);
      if (extra.length >= opportunityCount) break;
    }
  }
  return <String>[...cheap, ...extra];
}

/// Prefer names at or under [preferredCeiling]. If none of those fit the
/// account, use listed names up to [maxSharePrice] so a small account is
/// not stuck doing nothing. Never returns a symbol at or under \$1 — brokers
/// commonly reject those — or above what one share can cost.
List<String> pickSleeve({
  required Map<String, double> quotes,
  required double maxSharePrice,
  required double preferredCeiling,
  Set<String> exclude = const <String>{},
  int maxCount = BudgetSession.maxSleeve,
}) {
  bool fits(String symbol, double ceiling) {
    if (exclude.contains(symbol)) return false;
    final px = quotes[symbol];
    if (px == null) return false;
    if (px < BudgetSession.minSharePrice) return false;
    if (px > maxSharePrice + 1e-9) return false;
    return px <= ceiling + 1e-9;
  }

  final preferredCap = preferredCeiling < maxSharePrice
      ? preferredCeiling
      : maxSharePrice;
  final preferred = <String>[];
  for (final symbol in AffordableUniverse.oftenUnderFive) {
    if (fits(symbol, preferredCap)) preferred.add(symbol);
  }
  for (final symbol in AffordableUniverse.core) {
    if (preferred.contains(symbol)) continue;
    if (fits(symbol, preferredCap)) preferred.add(symbol);
  }
  if (preferred.isNotEmpty) {
    return preferred.take(maxCount).toList();
  }

  final fallback = <String>[];
  for (final symbol in <String>[
    ...AffordableUniverse.core,
    ...AffordableUniverse.oftenUnderFive,
  ]) {
    if (fallback.contains(symbol)) continue;
    if (fits(symbol, maxSharePrice)) fallback.add(symbol);
  }
  return fallback.take(maxCount).toList();
}

/// The first source that is not a demo generator. Sleeve scans must use this
/// so a Yahoo miss cannot fall through to synthetic prices and look tradable.
MarketDataSource liveScanSource(MarketDataSource source) {
  if (source is CompositeDataSource) {
    for (final child in source.sources) {
      if (child is SyntheticMarketSource || child is BundledCsvSource) continue;
      return child;
    }
  }
  return source;
}

/// Live quotes only. Synthetic and bundled demo prices are ignored so a
/// small account is never sized off invented numbers.
Future<Map<String, double>> liveQuotes(
  MarketDataSource source,
  List<String> symbols,
) async {
  if (symbols.isEmpty) return <String, double>{};
  if (source is CompositeDataSource) {
    final out = <String, double>{};
    for (final child in source.sources) {
      if (child is SyntheticMarketSource || child is BundledCsvSource) continue;
      final missing =
          symbols.where((s) => !out.containsKey(s.toUpperCase())).toList();
      if (missing.isEmpty) break;
      out.addAll(await liveQuotes(child, missing));
    }
    return out;
  }
  if (source is YahooFinanceSource) return source.quoteMany(symbols);
  if (source is AlpacaDataSource) return source.quoteMany(symbols);
  return <String, double>{};
}
