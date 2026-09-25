import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/secrets.dart';
import '../data/models.dart';

/// Where orders are routed.
enum BrokerMode { paper, live }

/// Pluggable broker contract. Implementations: [PaperBroker] (local
/// simulation) and [AlpacaBroker] (commission-free stock broker API).
abstract class Broker {
  /// Stable id shown in the UI: `paper`, `alpaca-paper`, `alpaca-live`.
  String get id;

  BrokerMode get mode;

  Future<AccountInfo> getAccount();

  Future<List<Position>> getPositions();

  Future<Order> submitOrder(OrderRequest request);

  Future<List<Order>> getOpenOrders();

  /// Fetch a single order by id (used for fill reconciliation).
  Future<Order?> getOrder(String orderId);

  Future<void> cancelOrder(String orderId);

  /// Close a position (market order for the full quantity).
  Future<void> closePosition(String symbol);

  /// Whether the broker is reachable / configured.
  Future<bool> healthCheck();
}

class BrokerException implements Exception {
  BrokerException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'BrokerException($statusCode): $message';
}

/// Alpaca REST broker — free commission-free US stock trading, free paper
/// account, bank linking on their website.
///
/// Paper: https://paper-api.alpaca.markets
/// Live:  https://api.alpaca.markets
class AlpacaBroker implements Broker {
  AlpacaBroker({
    required this.keys,
    required this.mode,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final TradingKeys keys;
  @override
  final BrokerMode mode;
  final http.Client _client;

  String get _base => mode == BrokerMode.paper
      ? 'https://paper-api.alpaca.markets'
      : 'https://api.alpaca.markets';

  @override
  String get id => mode == BrokerMode.paper ? 'alpaca-paper' : 'alpaca-live';

  Map<String, String> get _headers => <String, String>{
        'APCA-API-KEY-ID': keys.keyId,
        'APCA-API-SECRET-KEY': keys.secretKey,
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  Future<Map<String, dynamic>> _req(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.parse('$_base$path');
    final future = switch (method) {
      'GET' => _client.get(uri, headers: _headers),
      'DELETE' => _client.delete(uri, headers: _headers),
      _ => _client.post(uri, headers: _headers, body: jsonEncode(body)),
    };
    final http.Response resp;
    try {
      resp = await future.timeout(const Duration(seconds: 20));
    } catch (e) {
      throw BrokerException('network error: $e');
    }
    if (resp.statusCode >= 400) {
      String msg = resp.body;
      try {
        final decoded = jsonDecode(resp.body) as Map<String, dynamic>;
        msg = decoded['message']?.toString() ?? resp.body;
      } catch (_) {}
      throw BrokerException(msg, statusCode: resp.statusCode);
    }
    if (resp.body.isEmpty) return <String, dynamic>{};
    return jsonDecode(resp.body) as Map<String, dynamic>;
  }

  @override
  Future<bool> healthCheck() async {
    try {
      await getAccount();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AccountInfo> getAccount() async {
    final a = await _req('GET', '/v2/account');
    return AccountInfo(
      equity: _f(a['equity']) ?? 0,
      cash: _f(a['cash']) ?? 0,
      buyingPower: _f(a['buying_power']) ?? 0,
      dayTradeCount: (a['daytrade_count'] as int?) ?? 0,
      lastEquity: _f(a['last_equity']),
      dayPnl: (_f(a['equity']) ?? 0) - (_f(a['last_equity']) ?? 0),
      isBlocked: a['account_blocked'] == true || a['trading_blocked'] == true,
    );
  }

  @override
  Future<List<Position>> getPositions() async {
    // /v2/positions returns a bare JSON array.
    final raw = await _reqRawList('GET', '/v2/positions');
    return raw.map((p) {
      final m = p as Map<String, dynamic>;
      final qty = _f(m['qty']) ?? 0;
      final side = (m['side'] as String?) ?? 'long';
      return Position(
        symbol: (m['symbol'] as String?) ?? '',
        qty: qty.abs(),
        avgEntryPrice: _f(m['avg_entry_price']) ?? 0,
        currentPrice: _f(m['current_price']) ?? 0,
        short: side == 'short',
        realizedPnl: _f(m['unrealized_pl']) ?? 0,
      );
    }).toList();
  }

  @override
  Future<List<Order>> getOpenOrders() async {
    final raw = await _reqRawList('GET', '/v2/orders?status=open&limit=50');
    return raw.map((o) => _parseOrder(o as Map<String, dynamic>)).toList();
  }

  /// Alpaca sometimes returns arrays; _req expects objects — small helper.
  Future<List<dynamic>> _reqRawList(String method, String path) async {
    final uri = Uri.parse('$_base$path');
    final resp = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    if (resp.statusCode >= 400) {
      throw BrokerException('HTTP ${resp.statusCode}: ${resp.body}',
          statusCode: resp.statusCode);
    }
    return jsonDecode(resp.body) as List<dynamic>;
  }

  @override
  Future<Order> submitOrder(OrderRequest request) async {
    final body = <String, dynamic>{
      'symbol': request.symbol,
      'side': request.side == OrderSide.buy ? 'buy' : 'sell',
      'type': switch (request.type) {
        OrderType.market => 'market',
        OrderType.limit => 'limit',
        OrderType.stop => 'stop',
        OrderType.stopLimit => 'stop_limit',
      },
      'time_in_force': switch (request.timeInForce) {
        TimeInForce.day => 'day',
        TimeInForce.gtc => 'gtc',
        TimeInForce.ioc => 'ioc',
        TimeInForce.fok => 'fok',
      },
      'qty': request.qty == null ? null : _numStr(request.qty!),
      'notional': request.notional == null ? null : _numStr(request.notional!),
    }..removeWhere((k, v) => v == null);
    if (request.limitPrice != null) {
      body['limit_price'] = _orderPrice(request.limitPrice!);
    }
    if (request.stopPrice != null) {
      body['stop_price'] = _orderPrice(request.stopPrice!);
    }
    if (request.clientOrderId != null) {
      body['client_order_id'] = request.clientOrderId;
    }
    if (request.extendedHours) {
      body['extended_hours'] = true;
    }
    // Bracket caps the trade at the profit point. OTO keeps the stop and
    // leaves further profit to the engine trail.
    if (request.takeProfit != null && request.stopLoss != null) {
      body['order_class'] = 'bracket';
      body['take_profit'] = <String, dynamic>{
        'limit_price': _orderPrice(request.takeProfit!),
      };
      body['stop_loss'] = <String, dynamic>{
        'stop_price': _orderPrice(request.stopLoss!),
      };
    } else if (request.stopLoss != null) {
      body['order_class'] = 'oto';
      body['stop_loss'] = <String, dynamic>{
        'stop_price': _orderPrice(request.stopLoss!),
      };
    }
    final raw = await _req('POST', '/v2/orders', body: body);
    return _parseOrder(raw);
  }

  Order _parseOrder(Map<String, dynamic> o) => Order(
        id: (o['id'] as String?) ?? '',
        symbol: (o['symbol'] as String?) ?? '',
        side: (o['side'] as String?) == 'sell' ? OrderSide.sell : OrderSide.buy,
        type: switch ((o['type'] as String?) ?? 'market') {
          'limit' => OrderType.limit,
          'stop' => OrderType.stop,
          'stop_limit' => OrderType.stopLimit,
          _ => OrderType.market,
        },
        status: OrderStatus.parse(o['status'] as String?),
        qty: _f(o['qty']),
        filledQty: _f(o['filled_qty']) ?? 0,
        limitPrice: _f(o['limit_price']),
        stopPrice: _f(o['stop_price']),
        filledAvgPrice: _f(o['filled_avg_price']),
        clientOrderId: o['client_order_id'] as String?,
        submittedAt: DateTime.tryParse((o['submitted_at'] as String?) ?? '') ??
            DateTime.now(),
        filledAt: DateTime.tryParse((o['filled_at'] as String?) ?? ''),
      );

  @override
  Future<Order?> getOrder(String orderId) async {
    try {
      final raw = await _req('GET', '/v2/orders/$orderId');
      return _parseOrder(raw);
    } on BrokerException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  @override
  Future<void> cancelOrder(String orderId) async {
    await _req('DELETE', '/v2/orders/$orderId');
  }

  @override
  Future<void> closePosition(String symbol) async {
    final uri = Uri.parse('$_base/v2/positions/$symbol');
    final resp = await _client.delete(uri, headers: _headers).timeout(const Duration(seconds: 20));
    if (resp.statusCode >= 400) {
      throw BrokerException('close failed: ${resp.body}',
          statusCode: resp.statusCode);
    }
  }

  static double? _f(dynamic v) =>
      v == null ? null : double.tryParse(v.toString());

  /// Alpaca wants whole share counts as integers ('10', not '10.0').
  static String _numStr(double v) =>
      v == v.truncateToDouble() ? v.toStringAsFixed(0) : '$v';

  /// Sub-dollar names need four decimals or a one-cent spread is rounded away.
  static String _orderPrice(double v) =>
      v >= 1 ? v.toStringAsFixed(2) : v.toStringAsFixed(4);
}
