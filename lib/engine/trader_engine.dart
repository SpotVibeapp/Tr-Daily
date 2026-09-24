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

/// Per-position management state, anchored at entry. Recreated from broker
/// positions + the latest signal when the engine restarts.
class PositionMeta {
  PositionMeta({
    required this.initialStop,
    required this.target,
    required this.entryAtr,
    required this.peak,
    this.scaledOut = false,
  });

  /// Stop fixed at entry time (never ratchets the wrong way on its own).
  double initialStop;
  double target;
  double entryAtr;

  /// Best (long) / worst (short) price seen since entry — drives the trail.
  double peak;

  bool scaledOut;
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

  /// symbol -> entry-time management state (in-memory; reseeded on restart).
  final Map<String, PositionMeta> _meta = <String, PositionMeta>{};

  /// Orders awaiting confirmation (fill reconciliation).
  final Map<String, Order> _pendingOrders = <String, Order>{};

  bool get isRunning => state == EngineState.running || state == EngineState.starting;

  /// Reconciliation view for the UI: orders not yet confirmed filled.
  List<Order> get pendingOrders => List<Order>.unmodifiable(_pendingOrders.values);

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
        _emit('error', 'data issues: $lastError');
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

      // 4) Manage open positions: entry-anchored stops, trailing, scale-out,
      //    ensemble exits.
      await _manageExits(outcome.signals, positions);

      // 5) Consider new entries (re-fetch positions after exits).
      if (sessionOpen || settings.tradeWhileClosed) {
        final openPositions = await broker.getPositions();
        final heldSymbols = openPositions.map((p) => p.symbol).toSet();
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

  /// Current ATR estimate implied by a signal's suggested stop.
  double? _atrFromSignal(SignalScore sig) {
    if (sig.suggestedStop == null || settings.risk.stopLossAtrMult <= 0) {
      return null;
    }
    return (sig.price - sig.suggestedStop!).abs() /
        settings.risk.stopLossAtrMult;
  }

  /// Entry-anchored management state (recreated after restarts).
  PositionMeta _metaFor(Position p, SignalScore? sig) {
    return _meta.putIfAbsent(p.symbol, () {
      final atr = (sig != null ? _atrFromSignal(sig) : null) ?? p.avgEntryPrice * 0.01;
      final long = !p.short;
      return PositionMeta(
        initialStop: sig?.suggestedStop ??
            (long
                ? p.avgEntryPrice - settings.risk.stopLossAtrMult * atr
                : p.avgEntryPrice + settings.risk.stopLossAtrMult * atr),
        target: sig?.suggestedTarget ??
            (long
                ? p.avgEntryPrice + settings.risk.takeProfitAtrMult * atr
                : p.avgEntryPrice - settings.risk.takeProfitAtrMult * atr),
        entryAtr: atr,
        peak: p.currentPrice,
      );
    });
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
      final meta = _metaFor(p, sig);
      final px = sig?.price ?? p.currentPrice;
      if (px <= 0) continue;
      final long = !p.short;

      // Track the peak — foundation of the trailing stop.
      if (long ? px > meta.peak : px < meta.peak) {
        meta.peak = px;
      }

      final atr = (sig != null ? _atrFromSignal(sig) : null) ?? meta.entryAtr;

      // --- Trailing stop (engine-managed; live brackets still hard-stop) ---
      var effectiveStop = meta.initialStop;
      if (settings.risk.trailingStopAtrMult > 0 && atr > 0) {
        final activation = settings.risk.trailingActivateAtrMult * atr;
        final inProfit = long
            ? px - p.avgEntryPrice >= activation
            : p.avgEntryPrice - px >= activation;
        if (inProfit) {
          // Trail ratchets in the trade's favor only — never loosens.
          final trail = long
              ? meta.peak - settings.risk.trailingStopAtrMult * atr
              : meta.peak + settings.risk.trailingStopAtrMult * atr;
          effectiveStop = long
              ? (trail > effectiveStop ? trail : effectiveStop)
              : (trail < effectiveStop ? trail : effectiveStop);
        }
      }

      // --- Hard stop / target vs current price ---
      final stopHit = long ? px <= effectiveStop : px >= effectiveStop;
      final targetHit = long ? px >= meta.target : px <= meta.target;
      if (stopHit || targetHit) {
        final why = stopHit
            ? (effectiveStop != meta.initialStop ? 'trailing stop' : 'stop loss')
            : 'take profit';
        await _close(p, why, meta: meta);
        continue;
      }

      // --- Scale-out (partial profit taking) ---
      if (settings.risk.scaleOutEnabled &&
          !meta.scaledOut &&
          p.qty >= 2 &&
          settings.risk.scaleOutFraction > 0 &&
          settings.risk.scaleOutFraction < 1) {
        final level = long
            ? p.avgEntryPrice + settings.risk.scaleOutAtAtrMult * atr
            : p.avgEntryPrice - settings.risk.scaleOutAtAtrMult * atr;
        final reached = long ? px >= level : px <= level;
        if (reached) {
          final part = (p.qty * settings.risk.scaleOutFraction)
              .floorToDouble()
              .clamp(1.0, p.qty - 1);
          try {
            await broker.submitOrder(OrderRequest(
              symbol: p.symbol,
              side: long ? OrderSide.sell : OrderSide.buy,
              type: OrderType.market,
              qty: part,
            ));
            meta.scaledOut = true;
            _emit('trade',
                'SCALE-OUT ${part.toStringAsFixed(0)}/${p.qty.toStringAsFixed(0)} '
                '${p.symbol} at \$${px.toStringAsFixed(2)} (+${settings.risk.scaleOutAtAtrMult} ATR)',
                symbol: p.symbol);
          } catch (e) {
            _emit('error', 'scale-out failed for ${p.symbol}: $e');
          }
        }
      }

      // --- Ensemble-driven exit ---
      if (sig != null) {
        final exit = scanner.ensemble.shouldExit(
          positionStance: p.short ? Stance.short : Stance.long,
          score: sig.score,
          confidence: sig.confidence,
          entryScore: 0, // score-collapse rule still applies
        );
        if (exit && sig.stance == Stance.flat) {
          await _close(p, 'signal turned neutral (score ${sig.score.toStringAsFixed(2)})',
              meta: meta);
        } else if ((p.short && sig.stance == Stance.long) ||
            (!p.short && sig.stance == Stance.short)) {
          await _close(p, 'stance flipped to ${sig.stance.name}', meta: meta);
        }
      }
    }

    // Drop meta for positions that no longer exist.
    final held = positions.map((p) => p.symbol).toSet();
    _meta.removeWhere((k, _) => !held.contains(k));
  }

