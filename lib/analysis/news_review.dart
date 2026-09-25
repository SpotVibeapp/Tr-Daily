import '../data/models.dart';

/// One headline. [symbol] is set when the feed was queried for that ticker.
/// [trusted] means the feed is company-specific, so a severe word counts even
/// if the title uses the company name instead of the ticker.
class Headline {
  const Headline({
    required this.title,
    this.published,
    this.symbol,
    this.source = '',
    this.trusted = false,
  });

  final String title;
  final DateTime? published;
  final String? symbol;
  final String source;
  final bool trusted;
}

enum MacroStance { neutral, riskOn, riskOff, shock }

enum NewsTradeAction { allow, block, promoteLong, promoteShort, exit }

class SymbolNews {
  const SymbolNews({
    required this.symbol,
    required this.lean,
    required this.checked,
    required this.blocksLong,
    required this.blocksShort,
    required this.exitLong,
    required this.exitShort,
    required this.note,
    this.headline = '',
  });

  final String symbol;

  /// -1 bearish to +1 bullish. 0 when there is nothing usable.
  final double lean;
  final bool checked;
  final bool blocksLong;
  final bool blocksShort;
  final bool exitLong;
  final bool exitShort;
  final String note;
  final String headline;
}

class NewsOpportunity {
  const NewsOpportunity({
    required this.symbol,
    required this.lean,
    required this.note,
    required this.building,
  });

  final String symbol;
  final double lean;
  final String note;
  final bool building;
}

class NewsTradeDecision {
  const NewsTradeDecision({
    required this.action,
    required this.reason,
    this.sizeMultiplier = 1,
  });

  final NewsTradeAction action;
  final String reason;

  /// Applied to risk-per-trade. Never raises size.
  final double sizeMultiplier;
}

class NewsReview {
  const NewsReview({
    required this.at,
    required this.feedOk,
    required this.macro,
    required this.macroNote,
    required this.bySymbol,
    required this.opportunities,
    required this.summary,
    required this.signature,
  });

  final DateTime at;
  final bool feedOk;
  final MacroStance macro;
  final String macroNote;
  final Map<String, SymbolNews> bySymbol;
  final List<NewsOpportunity> opportunities;
  final String summary;

  /// Stable across repeated scans when the story has not changed.
  final String signature;

  bool get blockNewEntries => !feedOk || macro == MacroStance.shock;

  factory NewsReview.unavailable(DateTime at, String reason) {
    final summary =
        'News feed failed ($reason). New trades are skipped until headlines load. '
        'Open positions stay under their stops. This does not remove the risk of a loss.';
    return NewsReview(
      at: at,
      feedOk: false,
      macro: MacroStance.neutral,
      macroNote: 'World headlines could not be read.',
      bySymbol: const <String, SymbolNews>{},
      opportunities: const <NewsOpportunity>[],
      summary: summary,
      signature: 'down|$reason',
    );
  }
}

/// What the engine calls. The live feed is in `data/news_feed.dart`.
abstract class NewsDesk {
  Future<NewsReview> review({
    required List<String> symbols,
    required DateTime now,
    Map<String, SignalScore> charts = const <String, SignalScore>{},
  });
}

