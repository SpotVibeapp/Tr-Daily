import 'dart:convert';

import 'package:http/http.dart' as http;

import '../broker/alpaca_broker.dart';
import '../core/secrets.dart';
import '../data/listed_symbols.dart';
import 'budget.dart';

/// How many new listed names to chart on one pass. The watchlist is added on
/// top of this. A phone cannot chart every listed stock in one minute.
const int listedNamesPerPass = 16;

enum MarketListKind { none, alpaca, nasdaq, bundled, backup }

/// One pass through the listed market.
class MarketPass {
  const MarketPass({
    required this.symbols,
    required this.nextCursor,
    required this.cursorBefore,
    required this.universeSize,
    required this.added,
    required this.kind,
  });

  final List<String> symbols;
  final int nextCursor;
  final int cursorBefore;
  final int universeSize;
  final int added;
  final MarketListKind kind;

  bool get walkedMarket => added > 0 && universeSize > 0;

  /// 1-based range of the universe visited this pass.
  String get rangeLabel {
    if (!walkedMarket) return '';
    final start = cursorBefore + 1;
    if (nextCursor > cursorBefore) return '$start-$nextCursor of $universeSize';
    return '$start-$universeSize of $universeSize';
  }
}

/// Priority names first, then the next slice of [universe]. The cursor wraps.
MarketPass nextMarketPass({
  required List<String> universe,
  required int cursor,
  required Iterable<String> priority,
  int extraPerPass = listedNamesPerPass,
  MarketListKind kind = MarketListKind.none,
}) {
  final seen = <String>{};
  final symbols = <String>[];
  void add(String raw) {
    final symbol = raw.trim().toUpperCase();
    if (symbol.isEmpty || !seen.add(symbol)) return;
    symbols.add(symbol);
  }

  for (final raw in priority) {
    add(raw);
  }
  if (universe.isEmpty || extraPerPass <= 0) {
    return MarketPass(
      symbols: symbols,
      nextCursor: universe.isEmpty ? 0 : cursor % universe.length,
      cursorBefore: universe.isEmpty ? 0 : cursor % universe.length,
      universeSize: universe.length,
      added: 0,
      kind: kind,
    );
  }

  final start = cursor % universe.length;
  var index = start;
  var added = 0;
  while (added < extraPerPass && added < universe.length) {
    final symbol = universe[index].trim().toUpperCase();
    index = (index + 1) % universe.length;
    added++;
    add(symbol);
    if (index == start) break;
  }
  return MarketPass(
    symbols: symbols,
    nextCursor: index,
    cursorBefore: start,
    universeSize: universe.length,
    added: added,
    kind: kind,
  );
}

/// Loads the listed universe and remembers where the last pass stopped.
class MarketScan {
  MarketScan({
    http.Client? client,
    this.readBundled,
    this.loadUniverse,
    DateTime Function()? clock,
  })  : _client = client,
        _clock = clock ?? DateTime.now;

  final http.Client? _client;
  http.Client? _ownedClient;

  http.Client get _http => _client ?? (_ownedClient ??= http.Client());
  final Future<String> Function()? readBundled;

  /// Test hook. When set, network and the bundled file are not used.
  final Future<List<String>> Function()? loadUniverse;
  final DateTime Function() _clock;

  static const Duration universeTtl = Duration(hours: 6);
  static const Duration retryAfterFailure = Duration(minutes: 10);

  List<String> _universe = const <String>[];
  DateTime? _loadedAt;
  DateTime? _failedAt;
  int cursor = 0;
  MarketListKind kind = MarketListKind.none;
  MarketPass last = const MarketPass(
    symbols: <String>[],
    nextCursor: 0,
    cursorBefore: 0,
    universeSize: 0,
    added: 0,
    kind: MarketListKind.none,
  );

  int get universeSize => _universe.length;

  Future<MarketPass> next({
    required bool enabled,
    required Iterable<String> priority,
    required TradingKeys keys,
    required BrokerMode mode,
  }) async {
    if (!enabled) {
      last = nextMarketPass(
        universe: const <String>[],
        cursor: cursor,
        priority: priority,
        extraPerPass: 0,
      );
      return last;
    }
    await _ensureUniverse(keys: keys, mode: mode);
    last = nextMarketPass(
      universe: _universe,
      cursor: cursor,
      priority: priority,
      kind: kind,
    );
    cursor = last.nextCursor;
    return last;
  }

  Future<void> _ensureUniverse({
    required TradingKeys keys,
    required BrokerMode mode,
  }) async {
    final now = _clock();
    if (_universe.isNotEmpty &&
        _loadedAt != null &&
        now.difference(_loadedAt!) < universeTtl) {
      return;
    }
    if (_failedAt != null &&
        _universe.isNotEmpty &&
        now.difference(_failedAt!) < retryAfterFailure) {
      return;
    }

    final injected = loadUniverse;
    if (injected != null) {
      _remember(await injected(), MarketListKind.bundled, now);
      return;
    }

    if (keys.isConfigured) {
      try {
        final symbols = await _alpaca(keys, mode);
        if (symbols.length >= 100) {
          _remember(symbols, MarketListKind.alpaca, now);
          return;
        }
      } catch (_) {
        _failedAt = now;
      }
    }

    try {
      final symbols = await _nasdaq();
      if (symbols.length >= 100) {
        _remember(symbols, MarketListKind.nasdaq, now);
        return;
      }
    } catch (_) {
      _failedAt = now;
    }

    final reader = readBundled;
    if (reader != null) {
      try {
        final symbols = symbolsFromLines(await reader());
        if (symbols.length >= 100) {
          _remember(symbols, MarketListKind.bundled, now);
          return;
        }
      } catch (_) {
        _failedAt = now;
      }
    }

    if (_universe.isNotEmpty) return;
    _remember(AffordableUniverse.all, MarketListKind.backup, now);
  }

  void _remember(List<String> symbols, MarketListKind source, DateTime now) {
    _universe = List<String>.unmodifiable(symbols);
    kind = source;
    _loadedAt = now;
    _failedAt = null;
    if (cursor >= _universe.length) cursor = 0;
  }

  Future<List<String>> _alpaca(TradingKeys keys, BrokerMode mode) async {
    final base = mode == BrokerMode.live
        ? 'https://api.alpaca.markets'
        : 'https://paper-api.alpaca.markets';
    final uri = Uri.parse('$base/v2/assets?status=active&asset_class=us_equity');
    final response = await _http.get(uri, headers: <String, String>{
      'APCA-API-KEY-ID': keys.keyId,
      'APCA-API-SECRET-KEY': keys.secretKey,
      'Accept': 'application/json',
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Alpaca assets HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! List) throw StateError('Alpaca assets were not a list');
    return symbolsFromAlpacaAssets(decoded);
  }

  Future<List<String>> _nasdaq() async {
    const headers = <String, String>{
      'User-Agent': 'Mozilla/5.0',
      'Accept': 'text/plain',
    };
    final nasdaq = await _http
        .get(
          Uri.parse(
            'https://www.nasdaqtrader.com/dynamic/SymDir/nasdaqlisted.txt',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));
    final other = await _http
        .get(
          Uri.parse(
            'https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt',
          ),
          headers: headers,
        )
        .timeout(const Duration(seconds: 20));
    if (nasdaq.statusCode != 200 && other.statusCode != 200) {
      throw StateError('Nasdaq symbol directory was unavailable');
    }
    return symbolsFromNasdaqDirectories(
      nasdaq: nasdaq.statusCode == 200 ? nasdaq.body : '',
      other: other.statusCode == 200 ? other.body : '',
    );
  }
}