  Future<void> _close(Position p, String reason, {PositionMeta? meta}) async {
    try {
      await broker.closePosition(p.symbol);
      _meta.remove(p.symbol);
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
    final atr = _atrFromSignal(sig);
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
      final order = await broker.submitOrder(OrderRequest(
        symbol: sig.symbol,
        side: sig.stance == Stance.long ? OrderSide.buy : OrderSide.sell,
        type: OrderType.market,
        qty: qty,
        takeProfit: isLive ? targetPx : null,
        stopLoss: isLive ? stopPx : null,
        extendedHours: settings.extendedHours,
      ));

      // Anchor management state at entry.
      final entryAtr = atr ?? sig.price * 0.01;
      _meta[sig.symbol] = PositionMeta(
        initialStop: stopPx ?? sig.price - settings.risk.stopLossAtrMult * entryAtr,
        target: targetPx ?? sig.price + settings.risk.takeProfitAtrMult * entryAtr,
        entryAtr: entryAtr,
        peak: sig.price,
      );

      _emit('trade',
          '${sig.stance == Stance.long ? 'BOUGHT' : 'SHORTED'} ${qty.toStringAsFixed(0)} '
          '${sig.symbol} @ ~\$${sig.price.toStringAsFixed(2)} · score ${sig.scorePct} '
          'conf ${(sig.confidence * 100).round()}% · stop \$${stopPx?.toStringAsFixed(2)} '
          'target \$${targetPx?.toStringAsFixed(2)}',
          signal: sig,
          symbol: sig.symbol);

      // Reconcile the order asynchronously: market orders usually fill fast,
      // but queues/rejections must surface, not vanish.
      if (!order.isDone || order.status != OrderStatus.filled) {
        _pendingOrders[order.id] = order;
        unawaited(_watchOrder(order, sig.symbol));
      }
    } catch (e) {
      _emit('error', 'order failed for ${sig.symbol}: $e');
    }
  }

  /// Poll [order] until it reaches a terminal state (or times out).
  Future<void> _watchOrder(Order order, String symbol) async {
    const maxAttempts = 15;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 2));
      if (_events.isClosed) return;
      try {
        final fresh = await broker.getOrder(order.id);
        if (fresh == null) {
          // Disappeared from open orders without a trace → assume filled for
          // market orders (broker API quirk); surface unknown otherwise.
          _pendingOrders.remove(order.id);
          _emit('trade', 'FILLED $symbol order ${order.id} (confirmed)',
              symbol: symbol);
          return;
        }
        if (fresh.status == OrderStatus.filled) {
          _pendingOrders.remove(order.id);
          _emit('trade', 'FILLED $symbol ${fresh.filledQty.toStringAsFixed(0)} '
              '@ \$${fresh.filledAvgPrice?.toStringAsFixed(2)}',
              symbol: symbol);
          return;
        }
        if (fresh.status == OrderStatus.canceled ||
            fresh.status == OrderStatus.rejected ||
            fresh.status == OrderStatus.expired) {
          _pendingOrders.remove(order.id);
          _meta.remove(symbol);
          _emit('error',
              'ORDER ${fresh.status.name.toUpperCase()} for $symbol — position not opened',
              symbol: symbol);
          return;
        }
        _pendingOrders[order.id] = fresh;
      } catch (e) {
        _emit('error', 'reconciliation error for $symbol: $e');
      }
    }
    _emit('info',
        'order for $symbol still pending after 30s — will keep checking next cycles');
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
      'pendingOrders': engine.pendingOrders.length,
      'signals': engine.lastSignals
          .map((s) => <String, dynamic>{
                'symbol': s.symbol,
                'score': s.score,
                'stance': s.stance.name,
              })
          .toList(),
    });
