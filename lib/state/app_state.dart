import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../analysis/estimator.dart';
import '../broker/alpaca_broker.dart';
import '../broker/paper_broker.dart';
import '../core/config.dart';
import '../core/notifications.dart';
import '../core/secrets.dart';
import '../data/market_data_source.dart';
import '../data/models.dart';
import '../engine/backtester.dart';
import '../engine/scanner.dart';
import '../engine/trader_engine.dart';
import '../risk/risk_manager.dart';
import '../storage/local_store.dart';
import '../strategy/ensemble.dart';

class LogEntry {
  LogEntry(this.time, this.type, this.message);

  final DateTime time;
  final String type;
  final String message;
}

/// The single source of truth the UI observes. Owns settings, broker,
/// scanner, engine, and persistence.
class AppState extends ChangeNotifier {
  AppState({KeyValueStore? store}) : this.withStore(store ?? MemoryStore());

  AppState.withStore(KeyValueStore store) : _json = JsonStore(store);

  late final JsonStore _json;

  late AppSettings settings;
  late Broker broker;
  late MarketDataSource dataSource;
  late MarketScanner scanner;
  late RiskManager risk;
  late SignalEnsemble ensemble;
  late NotificationService notifications;

  AccountInfo account = const AccountInfo(
    equity: 0,
    cash: 0,
    buyingPower: 0,
    dayTradeCount: 0,
  );
  List<Position> positions = const <Position>[];
  List<SignalScore> signals = const <SignalScore>[];
  List<LogEntry> log = <LogEntry>[];

  TraderEngine? engine;
  bool initialized = false;
  bool scanning = false;
  String? lastError;
  BacktestResult? lastBacktest;
  bool backtestRunning = false;
  String? backtestSymbol;

  static const String _kSettings = 'trdaily.settings.v1';
  static const String _kPaper = 'trdaily.paper.v1';

  // ---------------------------------------------------------------- init

  Future<void> init() async {
    final settingsJson = await _json.readObject(_kSettings);
    settings = settingsJson != null
        ? AppSettings.fromJson(settingsJson)
        : AppSettings();
    // Ensure a persisted snapshot exists so updateSettings can diff against it.
    if (settingsJson == null) {
      await _json.writeObject(_kSettings, settings.toJson());
    }

    ensemble = SignalEnsemble(config: settings.ensemble);
    risk = RiskManager(config: settings.risk);
    notifications = NotificationService(config: settings.notifications);

    dataSource = _buildDataSource(settings);
    scanner = MarketScanner(
      source: dataSource,
      estimator: const TrendEstimator(),
      ensemble: ensemble,
    );

    // Restore or create the broker.
    if (settings.brokerMode == BrokerMode.live && settings.keys.isConfigured) {
      broker = AlpacaBroker(keys: settings.keys, mode: BrokerMode.live);
    } else if (settings.keys.isConfigured) {
      broker = AlpacaBroker(keys: settings.keys, mode: BrokerMode.paper);
    } else {
      final paperJson = await _json.readObject(_kPaper);
      broker = paperJson != null
          ? PaperBroker.fromJson(paperJson)
          : PaperBroker(startingCash: settings.paperStartingCash);
    }

    engine = _buildEngine();
    _wireEngine(engine!);
    await refreshAccount();

    initialized = true;
    _log('info', 'ready · data=${dataSource.id} · broker=${broker.id}');
    if (settings.startEngineOnLaunch) {
      startEngine();
    }
    notifyListeners();
  }

  MarketDataSource _buildDataSource(AppSettings s) {
    final synthetic = SyntheticMarketSource();
    final bundled = BundledCsvSource(
      filesBySymbol: const <String, String>{
        'AAPL': 'assets/sample_data/AAPL_demo.csv',
        'NVDA': 'assets/sample_data/NVDA_demo.csv',
        'MSFT': 'assets/sample_data/MSFT_demo.csv',
        'TSLA': 'assets/sample_data/TSLA_demo.csv',
        'AMZN': 'assets/sample_data/AMZN_demo.csv',
      },
      reader: rootBundle.loadString,
      fallback: synthetic,
    );
    final yahoo = YahooFinanceSource();
    switch (s.dataProvider) {
      case DataProviderMode.auto:
        return CompositeDataSource(<MarketDataSource>[yahoo, bundled, synthetic]);
      case DataProviderMode.yahoo:
        return CompositeDataSource(<MarketDataSource>[yahoo, synthetic]);
      case DataProviderMode.alpaca:
        if (s.keys.isConfigured) {
          return CompositeDataSource(<MarketDataSource>[
            AlpacaDataSource(keys: s.keys),
            yahoo,
            synthetic,
          ]);
        }
        return CompositeDataSource(<MarketDataSource>[yahoo, bundled, synthetic]);
      case DataProviderMode.synthetic:
        return synthetic;
    }
  }

