import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:tr_daily/core/notifications.dart';

class _FakeClient extends http.BaseClient {
  http.Request? lastRequest;
  int statusCode = 200;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request is http.Request) {
      lastRequest = request;
    }
    final body = utf8.encode('{"status": "ok"}');
    return http.StreamedResponse(
      Stream<List<int>>.value(body),
      statusCode,
      headers: <String, String>{'content-type': 'application/json'},
    );
  }
}

void main() {
  group('NotificationConfig', () {
    test('default configuration is enabled with default alerts', () {
      const c = NotificationConfig();
      expect(c.enabled, isTrue);
      expect(c.notifyOnFills, isTrue);
      expect(c.notifyOnStops, isTrue);
      expect(c.notifyOnHalts, isTrue);
      expect(c.notifyOnPdt, isTrue);
      expect(c.webhookUrl, isEmpty);
      expect(c.hasWebhook, isFalse);
    });

    test('json roundtrip preserves fields', () {
      const c = NotificationConfig(
        enabled: false,
        notifyOnFills: false,
        notifyOnStops: true,
        notifyOnHalts: true,
        notifyOnPdt: false,
        webhookUrl: 'https://discord.com/api/webhooks/123/abc',
        telegramBotToken: 'token123',
        telegramChatId: 'chat456',
      );
      final json = c.toJson();
      final back = NotificationConfig.fromJson(json);

      expect(back.enabled, isFalse);
      expect(back.notifyOnFills, isFalse);
      expect(back.notifyOnStops, isTrue);
      expect(back.notifyOnHalts, isTrue);
      expect(back.notifyOnPdt, isFalse);
      expect(back.webhookUrl, 'https://discord.com/api/webhooks/123/abc');
      expect(back.telegramBotToken, 'token123');
      expect(back.telegramChatId, 'chat456');
      expect(back.hasWebhook, isTrue);
      expect(back.hasTelegram, isTrue);
    });
  });

  group('NotificationService', () {
    test('filters notifications according to config', () {
      final service = NotificationService(
        config: const NotificationConfig(
          enabled: true,
          notifyOnFills: false,
          notifyOnStops: true,
          notifyOnHalts: true,
        ),
      );

      expect(service.shouldNotify(NotificationType.tradeFill), isFalse);
      expect(service.shouldNotify(NotificationType.stopLoss), isTrue);
      expect(service.shouldNotify(NotificationType.takeProfit), isTrue);
      expect(service.shouldNotify(NotificationType.dailyLossHalt), isTrue);

      service.config = service.config.copyWith(enabled: false);
      expect(service.shouldNotify(NotificationType.stopLoss), isFalse);
      expect(service.shouldNotify(NotificationType.dailyLossHalt), isFalse);
    });

    test('dispatch stores notification in history and tracks unread count', () async {
      final service = NotificationService();

      expect(service.unreadCount, 0);
      expect(service.history, isEmpty);

      final dispatched = await service.dispatch(
        title: 'BOUGHT 10 AAPL',
        body: 'Market order filled @ \$180.00',
        type: NotificationType.tradeFill,
        severity: NotificationSeverity.info,
        symbol: 'AAPL',
      );

      expect(dispatched, isTrue);
      expect(service.history.length, 1);
      expect(service.unreadCount, 1);
      expect(service.history.first.symbol, 'AAPL');
      expect(service.history.first.read, isFalse);

      service.markAllRead();
      expect(service.unreadCount, 0);
      expect(service.history.first.read, isTrue);

      service.clearHistory();
      expect(service.history, isEmpty);
    });

    test('posts Discord webhook with rich embed formatting', () async {
      final mockClient = _FakeClient();

      final service = NotificationService(
        config: const NotificationConfig(
          webhookUrl: 'https://discord.com/api/webhooks/12345/abcdef',
        ),
        client: mockClient,
      );

      await service.dispatch(
        title: 'Stop loss hit',
        body: 'Position in TSLA closed at \$210.00',
        type: NotificationType.stopLoss,
        severity: NotificationSeverity.warning,
        symbol: 'TSLA',
      );

      // Wait a tick for async delivery
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(mockClient.lastRequest, isNotNull);
      expect(mockClient.lastRequest!.url.host, 'discord.com');
      final payload = jsonDecode(mockClient.lastRequest!.body) as Map<String, dynamic>;
      expect(payload['username'], 'Tr-Daily Agent');
      final embeds = payload['embeds'] as List<dynamic>;
      expect(embeds.length, 1);
      final embed = embeds.first as Map<String, dynamic>;
      expect(embed['title'], 'Stop loss hit');
      expect(embed['description'], contains('TSLA'));
    });
  });
}
