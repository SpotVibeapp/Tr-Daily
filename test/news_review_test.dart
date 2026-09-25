import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/analysis/news_review.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/data/models.dart';

void main() {
  final now = DateTime.utc(2026, 9, 24, 15);

  Headline story(String title, {String? symbol, DateTime? published, bool trusted = true}) {
    return Headline(
      title: title,
      symbol: symbol,
      published: published ?? now.subtract(const Duration(hours: 1)),
      trusted: trusted,
      source: 'test',
    );
  }

  SignalScore chart(String symbol, double score, Stance stance) {
    return SignalScore(
      symbol: symbol,
      score: score,
      confidence: 0.6,
      stance: stance,
      reasons: const <String>['chart'],
      price: 100,
      generatedAt: now,
    );
  }

  test('rss parser reads a title, a date, and an escaped character', () {
    const xml = '''
      <rss><channel>
        <item>
          <title><![CDATA[Apple &amp; banks]]></title>
          <pubDate>Wed, 24 Sep 2026 14:00:00 +0000</pubDate>
        </item>
      </channel></rss>
    ''';
    final items = parseRss(xml, symbol: 'AAPL', trusted: true);
    expect(items, hasLength(1));
    expect(items.single.title, 'Apple & banks');
    expect(items.single.published, DateTime.utc(2026, 9, 24, 14));
    expect(items.single.symbol, 'AAPL');
  });

  test('a recent bankruptcy headline blocks and closes a long, not a short', () {
    final review = reviewHeadlines(
      headlines: <Headline>[
        story('Apple files for bankruptcy protection', symbol: 'AAPL'),
      ],
      symbols: <String>['AAPL'],
      now: now,
    );
    final news = review.bySymbol['AAPL']!;
    expect(news.blocksLong, isTrue);
    expect(news.exitLong, isTrue);
    expect(news.exitShort, isFalse);

    final heldLong = decideTrade(
      review: review,
      symbol: 'AAPL',
      chartStance: Stance.long,
      chartScore: 0.2,
      chartConfidence: 0.5,
      enterThreshold: 0.45,
      minConfidence: 0.35,
      heldLong: true,
    );
    expect(heldLong.action, NewsTradeAction.exit);

    final heldShort = decideTrade(
      review: review,
      symbol: 'AAPL',
      chartStance: Stance.short,
      chartScore: -0.2,
      chartConfidence: 0.5,
      enterThreshold: 0.45,
      minConfidence: 0.35,
      heldShort: true,
    );
    expect(heldShort.action, NewsTradeAction.allow);
  });

  test('a denial and a stale story do not close a position', () {
    final denied = reviewHeadlines(
      headlines: <Headline>[
        story('Apple denies bankruptcy rumors', symbol: 'AAPL'),
      ],
      symbols: <String>['AAPL'],
      now: now,
    );
    expect(denied.bySymbol['AAPL']!.exitLong, isFalse);
    expect(denied.bySymbol['AAPL']!.blocksLong, isFalse);

    final stale = reviewHeadlines(
      headlines: <Headline>[
        story(
          'Apple files for bankruptcy protection',
          symbol: 'AAPL',
          published: now.subtract(const Duration(days: 3)),
        ),
      ],
      symbols: <String>['AAPL'],
      now: now,
    );
    expect(stale.bySymbol['AAPL']!.exitLong, isFalse);
    expect(stale.bySymbol['AAPL']!.blocksLong, isFalse);
  });

  test('an undated severe headline blocks a new long but does not close one', () {
    final review = reviewHeadlines(
      headlines: <Headline>[
        const Headline(
          title: 'Tesla earnings miss estimates',
          symbol: 'TSLA',
          trusted: true,
        ),
      ],
      symbols: <String>['TSLA'],
      now: now,
    );
    expect(review.bySymbol['TSLA']!.blocksLong, isTrue);
    expect(review.bySymbol['TSLA']!.exitLong, isFalse);
  });

  test('a dated market-crash headline blocks new trades and does not flatten a book', () {
    final review = reviewHeadlines(
      headlines: <Headline>[
        story('S&P triggers a circuit breaker', published: now.subtract(const Duration(hours: 1))),
      ],
      symbols: <String>['AAPL'],
      now: now,
    );
    expect(review.macro, MacroStance.shock);
    expect(review.blockNewEntries, isTrue);
    final held = decideTrade(
      review: review,
      symbol: 'AAPL',
      chartStance: Stance.long,
      chartScore: 0.8,
      chartConfidence: 0.8,
      enterThreshold: 0.45,
      minConfidence: 0.35,
      heldLong: true,
    );
    expect(held.action, NewsTradeAction.allow);
    final fresh = decideTrade(
      review: review,
      symbol: 'AAPL',
      chartStance: Stance.long,
      chartScore: 0.8,
      chartConfidence: 0.8,
      enterThreshold: 0.45,
      minConfidence: 0.35,
    );
    expect(fresh.action, NewsTradeAction.block);
  });

  test('a failed feed skips new trades and keeps an open position', () {
    final review = NewsReview.unavailable(now, 'timeout');
    expect(review.blockNewEntries, isTrue);
    final fresh = decideTrade(
      review: review,
      symbol: 'NVDA',
      chartStance: Stance.long,
      chartScore: 0.8,
      chartConfidence: 0.8,
      enterThreshold: 0.45,
      minConfidence: 0.35,
    );
    expect(fresh.action, NewsTradeAction.block);
    final held = decideTrade(
      review: review,
      symbol: 'NVDA',
      chartStance: Stance.long,
      chartScore: 0.8,
      chartConfidence: 0.8,
      enterThreshold: 0.45,
      minConfidence: 0.35,
      heldLong: true,
    );
    expect(held.action, NewsTradeAction.allow);
  });

  test('positive news ahead of the chart is a developing idea, not a trade', () {
    final review = reviewHeadlines(
      headlines: <Headline>[
        story('Nvidia upgraded to buy after strong demand', symbol: 'NVDA'),
      ],
      symbols: <String>['NVDA'],
      now: now,
      charts: <String, SignalScore>{'NVDA': chart('NVDA', 0.1, Stance.flat)},
    );
    expect(review.opportunities, isNotEmpty);
    expect(review.opportunities.first.symbol, 'NVDA');
    expect(review.opportunities.first.note, contains('Not a buy'));
    final decision = decideTrade(
      review: review,
      symbol: 'NVDA',
      chartStance: Stance.flat,
      chartScore: 0.1,
      chartConfidence: 0.6,
      enterThreshold: 0.45,
      minConfidence: 0.35,
    );
    expect(decision.action, isNot(NewsTradeAction.promoteLong));
  });

  test('news can promote a chart that is close, and cut size when it disagrees', () {
    final close = reviewHeadlines(
      headlines: <Headline>[
        story('Microsoft earnings beat and raises guidance', symbol: 'MSFT'),
      ],
      symbols: <String>['MSFT'],
      now: now,
      charts: <String, SignalScore>{'MSFT': chart('MSFT', 0.32, Stance.flat)},
    );
    final promoted = decideTrade(
      review: close,
      symbol: 'MSFT',
      chartStance: Stance.flat,
      chartScore: 0.32,
      chartConfidence: 0.6,
      enterThreshold: 0.45,
      minConfidence: 0.35,
    );
    expect(promoted.action, NewsTradeAction.promoteLong);

    final against = reviewHeadlines(
      headlines: <Headline>[
        story('Amazon downgrade on weak demand', symbol: 'AMZN'),
      ],
      symbols: <String>['AMZN'],
      now: now,
    );
    final sized = decideTrade(
      review: against,
      symbol: 'AMZN',
      chartStance: Stance.long,
      chartScore: 0.7,
      chartConfidence: 0.7,
      enterThreshold: 0.45,
      minConfidence: 0.35,
    );
    expect(sized.action, NewsTradeAction.allow);
    expect(sized.sizeMultiplier, 0.5);
  });

  test('a story that gets stronger is marked building', () {
    final review = reviewHeadlines(
      headlines: <Headline>[
        story('Pfizer wins contract and upgraded to buy', symbol: 'PFE'),
      ],
      symbols: <String>['PFE'],
      now: now,
      charts: <String, SignalScore>{'PFE': chart('PFE', 0.05, Stance.flat)},
      previousLean: const <String, double>{'PFE': 0.1},
    );
    expect(review.opportunities.single.building, isTrue);
  });

  test('settings remember the news switch', () {
    expect(AppSettings().useNews, isTrue);
    final saved = AppSettings.fromJson(<String, dynamic>{'useNews': false});
    expect(saved.useNews, isFalse);
    expect(saved.toJson()['useNews'], isFalse);
  });
}