  TraderEngine _buildEngine() => TraderEngine(
        broker: broker,
        source: dataSource,
        scanner: scanner,
        settings: settings,
        risk: risk,
      );

  StreamSubscription<EngineEvent>? _engineSub;

  void _wireEngine(TraderEngine e) {
    // Cancel any previous wiring (engine rebuilds on broker switch).
    unawaited(_engineSub?.cancel());
    _engineSub = e.events.listen((ev) {
      _log(ev.type, ev.message);
      if (ev.type == 'trade' || ev.type == 'exit' || ev.type == 'halt') {
        unawaited(_persistPaper());
        unawaited(refreshAccount());
        _dispatchNotification(ev);
      }
      notifyListeners();
    });
  }

  void _dispatchNotification(EngineEvent ev) {
    if (ev.type == 'trade') {
      notifications.dispatch(
        title: 'Trade executed · ${ev.symbol ?? "Order"}',
        body: ev.message,
        type: NotificationType.tradeFill,
        severity: NotificationSeverity.info,
        symbol: ev.symbol,
      );
    } else if (ev.type == 'exit') {
      final msgLower = ev.message.toLowerCase();
      final isStop = msgLower.contains('stop');
      final isTarget = msgLower.contains('profit');
      notifications.dispatch(
        title: isStop
            ? 'Stop triggered · ${ev.symbol ?? ""}'
            : (isTarget ? 'Target reached · ${ev.symbol ?? ""}' : 'Position closed · ${ev.symbol ?? ""}'),
        body: ev.message,
        type: isStop
            ? NotificationType.stopLoss
            : (isTarget ? NotificationType.takeProfit : NotificationType.tradeFill),
        severity: isTarget ? NotificationSeverity.success : NotificationSeverity.warning,
        symbol: ev.symbol,
      );
    } else if (ev.type == 'halt') {
      notifications.dispatch(
        title: '🚨 Circuit Breaker Halted',
        body: ev.message,
        type: NotificationType.dailyLossHalt,
        severity: NotificationSeverity.critical,
        symbol: ev.symbol,
      );
    }
  }

  // ------------------------------------------------------------ settings

  Future<void> updateSettings(AppSettings next) async {
    // Diff against the last *persisted* snapshot — callers often mutate the
    // live settings object in place, so object identity proves nothing.
    final prev = await _json.readObject(_kSettings);
    final brokerChanged = prev != null &&
        (prev['brokerMode'] != next.brokerMode.name ||
            prev['keyId'] != next.keys.keyId ||
            prev['secretKey'] != next.keys.secretKey);
    final rebuildData =
        prev != null && prev['dataProvider'] != next.dataProvider.name;
    settings = next;
    ensemble.config = settings.ensemble;
    risk.config = settings.risk;
    notifications.config = settings.notifications;
    await _json.writeObject(_kSettings, settings.toJson());

    if (rebuildData) {
      dataSource = _buildDataSource(settings);
      scanner.source = dataSource;
    }
    if (brokerChanged) {
      engine?.stop();
      engine?.dispose();
      broker = _createBroker(settings);
      engine = _buildEngine();
      _wireEngine(engine!);
      await refreshAccount();
    }
    if (broker is PaperBroker) {
      (broker as PaperBroker).setAllowShort(settings.allowShort);
    }
    _log('info', 'settings saved');
    notifyListeners();
  }

  Broker _createBroker(AppSettings s) {
    if (s.keys.isConfigured) {
      return AlpacaBroker(keys: s.keys, mode: s.brokerMode);
    }
    return PaperBroker(startingCash: s.paperStartingCash);
  }

  /// Save Alpaca API credentials (obtained on alpaca.markets — bank linking
  /// happens there, never in this app).
  Future<void> connectAlpaca({
    required String keyId,
    required String secret,
    required BrokerMode mode,
  }) async {
    // Copy-on-write so change detection in updateSettings sees the delta.
    final next = AppSettings.fromJson(settings.toJson());
    next.keys = TradingKeys(keyId: keyId.trim(), secretKey: secret.trim());
    next.brokerMode = mode;
    await updateSettings(next);
    // Verify connectivity.
    final ok = await broker.healthCheck();
    _log(ok ? 'info' : 'error',
        ok ? 'Alpaca connected (${broker.id})' : 'Alpaca connection failed — check keys');
    notifyListeners();
  }

  Future<void> disconnectBroker() async {
    final next = AppSettings.fromJson(settings.toJson());
    next.keys = const TradingKeys(keyId: '', secretKey: '');
    next.brokerMode = BrokerMode.paper;
    await updateSettings(next);
  }