/// Names a headline can use instead of the ticker. Short tickers are not
/// matched as bare words — "F" and "GE" show up in ordinary sentences.
const Map<String, List<String>> companyAliases = <String, List<String>>{
  'AAPL': <String>['apple'],
  'NVDA': <String>['nvidia'],
  'TSLA': <String>['tesla'],
  'MSFT': <String>['microsoft'],
  'AMZN': <String>['amazon'],
  'META': <String>['meta platforms', 'facebook'],
  'GOOGL': <String>['alphabet', 'google'],
  'GOOG': <String>['alphabet', 'google'],
  'AMD': <String>['advanced micro devices'],
  'INTC': <String>['intel'],
  'AVGO': <String>['broadcom'],
  'NFLX': <String>['netflix'],
  'DIS': <String>['disney'],
  'BA': <String>['boeing'],
  'JPM': <String>['jpmorgan', 'jp morgan'],
  'BAC': <String>['bank of america'],
  'XOM': <String>['exxon'],
  'CVX': <String>['chevron'],
  'PFE': <String>['pfizer'],
  'LLY': <String>['eli lilly'],
  'WMT': <String>['walmart'],
  'COST': <String>['costco'],
  'NKE': <String>['nike'],
  'SBUX': <String>['starbucks'],
  'F': <String>['ford motor'],
  'GM': <String>['general motors'],
  'UBER': <String>['uber'],
  'COIN': <String>['coinbase'],
  'PLTR': <String>['palantir'],
  'QCOM': <String>['qualcomm'],
  'CRM': <String>['salesforce'],
  'ORCL': <String>['oracle'],
  'IBM': <String>['ibm'],
};

const List<String> _severeBearish = <String>[
  'bankruptcy',
  'chapter 11',
  'chapter 7',
  'accounting fraud',
  'sec charges',
  'criminal charges',
  'trading halt',
  'delisting',
  'going concern',
  'earnings miss',
  'misses estimates',
  'missed estimates',
  'guidance cut',
  'cuts guidance',
  'lowers guidance',
  'profit warning',
  'fda rejects',
  'fda rejection',
  'failed trial',
  'downgraded to sell',
  'debt default',
  'product recall',
];

const List<String> _severeBullish = <String>[
  'fda approval',
  'fda approves',
  'beats estimates',
  'earnings beat',
  'blowout earnings',
  'raises guidance',
  'raised guidance',
  'upgraded to buy',
  'share buyback',
  'stock buyback',
  'wins contract',
  'awarded a contract',
];

const List<String> _notableBearish = <String>[
  'downgrade',
  'layoffs',
  'lawsuit',
  'investigation',
  'probe',
  'plunge',
  'slumps',
  'weak demand',
  'profit warning',
];

const List<String> _notableBullish = <String>[
  'upgrade',
  'partnership',
  'surge',
  'record revenue',
  'strong demand',
  'buyout',
  'to be acquired',
];

const List<String> _shock = <String>[
  'circuit breaker',
  'market crash',
  'markets halted',
  'bank run',
  'emergency rate hike',
];

const List<String> _riskOff = <String>[
  'rate hike',
  'inflation hotter',
  'hot inflation',
  'hotter than expected',
  'recession',
  'invasion',
  'sanctions',
  'selloff',
  'sell-off',
  'jobs miss',
];

const List<String> _riskOn = <String>[
  'rate cut',
  'inflation cools',
  'cooler than expected',
  'soft landing',
  'jobs beat',
  'ceasefire',
];

