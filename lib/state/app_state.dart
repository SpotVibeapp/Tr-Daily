import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../analysis/estimator.dart';
import '../analysis/news_review.dart';
import '../data/news_feed.dart';
import '../broker/alpaca_broker.dart';
import '../broker/paper_broker.dart';
import '../core/config.dart';
import '../core/notifications.dart';
import '../core/secrets.dart';
import '../core/time.dart';
import '../data/market_data_source.dart';
import '../data/models.dart';
import '../engine/backtester.dart';
import '../engine/budget.dart';
import '../engine/cost_gate.dart';
import '../engine/market_scan.dart';
import '../engine/scan_quality.dart';
import '../engine/keep_alive_hooks.dart';
import '../engine/scanner.dart';
import '../engine/trader_engine.dart';
import '../risk/risk_manager.dart';
import '../storage/local_store.dart';
import '../strategy/ensemble.dart';

Future<String> _readListedSymbols() =>
    rootBundle.loadString('assets/listed_symbols.txt');

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

  /// Shared with the engine so a manual scan and the auto-trader use one
  /// quote cache for the small-account sleeve.
  final BudgetSession budget = BudgetSession();

  /// Shared so a manual scan and the auto-trader continue the same market walk.
  final MarketScan marketScan = MarketScan(
    readBundled: _readListedSymbols,
  );

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
  static const String keepAliveStatusKey = 'trdaily.keepalive.v1';

  /// True when the Android foreground service owns the scan.
  bool backgroundRunning = false;
  Timer? _keepAlivePoll;

  /// Shared with the engine so a manual scan and a tick do not double-fetch.
  final NewsDesk newsDesk = LiveNewsDesk();
  NewsReview? newsReview;
  String? backgroundNewsSummary;

  // ---------------------------------------------------------------- init

  Future<void> init({bool launchEngine = true}) async {
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
    } else if (settings.keys.isConfigured && !settings.useLocalPaper) {
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
    if (launchEngine) {
      final serviceUp =
          KeepAliveHooks.supported && await (KeepAliveHooks.isRunning?.call() ?? Future<bool>.value(false));
      if (serviceUp) {
        backgroundRunning = true;
        _startKeepAlivePoll();
        _log('info', 'Still scanning in the background. Closing the app does not stop it.');
      } else if (settings.startEngineOnLaunch ||
          (settings.engineArmed && settings.keepRunningWhenClosed)) {
        await startEngine();
      }
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
        if (s.keys.isConfigured) {
          return CompositeDataSource(<MarketDataSource>[
            AlpacaDataSource(keys: s.keys),
            yahoo,
            bundled,
            synthetic,
          ]);
        }
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
        budget: budget,
        marketScan: marketScan,
        news: newsDesk,
      );

  StreamSubscription<EngineEvent>? _engineSub;

  void _wireEngine(TraderEngine e) {
    // Cancel any previous wiring (engine rebuilds on broker switch).
    unawaited(_engineSub?.cancel());
    _engineSub = e.events.listen((ev) {
      _log(ev.type, ev.message);
      if (ev.type == 'trade' || ev.type == 'exit' || ev.type == 'halt') {
        // The background service owns the paper file while it is running.
        if (!backgroundRunning) unawaited(_persistPaper());
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
    final wasRunning = backgroundRunning || (engine?.isRunning ?? false);
    final brokerChanged = prev != null &&
        (prev['brokerMode'] != next.brokerMode.name ||
            prev['keyId'] != next.keys.keyId ||
            prev['secretKey'] != next.keys.secretKey ||
            prev['useLocalPaper'] != next.useLocalPaper);
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
    // Switching into live used to rebuild the engine and leave it stopped.
    // If it was already running, start it again. Closing the app is not a stop.
    if (brokerChanged && wasRunning && !backgroundRunning) {
      await startEngine();
    } else if (backgroundRunning) {
      final intervalChanged = prev != null &&
          prev['scanIntervalSeconds'] != settings.scanIntervalSeconds;
      if (!settings.keepRunningWhenClosed) {
        await KeepAliveHooks.stop?.call();
        backgroundRunning = false;
        _keepAlivePoll?.cancel();
        _keepAlivePoll = null;
        engine?.start();
      } else if (intervalChanged || brokerChanged) {
        await KeepAliveHooks.restart?.call(settings.scanIntervalSeconds);
      } else {
        await KeepAliveHooks.send?.call(<String, String>{'cmd': 'reload'});
      }
    }
    notifyListeners();
  }

  Broker _createBroker(AppSettings s) {
    if (s.brokerMode == BrokerMode.live && s.keys.isConfigured) {
      return AlpacaBroker(keys: s.keys, mode: BrokerMode.live);
    }
    if (s.keys.isConfigured && !s.useLocalPaper) {
      return AlpacaBroker(keys: s.keys, mode: BrokerMode.paper);
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
    next.useLocalPaper = false;
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

  Future<void> startEngine() async {
    settings.engineArmed = true;
    await persistSettings();
    if (settings.keepRunningWhenClosed && KeepAliveHooks.supported) {
      final started = await KeepAliveHooks.start?.call(settings.scanIntervalSeconds) ??
          false;
      if (started) {
        engine?.stop();
        backgroundRunning = true;
        _startKeepAlivePoll();
        _log(
          'info',
          settings.liveTrading
              ? 'LIVE engine keeps running if you leave or close the app. Real orders can still be sent until you turn it off, tap Stop on the notification, or the phone is off. A daily loss stop can halt the rest of the day. A profit goal does not. This does not guarantee a profit.'
              : 'Engine keeps running if you leave or close the app. A notification stays up. Force Stop in Android settings still stops it. This does not guarantee a profit.',
        );
        notifyListeners();
        return;
      }
      _log(
        'error',
        'Could not keep the engine alive after the app closes. It will stop if you leave. Allow notifications and unrestricted battery, then start it again.',
      );
    }
    engine?.start();
    notifyListeners();
  }

  Future<void> stopEngine() async {
    settings.engineArmed = false;
    await persistSettings();
    await KeepAliveHooks.stop?.call();
    backgroundRunning = false;
    _keepAlivePoll?.cancel();
    _keepAlivePoll = null;
    engine?.stop();
    await writeKeepAliveStatus(running: false, note: 'Stopped.');
    notifyListeners();
  }

  bool get engineRunning => backgroundRunning || (engine?.isRunning ?? false);
  EngineState get engineState => engine?.state ?? EngineState.stopped;

  Future<void> scanNow() async {
    if (scanning) return;
    scanning = true;
    lastError = null;
    notifyListeners();
    try {
      final pass = await marketScan.next(
        enabled: settings.scanListedMarket,
        priority: settings.watchlist,
        keys: settings.keys,
        mode: settings.brokerMode,
      );
      final out = await scanner.scan(
        pass.symbols,
        interval: settings.interval,
      );
      var merged = out.signals;
      if (out.hasErrors) {
        lastError =
            out.errors.entries.map((e) => '${e.key}: ${e.value}').join('; ');
      }
      if (broker is PaperBroker) {
        final pb = broker as PaperBroker;
        for (final s in out.signals) {
          if (isDemoSource(s.sourceId)) continue;
          pb.setPrice(s.symbol, s.price);
        }
      }
      if (settings.fitToBudget) {
        final acct = await broker.getAccount();
        account = acct;
        if (budget.shouldScreen(
          settings: settings,
          account: acct,
          watchlistSignals: out.signals,
        )) {
          _log(
            'info',
            'Watchlist does not fit this account. Checking listed names you can afford…',
          );
        }
        final advice = await budget.advise(
          settings: settings,
          account: acct,
          watchlistSignals: out.signals,
          source: dataSource,
        );
        if (advice.sleeve.isNotEmpty) {
          final have = merged.map((s) => s.symbol.toUpperCase()).toSet();
          final extra = advice.sleeve.where((s) => !have.contains(s)).toList();
          if (extra.isNotEmpty) {
            final previousSource = scanner.source;
            scanner.source = liveScanSource(dataSource);
            final ScanOutcome sleeveOut;
            try {
              sleeveOut = await scanner.scan(
                extra,
                interval: settings.interval,
              );
            } finally {
              scanner.source = previousSource;
            }
            merged = <SignalScore>[...merged, ...sleeveOut.signals]
              ..sort((a, b) => b.score.abs().compareTo(a.score.abs()));
            if (broker is PaperBroker) {
              final pb = broker as PaperBroker;
              for (final s in sleeveOut.signals) {
                if (isDemoSource(s.sourceId)) continue;
                pb.setPrice(s.symbol, s.price);
              }
            }
            if (sleeveOut.hasErrors) {
              final sleeveError = sleeveOut.errors.entries
                  .map((e) => '${e.key}: ${e.value}')
                  .join('; ');
              lastError = lastError == null
                  ? sleeveError
                  : '$lastError; $sleeveError';
            }
          }
        }
        if (advice.active && advice.summary.isNotEmpty) {
          _log('info', advice.summary);
        }
      }
      signals = merged;
      if (settings.useNews && !backgroundRunning) {
        try {
          newsReview = await newsDesk.review(
            symbols: <String>[
              ...settings.watchlist,
              for (final signal in merged)
                if (signal.stance != Stance.flat) signal.symbol,
            ],
            now: DateTime.now(),
            charts: <String, SignalScore>{
              for (final signal in merged) signal.symbol.toUpperCase(): signal,
            },
          );
        } catch (e) {
          newsReview = NewsReview.unavailable(DateTime.now(), '$e');
        }
      }
      if (broker is PaperBroker && !backgroundRunning) await _persistPaper();
      final range = pass.walkedMarket ? ' · listed ${pass.rangeLabel}' : '';
      _log('scan',
          'manual scan complete · ${merged.length} symbols$range · source=${out.dataSourceId}');
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
    if (backgroundRunning) {
      await KeepAliveHooks.send?.call(<String, String>{
        'cmd': 'close',
        'symbol': symbol,
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));
      await pullKeepAliveStatus();
      return;
    }
    try {
      final now = DateTime.now();
      if (!isMarketOpen(now)) {
        final held = positions
            .where((p) => p.symbol.toUpperCase() == symbol.toUpperCase());
        final position = held.isEmpty ? null : held.first;
        if (position == null) {
          lastError = 'No open position for $symbol';
          _log('error', lastError!);
          notifyListeners();
          return;
        }
        final quotes = await dataSource.getQuotes(<String>[symbol]);
        final request = sessionOrder(
          symbol: position.symbol,
          side: position.short ? OrderSide.buy : OrderSide.sell,
          qty: position.qty,
          regularSession: false,
          quote: quotes[symbol.toUpperCase()],
          allowOutside: (settings.extendedHours && isExtendedSession(now)) ||
              (settings.tradeWhileClosed && broker.mode != BrokerMode.live),
          extendedHours: settings.extendedHours && isExtendedSession(now),
        );
        if (request == null) {
          lastError =
              'No market order for $symbol. The regular session is closed, and there was no bid/ask for a limit.';
          _log('info', lastError!);
          notifyListeners();
          return;
        }
        await broker.submitOrder(request);
        _log(
          'exit',
          'Limit close sent for $symbol at \$${request.limitPrice!.toStringAsFixed(2)}. Not a market order.',
        );
        await refreshAccount();
        await _persistPaper();
        notifyListeners();
        return;
      }
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
    final resume = backgroundRunning;
    if (resume) await KeepAliveHooks.stop?.call();
    backgroundRunning = false;
    final next = settings;
    next.useLocalPaper = true;
    engine?.stop();
    engine?.dispose();
    broker = PaperBroker(startingCash: next.paperStartingCash);
    engine = _buildEngine();
    _wireEngine(engine!);
    await _json.writeObject(_kSettings, settings.toJson());
    await _persistPaper();
    await refreshAccount();
    _log('info', 'paper account reset to \$${next.paperStartingCash.toStringAsFixed(0)}');
    notifyListeners();
    if (resume) await startEngine();
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

  Future<void> persistSettings() =>
      _json.writeObject(_kSettings, settings.toJson());

  Future<void> reloadSettingsFromDisk() async {
    final json = await _json.readObject(_kSettings);
    if (json == null) return;
    settings = AppSettings.fromJson(json);
    engine?.settings = settings;
    risk.config = settings.risk;
    notifications.config = settings.notifications;
    ensemble.config = settings.ensemble;
  }

  Future<void> writeKeepAliveStatus({
    required bool running,
    String? note,
  }) async {
    final lines = log.length <= 20 ? log : log.sublist(log.length - 20);
    await _json.writeObject(keepAliveStatusKey, <String, dynamic>{
      'running': running,
      'note': note ?? '',
      'news': engine?.lastNewsReview?.summary ?? newsReview?.summary ?? '',
      'updatedAt': DateTime.now().toIso8601String(),
      'lines': <Map<String, String>>[
        for (final entry in lines)
          <String, String>{
            'time': entry.time.toIso8601String(),
            'type': entry.type,
            'message': entry.message,
          },
      ],
    });
  }

  Future<void> pullKeepAliveStatus() async {
    final json = await _json.readObject(keepAliveStatusKey);
    if (json == null) return;
    final wasRunning = backgroundRunning;
    backgroundRunning = json['running'] == true;
    if (wasRunning && !backgroundRunning) {
      final disk = await _json.readObject(_kSettings);
      if (disk != null) settings.engineArmed = disk['engineArmed'] == true;
    }
    final rawLines = json['lines'];
    if (rawLines is List) {
      for (final raw in rawLines) {
        if (raw is! Map) continue;
        final message = raw['message']?.toString() ?? '';
        final type = raw['type']?.toString() ?? 'info';
        final time = DateTime.tryParse(raw['time']?.toString() ?? '') ??
            DateTime.now();
        final seen = log.any(
          (entry) => entry.message == message && entry.type == type,
        );
        if (message.isNotEmpty && !seen) {
          log.add(LogEntry(time, type, message));
        }
      }
      if (log.length > 200) log.removeRange(0, log.length - 200);
    }
    if (backgroundRunning && broker is PaperBroker) {
      final paperJson = await _json.readObject(_kPaper);
      if (paperJson != null) {
        broker = PaperBroker.fromJson(paperJson);
        account = await broker.getAccount();
        positions = await broker.getPositions();
      }
    }
    backgroundNewsSummary = json['news']?.toString();
    final note = json['note']?.toString() ?? '';
    if (!backgroundRunning && note.startsWith('Android stopped')) {
      lastError = note;
    }
    notifyListeners();
  }

  void _startKeepAlivePoll() {
    _keepAlivePoll?.cancel();
    _keepAlivePoll = Timer.periodic(const Duration(seconds: 5), (_) {
      unawaited(pullKeepAliveStatus());
    });
    unawaited(pullKeepAliveStatus());
  }

  @override
  void dispose() {
    // Do not stop the foreground service here. Closing the UI is the case
    // the service exists for. Only a Stop from the user clears it.
    _keepAlivePoll?.cancel();
    unawaited(_engineSub?.cancel());
    notifications.dispose();
    engine?.stop();
    engine?.dispose();
    super.dispose();
  }
}
