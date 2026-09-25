import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/broker/alpaca_broker.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/core/server_config.dart';

void main() {
  group('ServerConfig.fromEnvironment', () {
    test('default environment produces safe paper defaults', () {
      final config = ServerConfig.fromEnvironment(<String, String>{});

      expect(config.settings.brokerMode, BrokerMode.paper);
      expect(config.port, 8080);
      expect(config.host, '0.0.0.0');
      expect(config.settings.watchlist, isNotEmpty);
      expect(config.settings.scanIntervalSeconds, 60);
      expect(config.settings.risk.riskPerTradePct, 0.5);
      expect(config.settings.risk.maxOpenPositions, 1);
      expect(config.settings.minSharePrice, 1.0);
      expect(config.settings.minDollarVolume, 1000000);
      expect(config.settings.risk.maxDailyLossPct, 2.0);
      expect(config.settings.fitToBudget, isTrue);
      expect(config.settings.budgetShareCeiling, 5);
      expect(config.settings.dayTradeEdge, isTrue);
      expect(config.settings.minTargetPct, 1);
      expect(config.settings.flattenBeforeClose, isTrue);
      expect(config.settings.scaleWithBalance, isTrue);
      expect(config.settings.allowConvictionRisk, isTrue);
      expect(config.settings.allowOvernightHolds, isFalse);
      expect(config.settings.scanListedMarket, isTrue);
      expect(config.settings.notifications.hasWebhook, isFalse);
    });

    test('custom environment parses all cloud settings correctly', () {
      final env = <String, String>{
        'TR_BROKER_MODE': 'live',
        'ALPACA_KEY_ID': 'PK_TEST_123',
        'ALPACA_SECRET_KEY': 'SECRET_KEY_456',
        'WATCHLIST': 'NVDA,MSFT,TSLA',
        'SCAN_INTERVAL_SECONDS': '30',
        'RISK_PER_TRADE_PCT': '1.5',
        'MAX_DAILY_LOSS_PCT': '3.0',
        'MAX_OPEN_POSITIONS': '4',
        'EXTENDED_HOURS': 'true',
        'DATA_PROVIDER': 'yahoo',
        'WEBHOOK_URL': 'https://discord.com/api/webhooks/999/xyz',
        'TELEGRAM_BOT_TOKEN': '123456:bot-token',
        'TELEGRAM_CHAT_ID': '987654321',
        'PORT': '9090',
        'BIND_HOST': '127.0.0.1',
      };

      final config = ServerConfig.fromEnvironment(env);

      expect(config.settings.brokerMode, BrokerMode.live);
      expect(config.settings.keys.keyId, 'PK_TEST_123');
      expect(config.settings.keys.secretKey, 'SECRET_KEY_456');
      expect(config.settings.watchlist, <String>['NVDA', 'MSFT', 'TSLA']);
      expect(config.settings.scanIntervalSeconds, 30);
      expect(config.settings.risk.riskPerTradePct, 1.5);
      expect(config.settings.risk.maxDailyLossPct, 3.0);
      expect(config.settings.risk.maxOpenPositions, 4);
      expect(config.settings.extendedHours, isTrue);
      expect(config.settings.dataProvider, DataProviderMode.yahoo);

      expect(config.port, 9090);
      expect(config.host, '127.0.0.1');

      expect(config.settings.notifications.webhookUrl, 'https://discord.com/api/webhooks/999/xyz');
      expect(config.settings.notifications.telegramBotToken, '123456:bot-token');
      expect(config.settings.notifications.telegramChatId, '987654321');
      expect(config.settings.notifications.hasWebhook, isTrue);
      expect(config.settings.notifications.hasTelegram, isTrue);
    });
  });
}