/// Score already-fetched headlines. No network, so tests and a failed feed
/// can both use it.
NewsReview reviewHeadlines({
  required List<Headline> headlines,
  required List<String> symbols,
  required DateTime now,
  Map<String, bool> checked = const <String, bool>{},
  Map<String, SignalScore> charts = const <String, SignalScore>{},
  Map<String, double> previousLean = const <String, double>{},
  bool feedFailed = false,
}) {
  final wanted = <String>[
    for (final raw in symbols)
      if (raw.trim().isNotEmpty) raw.toUpperCase(),
  ];
  final macro = _macro(headlines, now);
  final bySymbol = <String, SymbolNews>{};
  final opportunities = <NewsOpportunity>[];

  final mentioned = <String>{...wanted};
  for (final symbol in companyAliases.keys) {
    if (headlines.any((h) => _mentions(h, symbol))) mentioned.add(symbol);
  }

  for (final symbol in mentioned) {
    final requested = wanted.contains(symbol);
    final isChecked = feedFailed
        ? false
        : checked.isEmpty
            ? true
            : (checked[symbol] ?? !requested);
    final news = _scoreSymbol(
      symbol: symbol,
      headlines: headlines,
      now: now,
      checked: isChecked,
    );
    if (wanted.contains(symbol) || news.lean.abs() >= 0.4) {
      bySymbol[symbol] = news;
    }
    final chart = charts[symbol];
    final opp = _opportunity(news, chart, previousLean[symbol]);
    if (opp != null) opportunities.add(opp);
  }

  opportunities.sort((a, b) => b.lean.abs().compareTo(a.lean.abs()));
  final blocked = <String>[
    for (final news in bySymbol.values)
      if (news.blocksLong || news.blocksShort || news.exitLong || news.exitShort)
        news.symbol,
  ];
  final developing = <String>[
    for (final opp in opportunities.take(3)) opp.symbol,
  ];
  final summary = _summary(
    feedFailed: feedFailed,
    macro: macro.stance,
    blocked: blocked,
    developing: developing,
  );
  final signature = [
    feedFailed ? 'down' : 'ok',
    macro.stance.name,
    blocked.join(','),
    developing.join(','),
  ].join('|');
  return NewsReview(
    at: now,
    feedOk: !feedFailed,
    macro: macro.stance,
    macroNote: macro.note,
    bySymbol: bySymbol,
    opportunities: opportunities,
    summary: summary,
    signature: signature,
  );
}

NewsTradeDecision decideTrade({
  required NewsReview review,
  required String symbol,
  required Stance chartStance,
  required double chartScore,
  required double chartConfidence,
  required double enterThreshold,
  required double minConfidence,
  bool heldLong = false,
  bool heldShort = false,
}) {
  final key = symbol.toUpperCase();
  final news = review.bySymbol[key];

  if (heldLong && news != null && news.exitLong) {
    return NewsTradeDecision(
      action: NewsTradeAction.exit,
      reason: 'news: ${news.note}',
    );
  }
  if (heldShort && news != null && news.exitShort) {
    return NewsTradeDecision(
      action: NewsTradeAction.exit,
      reason: 'news: ${news.note}',
    );
  }
  if (heldLong || heldShort) {
    return const NewsTradeDecision(
      action: NewsTradeAction.allow,
      reason: 'open position kept — no severe fresh headline',
    );
  }

  if (review.blockNewEntries) {
    final why = review.feedOk
        ? 'world news: ${review.macroNote}'
        : 'headlines could not be read';
    return NewsTradeDecision(
      action: NewsTradeAction.block,
      reason: 'skipped $key — $why. A missed story is not opened as a new trade.',
    );
  }
  if (news != null && !news.checked) {
    return NewsTradeDecision(
      action: NewsTradeAction.block,
      reason: 'skipped $key — no current headlines for this name',
    );
  }
  if (chartStance == Stance.long && news != null && news.blocksLong) {
    return NewsTradeDecision(
      action: NewsTradeAction.block,
      reason: 'skipped $key long — ${news.note}',
    );
  }
  if (chartStance == Stance.short && news != null && news.blocksShort) {
    return NewsTradeDecision(
      action: NewsTradeAction.block,
      reason: 'skipped $key short — ${news.note}',
    );
  }
  if (review.macro == MacroStance.riskOff &&
      chartStance == Stance.long &&
      (chartScore < 0.55 || chartConfidence < 0.5) &&
      (news == null || news.lean < 0.5)) {
    return const NewsTradeDecision(
      action: NewsTradeAction.block,
      reason: 'skipped weak long — world news is risk-off',
    );
  }
  if (review.macro == MacroStance.riskOn &&
      chartStance == Stance.short &&
      (chartScore > -0.55 || chartConfidence < 0.5) &&
      (news == null || news.lean > -0.5)) {
    return const NewsTradeDecision(
      action: NewsTradeAction.block,
      reason: 'skipped weak short — world news is risk-on',
    );
  }

  final lean = news?.lean ?? 0;
  if (chartStance == Stance.flat &&
      news != null &&
      news.checked &&
      lean >= 0.55 &&
      chartScore >= enterThreshold - 0.15 &&
      chartScore >= 0.25 &&
      chartConfidence >= minConfidence &&
      !news.blocksLong &&
      review.macro != MacroStance.riskOff) {
    return NewsTradeDecision(
      action: NewsTradeAction.promoteLong,
      reason: 'news agrees and the chart is close — ${news.note}',
    );
  }
  if (chartStance == Stance.flat &&
      news != null &&
      news.checked &&
      lean <= -0.55 &&
      chartScore <= -(enterThreshold - 0.15) &&
      chartScore <= -0.25 &&
      chartConfidence >= minConfidence &&
      !news.blocksShort &&
      review.macro != MacroStance.riskOn) {
    return NewsTradeDecision(
      action: NewsTradeAction.promoteShort,
      reason: 'news agrees and the chart is close — ${news.note}',
    );
  }

  var size = 1.0;
  var reason = 'news reviewed';
  if (chartStance == Stance.long && lean <= -0.25) {
    size = 0.5;
    reason = 'size cut — headlines lean against the long';
  } else if (chartStance == Stance.short && lean >= 0.25) {
    size = 0.5;
    reason = 'size cut — headlines lean against the short';
  }
  return NewsTradeDecision(
    action: NewsTradeAction.allow,
    reason: reason,
    sizeMultiplier: size,
  );
}

