import 'package:http/http.dart' as http;

import '../analysis/news_review.dart';
import 'models.dart';

/// Company RSS plus one world-news feed. Cached so every scan re-reads the
/// latest headlines without a new request every few seconds.
class LiveNewsDesk implements NewsDesk {
  LiveNewsDesk({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, _CachedHeadlines> _bySymbol = <String, _CachedHeadlines>{};
  _CachedHeadlines? _macro;
  NewsReview? _last;
  DateTime? _lastFetch;
  Map<String, double> _previousLean = <String, double>{};
  Future<NewsReview>? _inflight;

  static const Duration refreshEvery = Duration(seconds: 45);
  static const Duration trustFor = Duration(minutes: 20);

  @override
  Future<NewsReview> review({
    required List<String> symbols,
    required DateTime now,
    Map<String, SignalScore> charts = const <String, SignalScore>{},
  }) {
    final running = _inflight;
    if (running != null) return running;
    final future = _review(symbols: symbols, now: now, charts: charts);
    _inflight = future;
    return future.whenComplete(() => _inflight = null);
  }

  Future<NewsReview> _review({
    required List<String> symbols,
    required DateTime now,
    required Map<String, SignalScore> charts,
  }) async {
    final wanted = _prioritize(symbols, charts.keys);
    final freshEnough = _last != null &&
        _lastFetch != null &&
        now.difference(_lastFetch!) < refreshEvery &&
        wanted.every(_bySymbol.containsKey);
    if (freshEnough) {
      return reviewHeadlines(
        headlines: _pooled(wanted),
        symbols: wanted,
        now: now,
        checked: _checked(wanted, now),
        charts: charts,
        previousLean: _previousLean,
        feedFailed: _pooled(wanted).isEmpty && _macro == null,
      );
    }

    await _refreshMacro(now);
    await Future.wait(<Future<void>>[
      for (final symbol in wanted) _refreshSymbol(symbol, now),
    ]);
    _lastFetch = now;
    final checked = _checked(wanted, now);
    final anyChecked = checked.values.any((ok) => ok);
    final review = reviewHeadlines(
      headlines: _pooled(wanted),
      symbols: wanted,
      now: now,
      checked: checked,
      charts: charts,
      previousLean: _previousLean,
      feedFailed: !anyChecked && _macro == null,
    );
    _previousLean = <String, double>{
      for (final entry in review.bySymbol.entries) entry.key: entry.value.lean,
    };
    _last = review;
    return review;
  }

  List<String> _prioritize(List<String> symbols, Iterable<String> chartKeys) {
    final out = <String>[];
    void add(String raw) {
      final symbol = raw.trim().toUpperCase();
      if (symbol.isEmpty || out.contains(symbol) || out.length >= 12) return;
      out.add(symbol);
    }

    for (final symbol in symbols) {
      add(symbol);
    }
    for (final symbol in chartKeys) {
      add(symbol);
    }
    return out;
  }

  Map<String, bool> _checked(List<String> symbols, DateTime now) {
    return <String, bool>{
      for (final symbol in symbols) symbol: _usable(_bySymbol[symbol], now),
    };
  }

  bool _usable(_CachedHeadlines? cache, DateTime now) {
    if (cache == null || !cache.ok) return false;
    return now.difference(cache.at) <= trustFor;
  }

  List<Headline> _pooled(List<String> symbols) {
    final out = <Headline>[];
    final macro = _macro;
    if (macro != null && macro.ok) out.addAll(macro.headlines);
    for (final symbol in symbols) {
      final cache = _bySymbol[symbol];
      if (cache != null && cache.ok) out.addAll(cache.headlines);
    }
    return out;
  }

  Future<void> _refreshMacro(DateTime now) async {
    try {
      final xml = await _get(_macroUri());
      final headlines = parseRss(xml, source: 'world', trusted: false);
      _macro = _CachedHeadlines(headlines, now, ok: true);
    } catch (_) {
      final previous = _macro;
      if (previous == null || now.difference(previous.at) > trustFor) {
        _macro = null;
      }
    }
  }

  Future<void> _refreshSymbol(String symbol, DateTime now) async {
    try {
      var headlines = parseRss(
        await _get(_yahooUri(symbol)),
        symbol: symbol,
        source: 'yahoo',
        trusted: true,
      );
      if (headlines.isEmpty) {
        headlines = parseRss(
          await _get(_googleUri('$symbol stock when:1d')),
          symbol: symbol,
          source: 'google',
          trusted: false,
        );
      }
      _bySymbol[symbol] = _CachedHeadlines(headlines, now, ok: true);
    } catch (_) {
      final previous = _bySymbol[symbol];
      if (previous == null || now.difference(previous.at) > trustFor) {
        _bySymbol[symbol] = _CachedHeadlines(const <Headline>[], now, ok: false);
      }
    }
  }

  Future<String> _get(Uri uri) async {
    final response = await _client.get(uri, headers: const <String, String>{
      'User-Agent': 'Mozilla/5.0 (compatible; TrDaily/1.0)',
      'Accept': 'application/rss+xml, application/xml, text/xml, */*',
    }).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw http.ClientException('HTTP ${response.statusCode}', uri);
    }
    final body = response.body;
    final lowered = body.toLowerCase();
    if (!lowered.contains('<rss') && !lowered.contains('<item')) {
      throw http.ClientException('response was not a news feed', uri);
    }
    return body;
  }

  Uri _yahooUri(String symbol) {
    return Uri.https('feeds.finance.yahoo.com', '/rss/2.0/headline', <String, String>{
      's': symbol,
      'region': 'US',
      'lang': 'en-US',
    });
  }

  Uri _googleUri(String query) {
    return Uri.https('news.google.com', '/rss/search', <String, String>{
      'q': query,
      'hl': 'en-US',
      'gl': 'US',
      'ceid': 'US:en',
    });
  }

  Uri _macroUri() {
    return _googleUri(
      'Federal Reserve OR inflation OR "jobs report" OR recession OR '
      '"stock market" OR "interest rate" OR ceasefire when:1d',
    );
  }
}

class _CachedHeadlines {
  const _CachedHeadlines(this.headlines, this.at, {required this.ok});

  final List<Headline> headlines;
  final DateTime at;
  final bool ok;
}
