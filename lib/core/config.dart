import '../broker/alpaca_broker.dart';
import '../data/models.dart';
import '../risk/risk_manager.dart';
import '../strategy/ensemble.dart';
import 'notifications.dart';
import 'secrets.dart';

/// Which market-data chain to use.
enum DataProviderMode {
  /// Alpaca first when keys exist, then Yahoo, bundled, and synthetic.
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
    this.fitToBudget = true,
    this.budgetShareCeiling = 5,
    this.dayTradeEdge = true,
    this.minTargetPct = 1.0,
    this.flattenBeforeClose = true,
    this.scaleWithBalance = true,
    this.allowConvictionRisk = true,
    this.allowOvernightHolds = false,
    this.useLocalPaper = false,
    this.keepRunningWhenClosed = true,
    this.engineArmed = false,
    this.useNews = true,
    this.scanListedMarket = true,
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

  /// Skip names one whole share cannot buy. If nothing on the watchlist
  /// fits, scan listed lower-priced names (see [budgetShareCeiling]).
  bool fitToBudget;

  /// Prefer backup names at or under this share price. 0 uses \$5.
  /// Never overrides the cash cap from [RiskConfig.maxPositionPct].
  double budgetShareCeiling;

  /// Skip setups whose target is too small a percent of price, or whose
  /// forced share size blows past the risk-per-trade setting.
  bool dayTradeEdge;

  /// Minimum target distance as a percent of the share price.
  double minTargetPct;

  /// Sell open positions in the last 15 minutes of the session.
  bool flattenBeforeClose;

  /// Size and strategy band from today's starting equity, not the intraday
  /// mark. A gain or a setback changes the next session, not the middle of
  /// one. Does not guarantee a profit.
  bool scaleWithBalance;

  /// A strong percentage setup may use up to 2× the risk-per-trade setting.
  /// Quiet setups stay at the normal size.
  bool allowConvictionRisk;

  /// Leave positions open past the close. Off by default. Not a long-term
  /// system, and not options trading.
  bool allowOvernightHolds;

  /// Use the local simulator even if Alpaca paper keys are saved. Live mode
  /// still uses the broker. Set when the user picks a test cash amount.
  bool useLocalPaper;

  /// On Android, keep scanning after the app is closed or the screen locks.
  /// A notification stays up. Force Stop in system settings still stops it.
  bool keepRunningWhenClosed;

  /// True after the user starts the engine, until they stop it. Used to
  /// resume after the process is killed, without starting a fresh install.
  bool engineArmed;

  /// Read company and world headlines before every new trade and on each
  /// scan of an open position. Feeds can be late or wrong. This does not
  /// remove the risk of a loss.
  bool useNews;

  /// Walk the listed US market in addition to [watchlist]. The watchlist is
  /// still checked every pass. This is not a download of every chart at once.
  bool scanListedMarket;

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
        'fitToBudget': fitToBudget,
        'budgetShareCeiling': budgetShareCeiling,
        'dayTradeEdge': dayTradeEdge,
        'minTargetPct': minTargetPct,
        'flattenBeforeClose': flattenBeforeClose,
        'scaleWithBalance': scaleWithBalance,
        'allowConvictionRisk': allowConvictionRisk,
        'allowOvernightHolds': allowOvernightHolds,
        'useLocalPaper': useLocalPaper,
        'keepRunningWhenClosed': keepRunningWhenClosed,
        'engineArmed': engineArmed,
        'useNews': useNews,
        'scanListedMarket': scanListedMarket,
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
      fitToBudget: json['fitToBudget'] as bool? ?? defaults.fitToBudget,
      budgetShareCeiling: (json['budgetShareCeiling'] as num?)?.toDouble() ??
          defaults.budgetShareCeiling,
      dayTradeEdge: json['dayTradeEdge'] as bool? ?? defaults.dayTradeEdge,
      minTargetPct: (json['minTargetPct'] as num?)?.toDouble() ??
          defaults.minTargetPct,
      flattenBeforeClose:
          json['flattenBeforeClose'] as bool? ?? defaults.flattenBeforeClose,
      scaleWithBalance:
          json['scaleWithBalance'] as bool? ?? defaults.scaleWithBalance,
      allowConvictionRisk: json['allowConvictionRisk'] as bool? ??
          defaults.allowConvictionRisk,
      allowOvernightHolds: json['allowOvernightHolds'] as bool? ??
          defaults.allowOvernightHolds,
      useLocalPaper:
          json['useLocalPaper'] as bool? ?? defaults.useLocalPaper,
      keepRunningWhenClosed: json['keepRunningWhenClosed'] as bool? ??
          defaults.keepRunningWhenClosed,
      engineArmed: json['engineArmed'] as bool? ?? defaults.engineArmed,
      useNews: json['useNews'] as bool? ?? defaults.useNews,
      scanListedMarket:
          json['scanListedMarket'] as bool? ?? defaults.scanListedMarket,
    );
  }
}
