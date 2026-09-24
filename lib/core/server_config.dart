import '../broker/alpaca_broker.dart';
import '../risk/risk_manager.dart';
import '../strategy/ensemble.dart';
import 'config.dart';
import 'notifications.dart';
import 'secrets.dart';

/// Configuration parsed for running Tr-Daily headlessly in cloud or CLI environments.
class ServerConfig {
  const ServerConfig({
    required this.settings,
    this.port = 8080,
    this.host = '0.0.0.0',
    this.configFile,
  });

  final AppSettings settings;
  final int port;
  final String host;
  final String? configFile;

  /// Loads configuration by combining environment variables with default settings.
  factory ServerConfig.fromEnvironment(Map<String, String> env) {
    final modeStr = (env['TR_BROKER_MODE'] ?? env['BROKER_MODE'] ?? 'paper').toLowerCase();
    final brokerMode = modeStr == 'live' ? BrokerMode.live : BrokerMode.paper;

    final keyId = env['ALPACA_KEY_ID'] ?? env['APCA_API_KEY_ID'] ?? '';
    final secretKey = env['ALPACA_SECRET_KEY'] ?? env['APCA_API_SECRET_KEY'] ?? '';

    final watchlistRaw = env['WATCHLIST'] ?? env['TR_WATCHLIST'];
    final watchlist = watchlistRaw != null && watchlistRaw.trim().isNotEmpty
        ? watchlistRaw
            .split(',')
            .map((s) => s.trim().toUpperCase())
            .where((s) => s.isNotEmpty)
            .toList()
        : List<String>.from(AppSettings.defaultWatchlist);

    final scanInterval = int.tryParse(env['SCAN_INTERVAL_SECONDS'] ?? '60') ?? 60;
    final riskPerTrade = double.tryParse(env['RISK_PER_TRADE_PCT'] ?? '1.0') ?? 1.0;
    final maxDailyLoss = double.tryParse(env['MAX_DAILY_LOSS_PCT'] ?? '2.0') ?? 2.0;
    final maxPositions = int.tryParse(env['MAX_OPEN_POSITIONS'] ?? '5') ?? 5;
    final extendedHours = (env['EXTENDED_HOURS'] ?? 'false').toLowerCase() == 'true';
    final allowShort = (env['ALLOW_SHORT'] ?? 'true').toLowerCase() != 'false';

    final dpStr = (env['DATA_PROVIDER'] ?? 'auto').toLowerCase();
    final dataProvider = switch (dpStr) {
      'yahoo' => DataProviderMode.yahoo,
      'alpaca' => DataProviderMode.alpaca,
      'synthetic' => DataProviderMode.synthetic,
      _ => DataProviderMode.auto,
    };

    final webhookUrl = env['WEBHOOK_URL'] ?? env['DISCORD_WEBHOOK_URL'] ?? '';
    final tgToken = env['TELEGRAM_BOT_TOKEN'] ?? '';
    final tgChatId = env['TELEGRAM_CHAT_ID'] ?? '';

    final port = int.tryParse(env['PORT'] ?? '8080') ?? 8080;
    final host = env['BIND_HOST'] ?? '0.0.0.0';

    final settings = AppSettings(
      brokerMode: brokerMode,
      keys: TradingKeys(keyId: keyId, secretKey: secretKey),
      dataProvider: dataProvider,
      watchlist: watchlist,
      scanIntervalSeconds: scanInterval,
      extendedHours: extendedHours,
      allowShort: allowShort,
      risk: RiskConfig(
        riskPerTradePct: riskPerTrade,
        maxDailyLossPct: maxDailyLoss,
        maxOpenPositions: maxPositions,
      ),
      ensemble: const EnsembleConfig(),
      notifications: NotificationConfig(
        enabled: true,
        notifyOnFills: true,
        notifyOnStops: true,
        notifyOnHalts: true,
        notifyOnPdt: true,
        webhookUrl: webhookUrl,
        telegramBotToken: tgToken,
        telegramChatId: tgChatId,
      ),
    );

    return ServerConfig(
      settings: settings,
      port: port,
      host: host,
      configFile: env['TR_CONFIG_FILE'],
    );
  }
}