List<Headline> parseRss(
  String xml, {
  String? symbol,
  String source = '',
  bool trusted = false,
}) {
  final items = <Headline>[];
  final itemRe = RegExp(
    '<item\\b[^>]*>([\\s\\S]*?)</item>',
    caseSensitive: false,
  );
  for (final match in itemRe.allMatches(xml)) {
    final block = match.group(1) ?? '';
    final title = _cleanTitle(_tag(block, 'title') ?? '');
    if (title.isEmpty) continue;
    items.add(Headline(
      title: title,
      published: parseRssDate(_tag(block, 'pubDate') ?? ''),
      symbol: symbol?.toUpperCase(),
      source: source,
      trusted: trusted,
    ));
  }
  return items;
}

DateTime? parseRssDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final iso = DateTime.tryParse(text);
  if (iso != null) return iso.toUtc();
  final match = RegExp(
    r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?',
  ).firstMatch(text);
  if (match == null) return null;
  const months = <String, int>{
    'jan': 1,
    'feb': 2,
    'mar': 3,
    'apr': 4,
    'may': 5,
    'jun': 6,
    'jul': 7,
    'aug': 8,
    'sep': 9,
    'oct': 10,
    'nov': 11,
    'dec': 12,
  };
  final month = months[match.group(2)!.toLowerCase()];
  if (month == null) return null;
  return DateTime.utc(
    int.parse(match.group(3)!),
    month,
    int.parse(match.group(1)!),
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6) ?? '0'),
  );
}

class _MacroRead {
  const _MacroRead(this.stance, this.note);

  final MacroStance stance;
  final String note;
}

_MacroRead _macro(List<Headline> headlines, DateTime now) {
  var shock = '';
  var off = '';
  var on = '';
  for (final headline in headlines) {
    if (headline.symbol != null) continue;
    final age = _age(headline, now);
    if (age != null && age.inHours > 24) continue;
    final title = headline.title.toLowerCase();
    shock = shock.isEmpty ? _firstHit(title, _shock) : shock;
    if (age == null || age.inHours <= 24) {
      off = off.isEmpty ? _firstHit(title, _riskOff) : off;
      on = on.isEmpty ? _firstHit(title, _riskOn) : on;
    }
  }
  if (shock.isNotEmpty) {
    final dated = headlines.any(
      (h) =>
          h.symbol == null &&
          h.published != null &&
          _age(h, now) != null &&
          _age(h, now)! <= const Duration(hours: 12) &&
          h.title.toLowerCase().contains(shock),
    );
    if (dated) {
      return _MacroRead(
        MacroStance.shock,
        'shock headline ($shock) — no new trades this scan',
      );
    }
  }
  if (off.isNotEmpty) {
    return _MacroRead(MacroStance.riskOff, 'risk-off ($off)');
  }
  if (on.isNotEmpty) {
    return _MacroRead(MacroStance.riskOn, 'risk-on ($on)');
  }
  return const _MacroRead(MacroStance.neutral, 'no strong world-news lean');
}

