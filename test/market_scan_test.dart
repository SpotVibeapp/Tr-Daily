import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/broker/alpaca_broker.dart';
import 'package:tr_daily/core/secrets.dart';
import 'package:tr_daily/data/listed_symbols.dart';
import 'package:tr_daily/engine/market_scan.dart';

void main() {
  test('a pass keeps the watchlist and walks the next listed names', () {
    final pass = nextMarketPass(
      universe: <String>['AAA', 'BBB', 'CCC', 'DDD'],
      cursor: 1,
      priority: <String>['AAPL', 'aapl', 'NVDA'],
      extraPerPass: 2,
    );
    expect(pass.symbols, <String>['AAPL', 'NVDA', 'BBB', 'CCC']);
    expect(pass.nextCursor, 3);
    expect(pass.rangeLabel, '2-3 of 4');
  });

  test('the walk wraps and covers every listed name once', () {
    final universe = <String>['AAA', 'BBB', 'CCC', 'DDD'];
    var cursor = 0;
    final seen = <String>[];
    for (var i = 0; i < universe.length; i++) {
      final pass = nextMarketPass(
        universe: universe,
        cursor: cursor,
        priority: <String>['AAPL'],
        extraPerPass: 1,
      );
      cursor = pass.nextCursor;
      seen.addAll(pass.symbols.where((symbol) => symbol != 'AAPL'));
    }
    expect(seen, universe);
    expect(cursor, 0);
  });

  test('turning the market walk off does not fetch a universe', () async {
    var loads = 0;
    final scan = MarketScan(loadUniverse: () async {
      loads++;
      return <String>['AAA', 'BBB'];
    });
    final pass = await scan.next(
      enabled: false,
      priority: <String>['MSFT'],
      keys: const TradingKeys(keyId: '', secretKey: ''),
      mode: BrokerMode.paper,
    );
    expect(pass.symbols, <String>['MSFT']);
    expect(loads, 0);
  });

  test('an injected list is reused until it expires', () async {
    var loads = 0;
    var now = DateTime.utc(2026, 6, 10, 14);
    final scan = MarketScan(
      clock: () => now,
      loadUniverse: () async {
        loads++;
        return <String>[
          for (var i = 0; i < 40; i++) 'S${i.toString().padLeft(2, '0')}',
        ];
      },
    );
    final keys = const TradingKeys(keyId: '', secretKey: '');
    final first = await scan.next(
      enabled: true,
      priority: <String>['AAPL'],
      keys: keys,
      mode: BrokerMode.paper,
    );
    now = now.add(const Duration(minutes: 1));
    final second = await scan.next(
      enabled: true,
      priority: <String>['AAPL'],
      keys: keys,
      mode: BrokerMode.paper,
    );
    expect(loads, 1);
    expect(first.symbols, contains('S00'));
    expect(first.symbols, isNot(contains('S16')));
    expect(second.symbols, contains('S16'));
    expect(second.symbols, isNot(contains('S00')));
    expect(second.kind, MarketListKind.bundled);
  });

  test('derivative names and attached warrants are not listed stocks', () {
    expect(nameIsDerivative('Apple Inc. Common Stock'), isFalse);
    expect(nameIsDerivative('Foo Warrant'), isTrue);
    expect(nameIsDerivative('Bar Preferred Stock'), isTrue);
    expect(
      dropAttachedIssues(<String>['AACI', 'AACIW', 'AACIU', 'AAPL', 'LOW']),
      <String>['AACI', 'AAPL', 'LOW'],
    );
    expect(
      symbolsFromAlpacaAssets(<dynamic>[
        <String, dynamic>{
          'symbol': 'AAPL',
          'name': 'Apple Inc. Common Stock',
          'status': 'active',
          'tradable': true,
          'class': 'us_equity',
          'exchange': 'NASDAQ',
        },
        <String, dynamic>{
          'symbol': 'AACIW',
          'name': 'Foo Warrant',
          'status': 'active',
          'tradable': true,
          'class': 'us_equity',
          'exchange': 'NASDAQ',
        },
        <String, dynamic>{
          'symbol': 'PINK',
          'name': 'Pink Sheet Co',
          'status': 'active',
          'tradable': true,
          'class': 'us_equity',
          'exchange': 'OTC',
        },
        <String, dynamic>{
          'symbol': 'DEAD',
          'name': 'Dead Co',
          'status': 'inactive',
          'tradable': false,
          'class': 'us_equity',
          'exchange': 'NYSE',
        },
      ]),
      <String>['AAPL'],
    );
  });

  test('nasdaq directories skip test issues and the footer', () {
    const nasdaq = '''
Symbol|Security Name|Market Category|Test Issue|Financial Status|Round Lot Size|ETF|NextShares
AAPL|Apple Inc. - Common Stock|Q|N|N|100|N|N
ZVZZT|NASDAQ TEST STOCK|G|Y|N|100|N|N
File Creation Time: 0622202618:00
''';
    const other = '''
ACT Symbol|Security Name|Exchange|CQS Symbol|ETF|Round Lot Size|Test Issue|NASDAQ Symbol
F|Ford Motor Company|N|F|N|100|N|F
TEST|Test Issue|N|TEST|N|100|Y|TEST
''';
    expect(
      symbolsFromNasdaqDirectories(nasdaq: nasdaq, other: other),
      <String>['AAPL', 'F'],
    );
  });
}
