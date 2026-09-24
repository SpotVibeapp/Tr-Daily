import '../broker/alpaca_broker.dart';
import '../data/models.dart';
import '../risk/risk_manager.dart';
import '../strategy/ensemble.dart';
import 'notifications.dart';
import 'secrets.dart';

/// Which market-data chain to use.
enum DataProviderMode {
  /// Try Yahoo → bundled → synthetic (recommended).
  auto,

  /// Yahoo Finance only.
  yahoo,

  /// Alpaca market data (needs API keys; IEX feed on free plan).
  alpaca,

  /// Deterministic synthetic data (offline demo — never real prices).
  synthetic,
}

/// Whole-app settings, persisted as one JSON blob.
class AppSettings {
  AppSettings({
    this.brokerMode = BrokerMode.paper,
    TradingKeys? keys,
    this.dataProvider = DataProviderMode.auto,
    List<String>? watchlist,
    this.interval = BarInterval.fiveMin,
    this.scanIntervalSeconds = 60,
    this.tradeWhileClosed = false,
    this.startEngineOnLaunch = false,
    this.extendedHours = false,
    RiskConfig? risk,
    EnsembleConfig? ensemble,
    NotificationConfig? notifications,
    this.allowShort = true,
    this.paperStartingCash = 25000,
  })  : keys = keys ?? const TradingKeys(keyId: '', secretKey: ''),
        watchlist = watchlist ?? List<String>.from(defaultWatchlist),
        risk = risk ?? const RiskConfig(),
        ensemble = ensemble ?? const EnsembleConfig(),
        notifications = notifications ?? const NotificationConfig();

  static const List<String> defaultWatchlist = <String>[
    'AAPL',
    'NVDA',
    'TSLA',
    'MSFT',
    'AMZN',
  ];

  BrokerMode brokerMode;
  TradingKeys keys;
  DataProviderMode dataProvider;
  List<String> watchlist;
  BarInterval interval;
  int scanIntervalSeconds;
  bool tradeWhileClosed;
  bool startEngineOnLaunch;

  /// Route orders outside 09:30–16:00 ET (Alpaca 4am–8pm ET).
  bool extendedHours;
  RiskConfig risk;
  EnsembleConfig ensemble;
  NotificationConfig notifications;
  bool allowShort;
  double paperStartingCash;

  bool get liveTrading => brokerMode == BrokerMode.live && keys.isConfigured;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'brokerMode': brokerMode.name,
        'keyId': keys.keyId,
        'secretKey': keys.secretKey,
        'dataProvider': dataProvider.name,
        'watchlist': watchlist,
        'interval': interval.name,
        'scanIntervalSeconds': scanIntervalSeconds,
        'tradeWhileClosed': tradeWhileClosed,
        'startEngineOnLaunch': startEngineOnLaunch,
        'extendedHours': extendedHours,
        'risk': risk.toJson(),
        'ensemble': ensemble.toJson(),
        'notifications': notifications.toJson(),
        'allowShort': allowShort,
        'paperStartingCash': paperStartingCash,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    final defaults = AppSettings();
    final modeName = json['brokerMode'] as String?;
    final dpName = json['dataProvider'] as String?;
    final wl = json['watchlist'];
    final riskJson = json['risk'];
    final ensJson = json['ensemble'];
    final notifJson = json['notifications'];
    final ivName = json['interval'] as String?;
    return AppSettings(
      brokerMode: modeName == 'live' ? BrokerMode.live : BrokerMode.paper,
      keys: TradingKeys(
        keyId: json['keyId'] as String? ?? '',
        secretKey: json['secretKey'] as String? ?? '',
      ),
      dataProvider: dpName == null
          ? DataProviderMode.auto
          : DataProviderMode.values.firstWhere(
              (m) => m.name == dpName,
              orElse: () => DataProviderMode.auto,
            ),
      watchlist: wl is List<dynamic>
          ? wl.map((s) => s.toString().toUpperCase()).toList()
          : List<String>.from(defaultWatchlist),
      interval: BarInterval.values.firstWhere(
        (b) => b.name == ivName,
        orElse: () => BarInterval.fiveMin,
      ),
      scanIntervalSeconds:
          (json['scanIntervalSeconds'] as int?) ?? defaults.scanIntervalSeconds,
      tradeWhileClosed:
          json['tradeWhileClosed'] as bool? ?? defaults.tradeWhileClosed,
      startEngineOnLaunch:
          json['startEngineOnLaunch'] as bool? ?? defaults.startEngineOnLaunch,
      extendedHours: json['extendedHours'] as bool? ?? defaults.extendedHours,
      risk: riskJson is Map<String, dynamic>
          ? RiskConfig.fromJson(riskJson)
          : defaults.risk,
      ensemble: ensJson is Map<String, dynamic>
          ? EnsembleConfig.fromJson(ensJson)
          : defaults.ensemble,
      notifications: notifJson is Map<String, dynamic>
          ? NotificationConfig.fromJson(notifJson)
          : defaults.notifications,
      allowShort: json['allowShort'] as bool? ?? defaults.allowShort,
      paperStartingCash:
          (json['paperStartingCash'] as num?)?.toDouble() ??
              defaults.paperStartingCash,
    );
  }
}