SymbolNews _scoreSymbol({
  required String symbol,
  required List<Headline> headlines,
  required DateTime now,
  required bool checked,
}) {
  if (!checked) {
    return SymbolNews(
      symbol: symbol,
      lean: 0,
      checked: false,
      blocksLong: true,
      blocksShort: true,
      exitLong: false,
      exitShort: false,
      note: 'No current headlines — a new trade in $symbol is skipped.',
    );
  }

  var lean = 0.0;
  var used = 0;
  var severeBear = false;
  var severeBull = false;
  var exitBear = false;
  var exitBull = false;
  String top = '';
  for (final headline in headlines) {
    if (!_countsFor(headline, symbol)) continue;
    final age = _age(headline, now);
    if (age != null && age > const Duration(hours: 36)) continue;
    final title = headline.title.toLowerCase();
    final bear = _hit(title, _severeBearish);
    final bull = _hit(title, _severeBullish);
    var weight = 0.0;
    if (bear != null) {
      weight = -1;
      severeBear = true;
      if (headline.published != null &&
          age != null &&
          age <= const Duration(hours: 18)) {
        exitBear = true;
      }
    } else if (bull != null) {
      weight = 1;
      severeBull = true;
      if (headline.published != null &&
          age != null &&
          age <= const Duration(hours: 18)) {
        exitBull = true;
      }
    } else {
      final down = _hit(title, _notableBearish);
      final up = _hit(title, _notableBullish);
      if (down != null) weight = -0.4;
      if (up != null) weight = 0.4;
    }
    if (weight == 0) continue;
    final decay = age != null && age.inHours > 6 ? 0.5 : 1.0;
    lean += weight * decay;
    used++;
    if (top.isEmpty) top = headline.title;
  }
  if (used >= 2) lean /= 2;
  lean = lean.clamp(-1.0, 1.0);

  final blocksLong = severeBear || lean <= -0.45;
  final blocksShort = severeBull || lean >= 0.45;
  final note = _symbolNote(
    symbol: symbol,
    lean: lean,
    severeBear: severeBear,
    severeBull: severeBull,
    headline: top,
  );
  return SymbolNews(
    symbol: symbol,
    lean: lean,
    checked: true,
    blocksLong: blocksLong,
    blocksShort: blocksShort,
    exitLong: exitBear,
    exitShort: exitBull,
    note: note,
    headline: top,
  );
}

NewsOpportunity? _opportunity(
  SymbolNews news,
  SignalScore? chart,
  double? previous,
) {
  if (!news.checked || news.lean.abs() < 0.4) return null;
  final chartAgrees = chart != null &&
      ((news.lean > 0 && chart.stance == Stance.long) ||
          (news.lean < 0 && chart.stance == Stance.short));
  if (chartAgrees && chart.score.abs() >= 0.45) return null;
  var building = false;
  if (previous != null) {
    final sameDirection = news.lean == 0 ||
        previous == 0 ||
        (news.lean > 0 && previous > 0) ||
        (news.lean < 0 && previous < 0);
    building = sameDirection && news.lean.abs() - previous.abs() >= 0.25;
  }
  final direction = news.lean > 0 ? 'positive' : 'negative';
  final lead = building ? 'Building' : 'Developing';
  return NewsOpportunity(
    symbol: news.symbol,
    lean: news.lean,
    building: building,
    note: '$lead: ${news.symbol} news is $direction'
        '${news.headline.isEmpty ? '' : ' — ${news.headline}'}'
        '. The chart has not confirmed. Not a buy or a profit prediction.',
  );
}

