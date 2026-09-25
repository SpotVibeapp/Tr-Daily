import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../core/secrets.dart';
import 'csv_parser.dart';
import 'models.dart';

/// Abstraction over market-data vendors so sources can be swapped freely.
abstract class MarketDataSource {
  /// Human-readable id, e.g. `yahoo`, `alpaca`, `synthetic`, `bundled`.
  String get id;

  /// Historical OHLCV bars, oldest first.
  Future<List<Candle>> getBars({
    required String symbol,
    required BarInterval interval,
    int limit = 400,
    DateTime? end,
  });

  /// Last trade/close price if the source can provide it cheaply.
  Future<double?> getLastPrice(String symbol);
}

/// Thrown when a source cannot satisfy a request (network, quota, parsing).
class DataSourceException implements Exception {
  DataSourceException(this.message, {this.source});

  final String message;
  final String? source;

  @override
  String toString() => 'DataSourceException($source): $message';
}

/// Yahoo Finance chart API (v8). Free, no key. Works in production
/// environments; may be unreachable from locked-down sandboxes.
class YahooFinanceSource implements MarketDataSource {
  YahooFinanceSource({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const String _base = 'https://query1.finance.yahoo.com/v8/finance/chart';

  @override
  String get id => 'yahoo';

  @override
  Future<List<Candle>> getBars({
    required String symbol,
    required BarInterval interval,
    int limit = 400,
    DateTime? end,
  }) async {
    final range = _rangeFor(interval, limit);
    final uri = Uri.parse(
      '$_base/$symbol?interval=${interval.code}&range=$range'
      '${end != null ? '&end=${end.millisecondsSinceEpoch ~/ 1000}' : ''}',
    );
    final resp = await _client.get(uri, headers: <String, String>{
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw DataSourceException('HTTP ${resp.statusCode}', source: id);
    }
    return _parseChart(jsonDecode(resp.body) as Map<String, dynamic>, symbol, interval);
  }

  List<Candle> _parseChart(Map<String, dynamic> root, String symbol, BarInterval interval) {
    try {
      final chart = (root['chart'] as Map<String, dynamic>);
      if (chart['error'] != null) {
        throw DataSourceException('Yahoo error: ${chart['error']}', source: id);
      }
      final result = (chart['result'] as List<dynamic>).first as Map<String, dynamic>;
      final timestamps = (result['timestamp'] as List<dynamic>? ?? <dynamic>[]);
      final quote = (result['indicators'] as Map<String, dynamic>)['quote']
              as List<dynamic>;
      final q = quote.first as Map<String, dynamic>;
      final opens = q['open'] as List<dynamic>;
      final highs = q['high'] as List<dynamic>;
      final lows = q['low'] as List<dynamic>;
      final closes = q['close'] as List<dynamic>;
      final vols = q['volume'] as List<dynamic>? ?? <dynamic>[];

      final out = <Candle>[];
      for (var i = 0; i < timestamps.length; i++) {
        final o = _d(opens, i), h = _d(highs, i), l = _d(lows, i), c = _d(closes, i);
        if (o == null || h == null || l == null || c == null) continue;
        out.add(Candle(
          symbol: symbol,
          time: DateTime.fromMillisecondsSinceEpoch(
            (timestamps[i] as int) * 1000,
            isUtc: true,
          ).toLocal(),
          open: o,
          high: h,
          low: l,
          close: c,
          volume: _d(vols, i) ?? 0,
        ));
      }
      if (out.isEmpty) throw DataSourceException('no bars parsed', source: id);
      return out;
    } on DataSourceException {
      rethrow;
    } catch (e) {
      throw DataSourceException('parse failure: $e', source: id);
    }
  }

  static double? _d(List<dynamic> list, int i) =>
      i < list.length ? (list[i] as num?)?.toDouble() : null;

  String _rangeFor(BarInterval interval, int limit) {
    // Yahoo intraday ranges are capped; pick something that covers `limit`.
    switch (interval) {
      case BarInterval.oneMin:
        return limit <= 390 ? '1d' : limit <= 780 ? '2d' : '5d';
      case BarInterval.fiveMin:
        return limit <= 78 ? '1d' : limit <= 234 ? '3d' : '5d';
      case BarInterval.fifteenMin:
        return limit <= 26 ? '1d' : limit <= 104 ? '5d' : '1mo';
      case BarInterval.oneHour:
        return limit <= 40 ? '1mo' : limit <= 120 ? '3mo' : '6mo';
      case BarInterval.oneDay:
        return limit <= 100 ? '6mo' : limit <= 250 ? '1y' : '5y';
    }
  }

  @override
  Future<double?> getLastPrice(String symbol) async {
    final bars = await getBars(
      symbol: symbol,
      interval: BarInterval.oneMin,
      limit: 5,
    );
    return bars.isEmpty ? null : bars.last.close;
  }

  /// Last daily closes for a budget screen. One small chart request per
  /// symbol, a few at a time, so a 30-name sleeve check does not open
  /// 30 intraday histories.
  Future<Map<String, double>> quoteMany(List<String> symbols) async {
    final out = <String, double>{};
    const width = 4;
    for (var i = 0; i < symbols.length; i += width) {
      final end = i + width > symbols.length ? symbols.length : i + width;
      final slice = symbols.sublist(i, end);
      final batch = await Future.wait(slice.map(_quoteClose));
      for (final row in batch) {
        if (row != null) out[row.key] = row.value;
      }
    }
    return out;
  }

  Future<MapEntry<String, double>?> _quoteClose(String symbol) async {
    final sym = symbol.toUpperCase();
    try {
      final uri = Uri.parse('$_base/$sym?interval=1d&range=5d');
      final resp = await _client.get(uri, headers: <String, String>{
        'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 12));
      if (resp.statusCode != 200) return null;
      final bars = _parseChart(
        jsonDecode(resp.body) as Map<String, dynamic>,
        sym,
        BarInterval.oneDay,
      );
      if (bars.isEmpty || bars.last.close <= 0) return null;
      return MapEntry(sym, bars.last.close);
    } catch (_) {
      return null;
    }
  }
}

/// Alpaca market data (free IEX feed for basic plans). Requires API keys.
class AlpacaDataSource implements MarketDataSource {
  AlpacaDataSource({
    required this.keys,
    http.Client? client,
    this.sipFallback = false,
  }) : _client = client ?? http.Client();

  final TradingKeys keys;
  final http.Client _client;
  final bool sipFallback;
  static const String _base = 'https://data.alpaca.markets';

  @override
  String get id => 'alpaca';

  Map<String, String> get _headers => <String, String>{
        'APCA-API-KEY-ID': keys.keyId,
        'APCA-API-SECRET-KEY': keys.secretKey,
        'Accept': 'application/json',
      };

  @override
  Future<List<Candle>> getBars({
    required String symbol,
    required BarInterval interval,
    int limit = 400,
    DateTime? end,
  }) async {
    final timeframe = _timeframe(interval);
    final qp = <String, String>{
      'timeframe': timeframe,
      'limit': '$limit',
      'feed': sipFallback ? 'sip' : 'iex',
      'adjustment': 'raw',
      'sort': 'desc',
    };
    if (end != null) qp['end'] = end.toUtc().toIso8601String();
    final uri = Uri.parse('$_base/v2/stocks/$symbol/bars').replace(queryParameters: qp);
    final resp = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode == 429) {
      throw DataSourceException('rate limited', source: id);
    }
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw DataSourceException('auth failed — check API keys', source: id);
    }
    if (resp.statusCode != 200) {
      throw DataSourceException('HTTP ${resp.statusCode}: ${resp.body}', source: id);
    }
    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    final raw = (root['bars'] as List<dynamic>? ?? <dynamic>[])
        .cast<Map<String, dynamic>>();
    final out = raw
        .map((b) => Candle(
              symbol: symbol,
              time: DateTime.parse(b['t'] as String).toLocal(),
              open: (b['o'] as num).toDouble(),
              high: (b['h'] as num).toDouble(),
              low: (b['l'] as num).toDouble(),
              close: (b['c'] as num).toDouble(),
              volume: (b['v'] as num).toDouble(),
            ))
        .toList()
        .reversed
        .toList();
    if (out.isEmpty) throw DataSourceException('no bars returned', source: id);
    return out;
  }

  String _timeframe(BarInterval i) {
    switch (i) {
      case BarInterval.oneMin:
        return '1Min';
      case BarInterval.fiveMin:
        return '5Min';
      case BarInterval.fifteenMin:
        return '15Min';
      case BarInterval.oneHour:
        return '1Hour';
      case BarInterval.oneDay:
        return '1Day';
    }
  }

  @override
  Future<double?> getLastPrice(String symbol) async {
    final uri = Uri.parse('$_base/v2/stocks/$symbol/quotes/latest?feed=iex');
    final resp = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;
    final root = jsonDecode(resp.body) as Map<String, dynamic>;
    final quote = (root['quote'] as Map<String, dynamic>?)?.cast<String, dynamic>();
    final px = quote == null ? null : (quote['ap'] as num? ?? quote['bp'] as num?);
    return px?.toDouble();
  }

  /// One snapshots call for the budget screen. Empty on any failure so the
  /// caller can fall through to another live source.
  Future<Map<String, double>> quoteMany(List<String> symbols) async {
    if (symbols.isEmpty) return <String, double>{};
    try {
      final joined = symbols.map((s) => s.toUpperCase()).join(',');
      final uri = Uri.parse(
        '$_base/v2/stocks/snapshots?symbols=$joined&feed=iex',
      );
      final resp = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) return <String, double>{};
      final decoded = jsonDecode(resp.body);
      if (decoded is! Map) return <String, double>{};
      final asMap = Map<dynamic, dynamic>.from(decoded);
      final nested = asMap['snapshots'];
      final raw = nested is Map ? Map<dynamic, dynamic>.from(nested) : asMap;
      final out = <String, double>{};
      raw.forEach((key, value) {
        if (key == 'snapshots' || value is! Map) return;
        final px = _snapshotPrice(Map<dynamic, dynamic>.from(value));
        if (px != null && px > 0) out[key.toString().toUpperCase()] = px;
      });
      return out;
    } catch (_) {
      return <String, double>{};
    }
  }

  static double? _snapshotPrice(Map<dynamic, dynamic> snap) {
    final trade = snap['latestTrade'];
    final minute = snap['minuteBar'];
    final daily = snap['dailyBar'];
    if (trade is Map && trade['p'] is num) return (trade['p'] as num).toDouble();
    if (minute is Map && minute['c'] is num) {
      return (minute['c'] as num).toDouble();
    }
    if (daily is Map && daily['c'] is num) return (daily['c'] as num).toDouble();
    return null;
  }
}

/// Deterministic synthetic market data for offline demo, tests, and
/// environments where live feeds are unreachable.
///
/// Produces regime-switching random walks with drift, volatility clustering
/// and intrabar structure so strategies have something realistic to chew on.
/// Clearly labeled as *synthetic* — never presented as real market data.
class SyntheticMarketSource implements MarketDataSource {
  SyntheticMarketSource({this.basePrice = 100, int? seed}) : _seed = seed ?? 1337;

  final double basePrice;
  final int _seed;

  @override
  String get id => 'synthetic';

  @override
  Future<List<Candle>> getBars({
    required String symbol,
    required BarInterval interval,
    int limit = 400,
    DateTime? end,
  }) async {
    final rnd = Random(_seed ^ symbol.hashCode ^ interval.code.hashCode);
    final now = end ?? DateTime.now();
    var price = basePrice * (0.5 + rnd.nextDouble());
    // Random-walk drift regimes.
    var drift = (rnd.nextDouble() - 0.45) * 0.0006;
    var vol = 0.004 + rnd.nextDouble() * 0.006;

    final out = <Candle>[];
    var t = now.subtract(interval.duration * limit);
    for (var i = 0; i < limit; i++) {
      if (rnd.nextInt(40) == 0) {
        drift = (rnd.nextDouble() - 0.45) * 0.0012;
        vol = 0.003 + rnd.nextDouble() * 0.01;
      }
      final shock = (rnd.nextDouble() * 2 - 1);
      final open = price;
      price *= 1 + drift + vol * shock + 0.35 * vol * (rnd.nextDouble() * 2 - 1);
      final hi = max(open, price) * (1 + rnd.nextDouble() * vol * 0.6);
      final lo = min(open, price) * (1 - rnd.nextDouble() * vol * 0.6);
      out.add(Candle(
        symbol: symbol,
        time: t,
        open: _r(open),
        high: _r(hi),
        low: _r(lo),
        close: _r(price),
        volume: 500000 + rnd.nextInt(4000000).toDouble(),
      ));
      t = t.add(interval.duration);
    }
    return out;
  }

  double _r(double v) => double.parse(v.toStringAsFixed(2));

  @override
  Future<double?> getLastPrice(String symbol) async {
    final bars = await getBars(symbol: symbol, interval: BarInterval.fiveMin, limit: 2);
    return bars.isEmpty ? null : bars.last.close;
  }
}

/// Bundled CSV sample data shipped with the app (demo/offline mode).
class BundledCsvSource implements MarketDataSource {
  BundledCsvSource({
    required this.filesBySymbol,
    required this.reader,
    this.fallback,
  });

  /// symbol -> asset path, e.g. `assets/sample_data/AAPL_demo.csv`.
  final Map<String, String> filesBySymbol;

  /// Reads an asset as a string (injected so this class stays pure Dart).
  final Future<String> Function(String path) reader;
  final MarketDataSource? fallback;

  @override
  String get id => 'bundled';

  @override
  Future<List<Candle>> getBars({
    required String symbol,
    required BarInterval interval,
    int limit = 400,
    DateTime? end,
  }) async {
    final path = filesBySymbol[symbol.toUpperCase()];
    if (path != null && interval == BarInterval.oneDay) {
      final csv = await reader(path);
      final bars = CsvParser.parse(csv, symbol: symbol);
      if (bars.isNotEmpty) {
        return bars.length > limit ? bars.sublist(bars.length - limit) : bars;
      }
    }
    final fb = fallback;
    if (fb != null) {
      return fb.getBars(
        symbol: symbol,
        interval: interval,
        limit: limit,
        end: end,
      );
    }
    throw DataSourceException('no bundled data for $symbol', source: id);
  }

  @override
  Future<double?> getLastPrice(String symbol) async {
    try {
      final bars = await getBars(symbol: symbol, interval: BarInterval.oneDay, limit: 1);
      return bars.isEmpty ? null : bars.last.close;
    } catch (_) {
      return fallback?.getLastPrice(symbol);
    }
  }
}

/// Tries each source in order until one succeeds.
class CompositeDataSource implements MarketDataSource {
  CompositeDataSource(this.sources);

  final List<MarketDataSource> sources;

  @override
  String get id => sources.map((s) => s.id).join('+');

  @override
  Future<List<Candle>> getBars({
    required String symbol,
    required BarInterval interval,
    int limit = 400,
    DateTime? end,
  }) async {
    final errors = <String>[];
    for (final s in sources) {
      try {
        return await s.getBars(
          symbol: symbol,
          interval: interval,
          limit: limit,
          end: end,
        );
      } catch (e) {
        errors.add('${s.id}: $e');
      }
    }
    throw DataSourceException('all sources failed: ${errors.join(' | ')}');
  }

  @override
  Future<double?> getLastPrice(String symbol) async {
    for (final s in sources) {
      try {
      final px = await s.getLastPrice(symbol);
        if (px != null) return px;
      } catch (_) {}
    }
    return null;
  }
}
