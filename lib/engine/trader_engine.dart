import 'dart:async';
import 'dart:convert';

import '../broker/alpaca_broker.dart';
import '../broker/paper_broker.dart';
import '../core/config.dart';
import '../core/time.dart';
import '../data/market_data_source.dart';
import '../data/models.dart';
import '../risk/risk_manager.dart';
import 'scanner.dart';

enum EngineState { stopped, starting, running, halted }

class EngineEvent {
  const EngineEvent(this.type, this.message, {this.signal, this.symbol});

  final String type; // scan | trade | exit | halt | error | info
  final String message;
  final SignalScore? signal;
  final String? symbol;
}

/// The autonomous loop: scan → score → risk-check → execute → manage exits.
///
/// Platform-agnostic (dart:async only) so the same engine can run in the app,
/// a CLI, or a server later. Mobile OSes suspend background work — while the
/// app is foregrounded the engine ticks every [AppSettings.scanIntervalSeconds]
/// during market hours.
class TraderEngine {
  TraderEngine({
    required this.broker,
    required this.source,
    required this.scanner,
    required this.settings,
    required this.risk,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    if (broker is PaperBroker) {
      broker.setAllowShort(settings.allowShort);
    }
  }

  final Broker broker;
  final MarketDataSource source;
  final MarketScanner scanner;
  final AppSettings settings;
  final RiskManager risk;
  final DateTime Function() _clock;

  final StreamController<EngineEvent> _events =
      StreamController<EngineEvent>.broadcast();
  Stream<EngineEvent> get events => _events.stream;

  Timer? _timer;
  EngineState state = EngineState.stopped;
  DateTime? lastScanAt;
  DateTime? lastErrorAt;
  String? lastError;
  int cycleCount = 0;
  List<SignalScore> lastSignals = const <SignalScore>[];

  bool get isRunning => state == EngineState.running || state == EngineState.starting;

  void _emit(String type, String message,
      {SignalScore? signal, String? symbol}) {
    if (_events.isClosed) return;
    _events.add(EngineEvent(type, message, signal: signal, symbol: symbol));
  }

  /// Start the periodic loop. Safe to call when already running.
  void start() {
    if (isRunning) return;
    state = EngineState.starting;
    _emit('info', 'engine starting (${broker.id}, interval ${settings.interval.name})');
    _timer?.cancel();
    _timer = Timer.periodic(
      Duration(seconds: settings.scanIntervalSeconds.clamp(10, 3600)),
      (_) => unawaited(tick()),
    );
    state = EngineState.running;
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    state = EngineState.stopped;
    _emit('info', 'engine stopped');
  }

  /// One full cycle — exposed for manual "Scan now" buttons & tests.
  Future<void> tick({bool force = false}) async {
    final now = _clock();
    if (state == EngineState.stopped && !force) return;
    if (risk.isHalted && state != EngineState.halted) {
      state = EngineState.halted;
    }
    final sessionOpen = isMarketOpen(now);
    if (!sessionOpen && !settings.tradeWhileClosed && !force) {
      _emit('info', 'market closed (${sessionLabel(now)}) — scan skipped');
      return;
    }
    if (risk.isHalted) {
      state = EngineState.halted;
      _emit('halt', 'halted: ${risk.haltReason}');
      return;
    }
    state = EngineState.running;
    cycleCount++;

    try {
      // 1) Fresh prices for every watchlist symbol.
      final outcome = await scanner.scan(
        settings.watchlist,
        interval: settings.interval,
        now: now,
      );
      lastScanAt = now;
      lastSignals = outcome.signals;
      if (outcome.hasErrors) {
        lastError = outcome.errors.entries.map((e) => '${e.key}: ${e.value}').join('; ');
        lastErrorAt = now;
        _emit('error', 'data issues: ${lastError!}');
      }

      // 2) Mark prices into the paper broker (feeds fills & uPnL).
      if (broker is PaperBroker) {
        final pb = broker as PaperBroker;
        pb.rollDay(now);
        for (final s in outcome.signals) {
          pb.setPrice(s.symbol, s.price);
        }
      }

      final account = await broker.getAccount();
      final positions = await broker.getPositions();

      // 3) Daily-loss circuit breaker.
      if (risk.enforceDailyLoss(dayPnlPct: account.dayPnlPct, day: now)) {
        state = EngineState.halted;
        _emit('halt', 'daily loss limit hit — closing positions & halting');
        for (final p in positions) {
          await _safe(() => broker.closePosition(p.symbol));
        }
        return;
      }

      // 4) Manage open positions: ensemble exits, hard stops, targets.
      await _manageExits(outcome.signals, positions);

      // 5) Consider new entries (re-fetch positions after exits).
      if (sessionOpen || settings.tradeWhileClosed) {
        final openPositions = await broker.getPositions();
        final heldSymbols =
            openPositions.map((p) => p.symbol).toSet();
        for (final sig in outcome.signals) {
          if (sig.stance == Stance.flat) continue;
          if (heldSymbols.contains(sig.symbol)) continue;
          await _tryEnter(sig, account, openPositions, now);
        }
      }
      _emit('scan',
          'scan #${outcome.signals.length} symbols · ${outcome.signals.where((s) => s.stance != Stance.flat).length} setups');
    } catch (e) {
      lastError = e.toString();
      lastErrorAt = now;
      _emit('error', 'cycle failed: $e');
    }
  }

  Future<void> _manageExits(
    List<SignalScore> signals,
    List<Position> positions,
  ) async {
    final scoreBySymbol = <String, SignalScore>{
      for (final s in signals) s.symbol: s,
    };
    for (final p in positions) {
      final sig = scoreBySymbol[p.symbol];

      // Hard stop/target vs current price (paper broker only handles these
      // itself on fill; for Alpaca brackets the broker enforces them).
      if (broker is PaperBroker && sig != null) {
        final pb = broker as PaperBroker;
        final px = pb.lastPrice[p.symbol];
        if (px != null && sig.suggestedStop != null && sig.suggestedTarget != null) {
          final stopHit = p.short ? px >= sig.suggestedStop! : px <= sig.suggestedStop!;
          final targetHit = p.short ? px <= sig.suggestedTarget! : px >= sig.suggestedTarget!;
          if (stopHit || targetHit) {
            final why = stopHit ? 'stop loss' : 'take profit';
            await _close(p, why);
            continue;
          }
        }
      }

      // Ensemble-driven exit.
      if (sig != null) {
        final exit = scanner.ensemble.shouldExit(
          positionStance: p.short ? Stance.short : Stance.long,
          score: sig.score,
          confidence: sig.confidence,
          entryScore: 0, // score-collapse rule still applies
        );
        if (exit && sig.stance == Stance.flat) {
          await _close(p, 'signal turned neutral (score ${sig.score.toStringAsFixed(2)})');
        } else if ((p.short && sig.stance == Stance.long) ||
            (!p.short && sig.stance == Stance.short)) {
          await _close(p, 'stance flipped to ${sig.stance.name}');
        }
      }
    }
  }

  Future<void> _close(Position p, String reason) async {
    try {
      await broker.closePosition(p.symbol);
      _emit('exit',
          'CLOSED ${p.symbol} ${p.short ? 'short' : 'long'} — $reason',
          symbol: p.symbol);
    } catch (e) {
      _emit('error', 'failed to close ${p.symbol}: $e');
    }
  }

  Future<void> _tryEnter(
    SignalScore sig,
    AccountInfo account,
    List<Position> positions,
    DateTime now,
  ) async {
    // Recover the ATR the ensemble used for its stop so the risk manager
    // sizes the position against the same stop distance.
    double? atr;
    if (sig.suggestedStop != null && settings.risk.stopLossAtrMult > 0) {
      atr = (sig.price - sig.suggestedStop!).abs() /
          settings.risk.stopLossAtrMult;
    }
    final verdict = risk.entry(
      account: account,
      positions: positions,
      price: sig.price,
      atr: atr,
      stance: sig.stance,
      confidence: sig.confidence,
      day: now,
    );
    if (!verdict.allowed) {
      _emit('info', 'skip ${sig.symbol}: ${verdict.haltReason}');
      return;
    }
    final qty = verdict.suggestedQty;
    if (qty == null || qty < 1) return;

    // Prefer ensemble ATR-based stops when present.
    final stopPx = sig.suggestedStop ?? verdict.stopPrice;
    final targetPx = sig.suggestedTarget ?? verdict.targetPrice;

    try {
      final isLive = broker.mode == BrokerMode.live;
      await broker.submitOrder(OrderRequest(
        symbol: sig.symbol,
        side: sig.stance == Stance.long ? OrderSide.buy : OrderSide.sell,
        type: OrderType.market,
        qty: qty,
        takeProfit: isLive ? targetPx : null,
        stopLoss: isLive ? stopPx : null,
      ));
      _emit('trade',
          '${sig.stance == Stance.long ? 'BOUGHT' : 'SHORTED'} ${qty.toStringAsFixed(0)} '
          '${sig.symbol} @ ~\$${sig.price.toStringAsFixed(2)} · score ${sig.scorePct} '
          'conf ${(sig.confidence * 100).round()}% · stop \$${stopPx?.toStringAsFixed(2)} '
          'target \$${targetPx?.toStringAsFixed(2)}',
          signal: sig,
          symbol: sig.symbol);
    } catch (e) {
      _emit('error', 'order failed for ${sig.symbol}: $e');
    }
  }

  Future<T?> _safe<T>(Future<T> Function() fn) async {
    try {
      return await fn();
    } catch (e) {
      _emit('error', '$e');
      return null;
    }
  }

  void dispose() {
    _timer?.cancel();
    unawaited(_events.close());
  }
}

/// Serialize engine-visible state for debugging (not secrets).
String debugSummary(TraderEngine engine) => jsonEncode(<String, dynamic>{
      'state': engine.state.name,
      'cycles': engine.cycleCount,
      'lastScanAt': engine.lastScanAt?.toIso8601String(),
      'lastError': engine.lastError,
      'signals': engine.lastSignals
          .map((s) => <String, dynamic>{
                'symbol': s.symbol,
                'score': s.score,
                'stance': s.stance.name,
              })
          .toList(),
    });
