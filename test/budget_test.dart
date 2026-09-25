import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/data/market_data_source.dart';
import 'package:tr_daily/data/models.dart';
import 'package:tr_daily/engine/budget.dart';
import 'package:tr_daily/engine/scale.dart';
import 'package:tr_daily/risk/risk_manager.dart';

SignalScore sig(String symbol, double price) => SignalScore(
      symbol: symbol,
      score: 0.6,
      confidence: 0.8,
      stance: Stance.long,
      reasons: const <String>[],
      price: price,
      generatedAt: DateTime(2026, 9, 24, 10),
    );

AccountInfo cash(double equity) => AccountInfo(
      equity: equity,
      cash: equity,
      buyingPower: equity,
      dayTradeCount: 0,
    );

void main() {
  group('maxAffordableSharePrice', () {
    test('25% of a 100 dollar account is 25', () {
      expect(
        maxAffordableSharePrice(cash(100), const RiskConfig()),
        25,
      );
    });

    test('buying power of zero cannot open a share', () {
      expect(
        maxAffordableSharePrice(
          const AccountInfo(
            equity: 100,
            cash: 100,
            buyingPower: 0,
            dayTradeCount: 0,
          ),
          const RiskConfig(),
        ),
        0,
      );
    });

    test('uses the tighter of the position cap and buying power', () {
      expect(
        maxAffordableSharePrice(
          const AccountInfo(
            equity: 100,
            cash: 100,
            buyingPower: 10,
            dayTradeCount: 0,
          ),
          const RiskConfig(),
        ),
        10,
      );
    });
  });

  group('pickSleeve', () {
    test('prefers names at or under 5 when any fit', () {
      final sleeve = pickSleeve(
        quotes: const <String, double>{
          'NOK': 4.2,
          'PLUG': 2.4,
          'F': 11,
          'T': 22,
        },
        maxSharePrice: 25,
        preferredCeiling: 5,
      );
      expect(sleeve, contains('NOK'));
      expect(sleeve, contains('PLUG'));
      expect(sleeve, isNot(contains('F')));
      expect(sleeve, isNot(contains('T')));
    });

    test('fills up to the cash cap when nothing is under the preferred price', () {
      final sleeve = pickSleeve(
        quotes: const <String, double>{
          'F': 11,
          'T': 18,
          'PLUG': 8,
          'NOK': 6,
        },
        maxSharePrice: 25,
        preferredCeiling: 5,
      );
      expect(sleeve, isNotEmpty);
      expect(sleeve, contains('F'));
      expect(sleeve.every((s) => s != 'AAPL'), isTrue);
    });

    test('drops sub-dollar names and names above the cash cap', () {
      final sleeve = pickSleeve(
        quotes: const <String, double>{
          'NOK': 0.4,
          'PLUG': 2.5,
          'F': 40,
        },
        maxSharePrice: 3,
        preferredCeiling: 5,
      );
      expect(sleeve, <String>['PLUG']);
    });

    test('does not re-add a symbol the user already watches', () {
      final sleeve = pickSleeve(
        quotes: const <String, double>{'NOK': 3, 'PLUG': 2},
        maxSharePrice: 25,
        preferredCeiling: 5,
        exclude: <String>{'NOK'},
      );
      expect(sleeve, isNot(contains('NOK')));
      expect(sleeve, contains('PLUG'));
    });
  });

  group('BudgetSession.advise', () {
    test('large account keeps the watchlist and does not add a sleeve', () async {
      final session = BudgetSession(
        quotesFor: (_) async => const <String, double>{'NOK': 3},
      );
      final advice = await session.advise(
        settings: AppSettings(watchlist: <String>['AAPL', 'NVDA']),
        account: cash(25000),
        watchlistSignals: <SignalScore>[sig('AAPL', 190), sig('NVDA', 120)],
        source: SyntheticMarketSource(),
      );
      expect(advice.active, isFalse);
      expect(advice.sleeve, isEmpty);
      expect(advice.maxSharePrice, 6250);
    });

    test('large account still scans lower-priced names when scaling is on',
        () async {
      final session = BudgetSession(
        quotesFor: (_) async => const <String, double>{
          'NOK': 3.2,
          'F': 12,
          'T': 22,
          'INTC': 40,
        },
      );
      final settings = AppSettings(
        watchlist: <String>['AAPL', 'NVDA'],
        scaleWithBalance: true,
      );
      final account = cash(25000);
      final plan = scalePlan(account: account, settings: settings);
      final advice = await session.advise(
        settings: settings,
        account: account,
        watchlistSignals: <SignalScore>[sig('AAPL', 190), sig('NVDA', 120)],
        source: SyntheticMarketSource(),
        plan: plan,
      );
      expect(plan.keepLowerPriced, isTrue);
      expect(advice.sleeve, contains('NOK'));
      expect(advice.sleeve, contains('F'));
      expect(advice.skipped, isEmpty);
      expect(advice.summary, contains('lower-priced'));
    });

    test('100 dollar account skips mega-caps and scans sub-5 names', () async {
      var quoted = false;
      final session = BudgetSession(
        quotesFor: (_) async {
          quoted = true;
          return const <String, double>{
            'NOK': 4.2,
            'PLUG': 2.4,
            'F': 12,
            'T': 22,
          };
        },
      );
      final settings = AppSettings(
        watchlist: <String>['AAPL', 'NVDA', 'TSLA', 'MSFT', 'AMZN'],
        fitToBudget: true,
        budgetShareCeiling: 5,
      );
      final advice = await session.advise(
        settings: settings,
        account: cash(100),
        watchlistSignals: <SignalScore>[
          sig('AAPL', 190),
          sig('NVDA', 120),
          sig('TSLA', 250),
          sig('MSFT', 420),
          sig('AMZN', 180),
        ],
        source: SyntheticMarketSource(),
      );
      expect(quoted, isTrue);
      expect(advice.active, isTrue);
      expect(advice.maxSharePrice, 25);
      expect(advice.skipped, contains('AAPL'));
      expect(advice.sleeve, containsAll(<String>['NOK', 'PLUG']));
      expect(advice.sleeve, isNot(contains('F')));
      expect(advice.summary, contains('NOK'));
      expect(advice.summary, contains('Shorts are skipped'));
    });

    test('a cheap name already on the watchlist is kept; sleeve stays off', () async {
      final session = BudgetSession(
        quotesFor: (_) async => const <String, double>{'PLUG': 2},
      );
      final advice = await session.advise(
        settings: AppSettings(watchlist: <String>['AAPL', 'NOK']),
        account: cash(100),
        watchlistSignals: <SignalScore>[sig('AAPL', 190), sig('NOK', 4)],
        source: SyntheticMarketSource(),
      );
      expect(advice.sleeve, isEmpty);
      expect(advice.skipped, <String>['AAPL']);
      expect(advice.summary, contains('NOK'));
    });

    test('fit-to-cash off does not change a small account', () async {
      final session = BudgetSession(
        quotesFor: (_) async => const <String, double>{'NOK': 3},
      );
      final advice = await session.advise(
        settings: AppSettings(
          watchlist: <String>['AAPL'],
          fitToBudget: false,
        ),
        account: cash(100),
        watchlistSignals: <SignalScore>[sig('AAPL', 190)],
        source: SyntheticMarketSource(),
      );
      expect(advice.active, isFalse);
      expect(advice.sleeve, isEmpty);
    });

    test('no live quotes means no invented sleeve', () async {
      final session = BudgetSession(
        quotesFor: (_) async => <String, double>{},
      );
      final advice = await session.advise(
        settings: AppSettings(watchlist: <String>['AAPL']),
        account: cash(100),
        watchlistSignals: <SignalScore>[sig('AAPL', 190)],
        source: SyntheticMarketSource(),
      );
      expect(advice.sleeve, isEmpty);
      expect(advice.summary, contains('unavailable'));
    });
  });

  test('liveScanSource does not hand sleeve scans to the demo generator', () {
    final yahoo = YahooFinanceSource();
    final composite = CompositeDataSource(<MarketDataSource>[
      yahoo,
      SyntheticMarketSource(),
    ]);
    expect(liveScanSource(composite), same(yahoo));
    expect(liveScanSource(SyntheticMarketSource()), isA<SyntheticMarketSource>());
  });

  test('liveQuotes ignores synthetic demo prices', () async {
    final quotes = await liveQuotes(
      CompositeDataSource(<MarketDataSource>[SyntheticMarketSource()]),
      <String>['F', 'NOK'],
    );
    expect(quotes, isEmpty);
  });
}
