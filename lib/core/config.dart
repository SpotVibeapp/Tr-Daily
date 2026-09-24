import '../broker/alpaca_broker.dart';
import '../data/models.dart';
import '../risk/risk_manager.dart';
import '../strategy/ensemble.dart';
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
    RiskConfig? risk,
    EnsembleConfig? ensemble,
    this.allowShort = true,
    this.paperStartingCash = 25000,
  })  : keys = keys ?? const TradingKeys(keyId: '', secretKey: ''),
        watchlist = watchlist ?? List<String>.from(defaultWatchlist),
        risk = risk ?? const RiskConfig(),
        ensemble = ensemble ?? const EnsembleConfig();

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
  RiskConfig risk;
  EnsembleConfig ensemble;
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
        'risk': risk.toJson(),
        'ensemble': ensemble.toJson(),
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
      watchlist: wl is List
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
      risk: riskJson is Map
          ? RiskConfig.fromJson(riskJson.cast<String, dynamic>())
          : defaults.risk,
      ensemble: ensJson is Map
          ? EnsembleConfig.fromJson(ensJson.cast<String, dynamic>())
          : defaults.ensemble,
      allowShort: json['allowShort'] as bool? ?? defaults.allowShort,
      paperStartingCash:
          (json['paperStartingCash'] as num?)?.toDouble() ??
              defaults.paperStartingCash,
    );
  }
}