String _symbolNote({
  required String symbol,
  required double lean,
  required bool severeBear,
  required bool severeBull,
  required String headline,
}) {
  final story = headline.isEmpty ? '' : ' "$headline"';
  if (severeBear) {
    return 'Severe headline for $symbol$story. New longs are blocked. '
        'An open long is closed only if the story is dated and recent.';
  }
  if (severeBull) {
    return 'Severe positive headline for $symbol$story. New shorts are blocked.';
  }
  if (lean <= -0.45) return 'Headlines lean against $symbol$story.';
  if (lean >= 0.45) return 'Headlines lean with $symbol$story.';
  if (headline.isEmpty) return 'No strong headline for $symbol.';
  return 'Reviewed $symbol$story.';
}

String _summary({
  required bool feedFailed,
  required MacroStance macro,
  required List<String> blocked,
  required List<String> developing,
}) {
  if (feedFailed) {
    return 'News feed failed. New trades are skipped until headlines load. '
        'This does not remove the risk of a loss.';
  }
  final parts = <String>['News reviewed. World: ${macro.name}.'];
  if (blocked.isNotEmpty) parts.add('Checked hard: ${blocked.join(', ')}.');
  if (developing.isNotEmpty) {
    parts.add('Developing: ${developing.join(', ')}.');
  }
  parts.add('Headlines can be late or wrong. This does not remove the risk of a loss.');
  return parts.join(' ');
}

bool _countsFor(Headline headline, String symbol) {
  if (headline.trusted && headline.symbol?.toUpperCase() == symbol) return true;
  return _mentions(headline, symbol);
}

bool _mentions(Headline headline, String symbol) {
  if (_hasTicker(headline.title, symbol)) return true;
  for (final alias in companyAliases[symbol] ?? const <String>[]) {
    if (_hasWord(headline.title, alias)) return true;
  }
  return false;
}

bool _hasTicker(String title, String symbol) {
  if (symbol.length < 3) return false;
  return RegExp('\\b${RegExp.escape(symbol)}\\b', caseSensitive: false)
      .hasMatch(title);
}

bool _hasWord(String title, String phrase) {
  return RegExp('\\b${RegExp.escape(phrase)}\\b', caseSensitive: false)
      .hasMatch(title);
}

Duration? _age(Headline headline, DateTime now) {
  final published = headline.published;
  if (published == null) return null;
  return now.toUtc().difference(published.toUtc());
}

String? _hit(String title, List<String> phrases) {
  for (final phrase in phrases) {
    final at = title.indexOf(phrase);
    if (at < 0) continue;
    if (_denied(title, at)) continue;
    return phrase;
  }
  return null;
}

String _firstHit(String title, List<String> phrases) => _hit(title, phrases) ?? '';

bool _denied(String title, int at) {
  final start = at < 28 ? 0 : at - 28;
  final window = title.substring(start, at);
  return window.contains('no ') ||
      window.contains('not ') ||
      window.contains('denies') ||
      window.contains('denied') ||
      window.contains('without') ||
      window.contains('avoids') ||
      window.contains('rumor');
}

String? _tag(String block, String name) {
  final match = RegExp(
    '<$name\\b[^>]*>([\\s\\S]*?)</$name>',
    caseSensitive: false,
  ).firstMatch(block);
  return match?.group(1);
}

String _cleanTitle(String raw) {
  var text = raw.trim();
  if (text.toLowerCase().startsWith('<![cdata[')) {
    text = text.substring(9);
    if (text.endsWith(']]>')) text = text.substring(0, text.length - 3);
  }
  text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');
  text = text
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&apos;', "'");
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
