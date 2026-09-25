import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/estimator.dart';
import 'package:tr_daily/data/market_data_source.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/cost_gate.dart';
import 'package:tr_daily/engine/scanner.dart';
import 'package:tr_daily/strategy/ensemble.dart';
import 'package:tr_daily/ui/theme.dart';

/// Synthetic bars, except [thin] names return a short history and [broken]
/// names throw, like a real HTTP failure.
class _Source implements MarketDataSource {
  _Source({required this.thin, this.broken = const <String>{}});

  final Map<String, int> thin;
  final Set<String> broken;
  final SyntheticMarketSource _inner = SyntheticMarketSource(seed: 7);

  @override
  String get id => 'test';

  @override
  Future<List<Candle>> getBars({
    required String symbol,
    required BarInterval interval,
    int limit = 400,
    DateTime? end,
  }) async {
    if (broken.contains(symbol)) {
      throw DataSourceException('HTTP 500');
    }
    final bars = await _inner.getBars(
      symbol: symbol,
      interval: interval,
      limit: limit,
      end: end,
    );
    final cap = thin[symbol];
    return cap == null ? bars : bars.sublist(bars.length - cap);
  }

  @override
  Future<double?> getLastPrice(String symbol) => _inner.getLastPrice(symbol);

  @override
  Future<BidAsk?> getQuote(String symbol) async => null;

  @override
  Future<Map<String, BidAsk>> getQuotes(List<String> symbols) async =>
      <String, BidAsk>{};
}

MarketScanner _scanner(MarketDataSource source) => MarketScanner(
      source: source,
      estimator: const TrendEstimator(),
      ensemble: SignalEnsemble(),
    );

void main() {
  test('thinly traded market-walk names are skipped, not reported as errors',
      () async {
    final out = await _scanner(
      _Source(thin: <String, int>{'VEGN': 20, 'DINT': 28, 'TSBK': 46}),
    ).scan(<String>['AAPL', 'VEGN', 'DINT', 'TSBK'], train: false);

    expect(out.hasErrors, isFalse);
    expect(out.thin, <String, int>{'VEGN': 20, 'DINT': 28, 'TSBK': 46});
    expect(out.signals.map((s) => s.symbol), <String>['AAPL']);

    // AAPL is the only name the user picked, and it scanned fine.
    expect(out.warningFor(<String>['AAPL']), isNull);
    expect(out.thinSkipped(<String>['AAPL']), <String>['VEGN', 'DINT', 'TSBK']);
    expect(
      thinSkippedNote(out.thinSkipped(<String>['AAPL'])),
      '3 thinly traded names skipped (under 60 bars): VEGN, DINT, TSBK',
    );
  });

  test('a thin name on the watchlist or held still warns', () async {
    final out = await _scanner(
      _Source(thin: <String, int>{'RSSX': 48, 'GMMF': 46}),
    ).scan(<String>['RSSX', 'GMMF'], train: false);

    expect(
      out.warningFor(<String>['rssx']),
      'RSSX: only 48 bars so far, needs 60 to judge',
    );
    expect(out.thinSkipped(<String>['rssx']), <String>['GMMF']);
  });

  test('real data failures still warn for any name', () async {
    final out = await _scanner(
      _Source(thin: <String, int>{'ARTNA': 36}, broken: <String>{'USMF'}),
    ).scan(<String>['ARTNA', 'USMF'], train: false);

    expect(out.hasErrors, isTrue);
    final warning = out.warningFor(const <String>[]);
    expect(warning, startsWith('USMF: '));
    expect(warning, contains('HTTP 500'));
    expect(warning, isNot(contains('ARTNA')));
  });

  test('thinSkippedNote is empty when nothing was skipped', () {
    expect(thinSkippedNote(const <String>[]), isEmpty);
    expect(
      thinSkippedNote(const <String>['VEGN']),
      '1 thinly traded name skipped (under 60 bars): VEGN',
    );
  });

  test('money groups thousands', () {
    expect(TrTheme.money(25000), r'$25,000.00');
    expect(TrTheme.money(25), r'$25.00');
    expect(TrTheme.money(1234.5, signed: true), r'+$1,234.50');
    expect(TrTheme.money(-1234.5), r'-$1,234.50');
    expect(TrTheme.money(999.999), r'$1,000.00');
    expect(TrTheme.money(250000), r'$250.0k');
  });
}
