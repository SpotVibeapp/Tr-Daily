/// Listed US equity symbols. Warrants, rights, units, and OTC names are not
/// treated as the tradable stock list.
library;

final RegExp _ticker = RegExp(r'^[A-Z]{1,5}(\.[A-Z])?$');

/// True for a normal listed ticker, including a single class suffix such as BRK.B.
bool isListedTicker(String symbol) => _ticker.hasMatch(symbol.trim().toUpperCase());

/// Security names that are not the common stock or ETF the app can trade.
bool nameIsDerivative(String name) {
  final text = name.toLowerCase();
  if (text.isEmpty) return false;
  const markers = <String>[
    'warrant',
    ' right',
    'rights',
    ' unit',
    'units',
    'preferred',
    'debenture',
    'note due',
    'depositary share',
    'when issued',
    'test stock',
  ];
  for (final marker in markers) {
    if (text.contains(marker)) return true;
  }
  return false;
}

bool _otcExchange(String exchange) {
  final text = exchange.toUpperCase();
  if (text.isEmpty) return false;
  return text.contains('OTC') || text == 'PINK' || text == 'GREY';
}

/// Drop warrant, right, and unit tickers that hang off a listed common symbol.
List<String> dropAttachedIssues(Iterable<String> symbols) {
  final present = <String>{
    for (final raw in symbols) raw.trim().toUpperCase(),
  };
  final out = <String>[];
  final seen = <String>{};
  for (final raw in symbols) {
    final symbol = raw.trim().toUpperCase();
    if (symbol.isEmpty || !seen.add(symbol) || !isListedTicker(symbol)) {
      continue;
    }
    if (_attachedIssue(symbol, present)) continue;
    out.add(symbol);
  }
  return out;
}

bool _attachedIssue(String symbol, Set<String> present) {
  final dot = symbol.indexOf('.');
  if (dot >= 0) {
    final suffix = symbol.substring(dot + 1);
    return suffix == 'W' ||
        suffix == 'WS' ||
        suffix == 'U' ||
        suffix == 'R' ||
        suffix.startsWith('PR');
  }
  if (symbol.length < 2) return false;
  final last = symbol[symbol.length - 1];
  if (last != 'W' && last != 'R' && last != 'U') return false;
  return present.contains(symbol.substring(0, symbol.length - 1));
}

/// One symbol per line, or a pipe-delimited directory row whose first column
/// is the ticker.
List<String> symbolsFromLines(String body) {
  final raw = <String>[];
  for (final line in body.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('file creation')) {
      continue;
    }
    final symbol = trimmed.split('|').first.trim().toUpperCase();
    if (symbol == 'SYMBOL' || symbol == 'ACT SYMBOL') continue;
    if (!isListedTicker(symbol)) continue;
    raw.add(symbol);
  }
  return dropAttachedIssues(raw);
}

/// Nasdaq Trader `nasdaqlisted.txt` and `otherlisted.txt` bodies.
List<String> symbolsFromNasdaqDirectories({
  required String nasdaq,
  required String other,
}) {
  final raw = <String>[
    ..._nasdaqRows(nasdaq, symbolColumn: 0, nameColumn: 1, testColumn: 3),
    ..._nasdaqRows(other, symbolColumn: 0, nameColumn: 1, testColumn: 6),
  ];
  return dropAttachedIssues(raw);
}

List<String> _nasdaqRows(
  String body, {
  required int symbolColumn,
  required int nameColumn,
  required int testColumn,
}) {
  final out = <String>[];
  for (final line in body.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('file creation')) {
      continue;
    }
    final parts = trimmed.split('|');
    if (parts.length <= symbolColumn) continue;
    final symbol = parts[symbolColumn].trim().toUpperCase();
    if (symbol == 'SYMBOL' || symbol == 'ACT SYMBOL') continue;
    if (!isListedTicker(symbol)) continue;
    if (testColumn < parts.length && parts[testColumn].trim().toUpperCase() == 'Y') {
      continue;
    }
    final name = nameColumn < parts.length ? parts[nameColumn] : '';
    if (nameIsDerivative(name)) continue;
    out.add(symbol);
  }
  return out;
}

/// Alpaca `GET /v2/assets` payload. Only active, tradable US equities.
List<String> symbolsFromAlpacaAssets(List<dynamic> assets) {
  final raw = <String>[];
  for (final item in assets) {
    if (item is! Map) continue;
    final row = Map<String, dynamic>.from(item);
    final symbol = (row['symbol'] as String? ?? '').trim().toUpperCase();
    if (!isListedTicker(symbol)) continue;
    if (row['status'] != 'active' || row['tradable'] != true) continue;
    final assetClass = (row['class'] as String? ?? '').toLowerCase();
    if (assetClass.isNotEmpty && assetClass != 'us_equity') continue;
    if (_otcExchange(row['exchange'] as String? ?? '')) continue;
    if (nameIsDerivative(row['name'] as String? ?? '')) continue;
    raw.add(symbol);
  }
  return dropAttachedIssues(raw);
}