  // ------------------------------------------------------------- engine

  void startEngine() {
    engine?.start();
    notifyListeners();
  }

  void stopEngine() {
    engine?.stop();
    notifyListeners();
  }

  bool get engineRunning => engine?.isRunning ?? false;
  EngineState get engineState => engine?.state ?? EngineState.stopped;

  Future<void> scanNow() async {
    if (scanning) return;
    scanning = true;
    lastError = null;
    notifyListeners();
    try {
      final out = await scanner.scan(
        settings.watchlist,
        interval: settings.interval,
      );
      signals = out.signals;
      if (out.hasErrors) {
        lastError =
            out.errors.entries.map((e) => '${e.key}: ${e.value}').join('; ');
      }
      if (broker is PaperBroker) {
        final pb = broker as PaperBroker;
        for (final s in out.signals) {
          pb.setPrice(s.symbol, s.price);
        }
        await _persistPaper();
      }
      _log('scan',
          'manual scan complete · ${out.signals.length} symbols · source=${out.dataSourceId}');
    } catch (e) {
      lastError = '$e';
      _log('error', 'scan failed: $e');
    } finally {
      scanning = false;
      notifyListeners();
    }
  }

  Future<void> refreshAccount() async {
    try {
      account = await broker.getAccount();
      positions = await broker.getPositions();
      if (engine?.lastSignals.isNotEmpty ?? false) {
        signals = engine!.lastSignals;
      }
      notifyListeners();
    } catch (e) {
      lastError = '$e';
    }
  }

  // ---------------------------------------------------------- backtest

  Future<void> runBacktest(
    String symbol, {
    int bars = 400,
    BarInterval interval = BarInterval.fiveMin,
  }) async {
    if (backtestRunning) return;
    backtestRunning = true;
    backtestSymbol = symbol;
    lastError = null;
    notifyListeners();
    try {
      final bt = Backtester(
        source: dataSource,
        estimator: const TrendEstimator(),
        config: BacktestConfig(
          risk: settings.risk,
          ensemble: settings.ensemble,
          useMl: settings.ensemble.useMl,
        ),
      );
      lastBacktest = await bt.run(symbol: symbol, interval: interval, bars: bars);
      _log('info',
          'backtest $symbol: ${lastBacktest!.metrics.tradeCount} trades, '
          '${lastBacktest!.metrics.returnPct.toStringAsFixed(2)}% '
          '(paper simulation, not a guarantee)');
    } catch (e) {
      lastError = 'backtest failed: $e';
      _log('error', lastError!);
    } finally {
      backtestRunning = false;
      backtestSymbol = null;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ trades

  List<PaperFill> get tradeLog {
    final b = broker;
    if (b is PaperBroker) return List<PaperFill>.from(b.fills.reversed);
    return const <PaperFill>[];
  }

  /// Close an open position immediately via broker market order.
  Future<void> closePosition(String symbol) async {
    try {
      await broker.closePosition(symbol);
      _log('exit', 'manually closed position for $symbol');
      await refreshAccount();
      await _persistPaper();
      notifyListeners();
    } catch (e) {
      lastError = 'failed to close $symbol: $e';
      _log('error', lastError!);
      notifyListeners();
    }
  }

  /// Entry-anchored risk targets/stops for symbol, if managed by the engine.
  PositionMeta? getPositionMeta(String symbol) => engine?.positionMeta[symbol];

  Future<void> resetPaperAccount() async {
    final next = settings;
    engine?.stop();
    engine?.dispose();
    broker = PaperBroker(startingCash: next.paperStartingCash);
    engine = _buildEngine();
    _wireEngine(engine!);
    await _persistPaper();
    await refreshAccount();
    _log('info', 'paper account reset to \$${next.paperStartingCash.toStringAsFixed(0)}');
    notifyListeners();
  }

  Future<void> _persistPaper() async {
    final b = broker;
    if (b is PaperBroker) {
      await _json.writeObject(_kPaper, b.toJson());
    }
  }

  // --------------------------------------------------------------- util

  void _log(String type, String message) {
    log.add(LogEntry(DateTime.now(), type, message));
    if (log.length > 200) log.removeRange(0, log.length - 200);
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  /// Rebuilds UI after imperative tweaks (e.g. risk-manager reset).
  void notifyManually() => notifyListeners();

  @override
  void dispose() {
    // Drop engine events BEFORE disposing — engine.stop() emits one, and its
    // async delivery would otherwise hit notifyListeners() after this
    // ChangeNotifier is disposed (crashed the app-smoke test, and could
    // crash the app itself on shutdown).
    unawaited(_engineSub?.cancel());
    notifications.dispose();
    engine?.stop();
    engine?.dispose();
    super.dispose();
  }
}
