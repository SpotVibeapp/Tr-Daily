import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tr_daily/broker/alpaca_broker.dart';
import 'package:tr_daily/core/secrets.dart';
import 'package:tr_daily/data/models.dart';

/// Records requests and plays canned responses — validates Alpaca's wire
/// contract without hitting the network.
class FakeClient extends http.BaseClient {
  final List<http.Request> requests = <http.Request>[];

  /// Object (JSON map) responses, consumed FIFO.
  final List<Map<String, dynamic>> responseQueue = <Map<String, dynamic>>[];

  /// Bare-array responses (Alpaca list endpoints), consumed FIFO.
  final List<List<dynamic>> arrayQueue = <List<dynamic>>[];

  int statusCode = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      requests.add(request);
    }
    final Object body;
    if (arrayQueue.isNotEmpty) {
      body = arrayQueue.removeAt(0);
    } else if (responseQueue.isNotEmpty) {
      body = responseQueue.removeAt(0);
    } else {
      body = <String, dynamic>{};
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

const keys = TradingKeys(keyId: 'PKTEST', secretKey: 'SECRETTEST');

void main() {
  late FakeClient client;
  late AlpacaBroker broker;

  setUp(() {
    client = FakeClient();
    broker = AlpacaBroker(keys: keys, mode: BrokerMode.paper, client: client);
  });

  group('closing a position', () {
    test('cancels that name\'s open orders, then closes', () async {
      broker.cancelSettle = Duration.zero;
      client.arrayQueue.add(<dynamic>[
        <String, dynamic>{
          'id': 'leg-stop',
          'symbol': 'PLUG',
          'side': 'sell',
          'type': 'stop',
          'status': 'held',
          'qty': '6',
          'submitted_at': '2026-06-10T14:30:00Z',
        },
        <String, dynamic>{
          'id': 'other',
          'symbol': 'SOFI',
          'side': 'sell',
          'type': 'limit',
          'status': 'new',
          'qty': '3',
          'submitted_at': '2026-06-10T14:30:00Z',
        },
      ]);
      await broker.closePosition('plug');
      final calls = [
        for (final r in client.requests) '${r.method} ${r.url.path}',
      ];
      expect(calls, <String>[
        'GET /v2/orders',
        'DELETE /v2/orders/leg-stop',
        'DELETE /v2/positions/PLUG',
      ]);
    });
  });

  group('auth & endpoints', () {
    test('account request hits paper base with key headers', () async {
      client.responseQueue.add(<String, dynamic>{
        'equity': '25000.50',
        'cash': '20000',
        'buying_power': '40000',
        'daytrade_count': 2,
        'last_equity': '24800',
        'account_blocked': false,
      });
      final acct = await broker.getAccount();

      expect(client.requests.single.url.toString(),
          'https://paper-api.alpaca.markets/v2/account');
      expect(client.requests.single.headers['APCA-API-KEY-ID'], 'PKTEST');
      expect(client.requests.single.headers['APCA-API-SECRET-KEY'], 'SECRETTEST');
      expect(acct.equity, closeTo(25000.5, 0.001));
      expect(acct.buyingPower, 40000);
      expect(acct.dayTradeCount, 2);
      expect(acct.dayPnl, closeTo(200.5, 0.001));
    });

    test('live mode uses live base url', () async {
      final live = AlpacaBroker(keys: keys, mode: BrokerMode.live, client: client);
      client.responseQueue.add(<String, dynamic>{
        'equity': '1',
        'cash': '1',
        'buying_power': '1',
        'daytrade_count': 0,
      });
      await live.getAccount();
      expect(client.requests.single.url.host, 'api.alpaca.markets');
    });
  });

  group('positions', () {
    test('parses array payload incl. shorts', () async {
      // /v2/positions returns a bare JSON array.
      client.arrayQueue.add(<dynamic>[
        <String, dynamic>{
          'symbol': 'AAPL',
          'qty': '10',
          'side': 'long',
          'avg_entry_price': '190.5',
          'current_price': '195',
          'unrealized_pl': '45',
        },
        <String, dynamic>{
          'symbol': 'TSLA',
          'qty': '-5',
          'side': 'short',
          'avg_entry_price': '250',
          'current_price': '240',
          'unrealized_pl': '50',
        },
      ]);
      final positions = await broker.getPositions();
      expect(positions, hasLength(2));
      expect(positions[0].symbol, 'AAPL');
      expect(positions[0].qty, 10);
      expect(positions[1].short, isTrue);
      expect(positions[1].qty, 5);
      expect(positions[1].currentPrice, 240);
    });
  });

  group('submitOrder payloads', () {
    test('plain market buy', () async {
      client.responseQueue.add(<String, dynamic>{
        'id': 'ord-1',
        'symbol': 'AAPL',
        'side': 'buy',
        'type': 'market',
        'status': 'accepted',
        'qty': '10',
        'submitted_at': '2026-06-10T14:30:00Z',
      });
      final o = await broker.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 10,
      ));
      final req = client.requests.single;
      expect(req.url.path, '/v2/orders');
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      expect(body['symbol'], 'AAPL');
      expect(body['side'], 'buy');
      expect(body['type'], 'market');
      expect(body['time_in_force'], 'day');
      expect(body['qty'], '10');
      expect(body.containsKey('order_class'), isFalse);
      expect(body.containsKey('extended_hours'), isFalse);
      expect(o.status, OrderStatus.accepted);
      expect(o.id, 'ord-1');
    });

    test('bracket order with stops/targets', () async {
      client.responseQueue.add(<String, dynamic>{
        'id': 'ord-2',
        'symbol': 'NVDA',
        'side': 'buy',
        'type': 'market',
        'status': 'accepted',
        'submitted_at': '2026-06-10T14:30:00Z',
      });
      await broker.submitOrder(const OrderRequest(
        symbol: 'NVDA',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 5,
        takeProfit: 140.0,
        stopLoss: 120.0,
      ));
      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      expect(body['order_class'], 'bracket');
      expect(body['take_profit']['limit_price'], '140.00');
      expect(body['stop_loss']['stop_price'], '120.00');
    });

    test('stop without a profit cap is an OTO order', () async {
      client.responseQueue.add(<String, dynamic>{
        'id': 'ord-oto',
        'symbol': 'NVDA',
        'side': 'buy',
        'type': 'market',
        'status': 'accepted',
        'submitted_at': '2026-06-10T14:30:00Z',
      });
      await broker.submitOrder(const OrderRequest(
        symbol: 'NVDA',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 5,
        stopLoss: 120.0,
      ));
      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      expect(body['order_class'], 'oto');
      expect(body.containsKey('take_profit'), isFalse);
      expect(body['stop_loss']['stop_price'], '120.00');
    });

    test('extended hours flag included when requested', () async {
      client.responseQueue.add(<String, dynamic>{
        'id': 'ord-3',
        'symbol': 'AAPL',
        'side': 'buy',
        'type': 'market',
        'status': 'accepted',
        'submitted_at': '2026-06-10T14:30:00Z',
      });
      await broker.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.buy,
        type: OrderType.market,
        qty: 1,
        extendedHours: true,
      ));
      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      expect(body['extended_hours'], isTrue);
    });

    test('limit order carries limit_price', () async {
      client.responseQueue.add(<String, dynamic>{
        'id': 'ord-4',
        'symbol': 'AAPL',
        'side': 'sell',
        'type': 'limit',
        'status': 'accepted',
        'submitted_at': '2026-06-10T14:30:00Z',
      });
      await broker.submitOrder(const OrderRequest(
        symbol: 'AAPL',
        side: OrderSide.sell,
        type: OrderType.limit,
        qty: 3,
        limitPrice: 199.55,
      ));
      final body =
          jsonDecode(client.requests.single.body) as Map<String, dynamic>;
      expect(body['type'], 'limit');
      expect(body['limit_price'], '199.55');
    });
  });

  group('errors', () {
    test('4xx raises BrokerException with broker message', () async {
      client.statusCode = 401;
      client.responseQueue.add(<String, dynamic>{'message': 'invalid key'});
      expect(
        () => broker.getAccount(),
        throwsA(isA<BrokerException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('invalid key'))),
      );
    });
  });

  group('getOrder', () {
    test('404 returns null', () async {
      client.statusCode = 404;
      client.responseQueue.add(<String, dynamic>{'message': 'not found'});
      expect(await broker.getOrder('missing'), isNull);
    });

    test('parses filled order', () async {
      client.responseQueue.add(<String, dynamic>{
        'id': 'ord-9',
        'symbol': 'MSFT',
        'side': 'buy',
        'type': 'market',
        'status': 'filled',
        'qty': '2',
        'filled_qty': '2',
        'filled_avg_price': '420.10',
        'submitted_at': '2026-06-10T14:30:00Z',
        'filled_at': '2026-06-10T14:30:01Z',
      });
      final o = await broker.getOrder('ord-9');
      expect(o, isNotNull);
      expect(o!.status, OrderStatus.filled);
      expect(o.filledAvgPrice, closeTo(420.1, 0.001));
      expect(o.filledAt, isNotNull);
    });
  });
}
