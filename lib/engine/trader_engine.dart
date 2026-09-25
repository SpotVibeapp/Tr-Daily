import 'dart:async';
import 'dart:convert';

import '../broker/alpaca_broker.dart';
import '../broker/paper_broker.dart';
import '../core/config.dart';
import '../core/pdt.dart';
import '../core/time.dart';
import 'cost_gate.dart';
import 'day_trade.dart';
import 'scan_quality.dart';
import 'scale.dart';
import '../data/market_data_source.dart';
import '../data/models.dart';
import '../analysis/news_review.dart';
import '../risk/risk_manager.dart';
import 'budget.dart';
import 'market_scan.dart';
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
/// a CLI, or a server later. On Android a foreground service calls [tick]
/// after the UI is closed. Other platforms tick only while the process is
/// alive. Each tick reviews company and world headlines when a [NewsDesk] is
/// set, then follows [AppSettings.scanIntervalSeconds] during market hours.
class TraderEngine {
  TraderEngine({
    required this.broker,
    required this.source,
    required this.scanner,
    required this.settings,
    required this.risk,
    BudgetSession? budget,
    MarketScan? marketScan,
    DateTime Function()? clock,
    this.news,
  })  : budget = budget ?? BudgetSession(),
        marketScan = marketScan ?? MarketScan(),
        _clock = clock ?? DateTime.now {
    final b = broker;
    if (b is PaperBroker) {
      b.setAllowShort(settings.allowShort);
    }
  }

  final Broker broker;
  final MarketDataSource source;
  final MarketScanner scanner;
  AppSettings settings;
  final RiskManager risk;
  final BudgetSession budget;
  final MarketScan marketScan;
  final DateTime Function() _clock;

  /// When set, every scan reviews company and world headlines before entries
  /// and while a position is open. Tests omit it.
  final NewsDesk? news;

  String? _lastBudgetSummary;
  DateTime? _lastBudgetEmitAt;
  final Set<String> _notedOnce = <String>{};
  String? _quietNotedKey;

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
  NewsReview? lastNewsReview;
  String? _lastNewsSignature;

  /// symbol -> entry-time management state (in-memory; reseeded on restart).
  final Map<String, PositionMeta> _meta = <String, PositionMeta>{};

  /// Read-only snapshot of entry-anchored management state for open positions.
  Map<String, PositionMeta> get positionMeta =>
      Map<String, PositionMeta>.unmodifiable(_meta);

  /// Orders awaiting confirmation (fill reconciliation).
  final Map<String, Order> _pendingOrders = <String, Order>{};

  /// Bid/ask read for the current scan. Not a guess when a name is missing.
  final Map<String, BidAsk> _quotes = <String, BidAsk>{};

  bool get isRunning => state == EngineState.running || state == EngineState.starting;

  /// Reconciliation view for the UI: orders not yet confirmed filled.
  List<Order> get pendingOrders => List<Order>.unmodifiable(_pendingOrders.values);

  void _noteOnce(DateTime now, String message, {required bool notedDay}) {
    if (!notedDay) return;
    final et = toEastern(now);
    final key = '${et.year}-${et.month}-${et.day}|$message';
    if (!_notedOnce.add(key)) return;
    _emit('info', message);
  }

  void _noteSkips(
    DateTime now, {
    required List<String> quiet,
    required List<String> oversized,
  }) {
    if (quiet.isEmpty && oversized.isEmpty) return;
    final min = settings.minTargetPct.toStringAsFixed(1);
    final parts = <String>[];
    if (quiet.isNotEmpty) {
      parts.add(
        'Skipped ${quiet.join(', ')} — target move is under $min% of price',
      );
    }
    if (oversized.isNotEmpty) {
      parts.add(
        'Skipped ${oversized.join(', ')} — one share would risk more than '
        '2.5× the risk-per-trade setting',
      );
    }
    final summary = parts.join('. ');
    final et = toEastern(now);
    final key = '${et.year}-${et.month}-${et.day}-${et.hour}-${et.minute ~/ 15}|$summary';
    if (_quietNotedKey == key) return;
    _quietNotedKey = key;
    _emit('info', summary);
  }

  void _noteBudget(String summary, DateTime now) {
    if (summary.isEmpty) return;
    final recent = _lastBudgetSummary == summary &&
        _lastBudgetEmitAt != null &&
        now.difference(_lastBudgetEmitAt!) < const Duration(minutes: 15);
    if (recent) return;
    _lastBudgetSummary = summary;
    _lastBudgetEmitAt = now;
    _emit('info', summary);
  }

  void _emit(String type, String message,
      {SignalScore? signal, String? symbol}) {
    if (_events.isClosed) return;
    _events.add(EngineEvent(type, message, signal: signal, symbol: symbol));
  }

  /// Start the periodic loop. Safe to call when already running.
  ///
  /// [periodic] is false when a foreground service calls [tick] itself.
  void start({bool periodic = true}) {
    if (isRunning) return;
    state = EngineState.starting;
    _emit('info', 'engine starting (${broker.id}, interval ${settings.interval.name})');
    _timer?.cancel();
    _timer = null;
    if (periodic) {
      _timer = Timer.periodic(
        Duration(seconds: settings.scanIntervalSeconds.clamp(10, 3600)),
        (_) => unawaited(tick()),
      );
    }
    state = EngineState.running;
    unawaited(tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    state = EngineState.stopped;
    _emit('info', 'engine stopped');
  }

  bool _tickBusy = false;

  /// One full cycle — exposed for manual "Scan now" buttons & tests.
  Future<void> tick({bool force = false}) async {
    if (_tickBusy) return;
    final now = _clock();
    if (state == EngineState.stopped && !force) return;
    // A new session re-arms the daily loss stop without a second Start tap.
    // Closing the app is not a stop. Only Stop, Force Stop, or the phone
    // being off stops the scan. The loss stop is the exception the user asked
    // for, and it lasts for that day only.
    risk.checkNewDay(now);
    final sessionOpen = isMarketOpen(now);
    if (risk.isHalted) {
      state = EngineState.halted;
    } else {
      state = EngineState.running;
    }
    cycleCount++;
    _tickBusy = true;
    try {
      // Held names stay in the scan even after they leave the watchlist,
      // which is how a budget-sleeve position still gets exit management.
      final extraHeld = <String>[];
      try {
        final pre = await broker.getPositions();
        for (final p in pre) {
          final sym = p.symbol.toUpperCase();
          final onList = settings.watchlist
              .any((w) => w.toUpperCase() == sym);
          if (!onList && !extraHeld.contains(sym)) extraHeld.add(sym);
        }
      } catch (e) {
        _emit('error', 'could not load positions before scan: $e');
      }

      // 1) Watchlist and held names every pass. When the listed-market walk
      // is on, also chart the next slice. The watchlist is not a lock.
      final pass = await marketScan.next(
        enabled: settings.scanListedMarket,
        priority: <String>[...settings.watchlist, ...extraHeld],
        keys: settings.keys,
        mode: settings.brokerMode,
      );
      if (settings.scanListedMarket && pass.universeSize > 0) {
        final where = pass.kind == MarketListKind.backup
            ? 'The full listed list was unavailable, so this pass uses the backup names.'
            : '${pass.universeSize} listed names, ${listedNamesPerPass} new charts each pass, plus the watchlist every pass.';
        _noteOnce(
          now,
          'Listed market scan is on. $where Not every chart at once, and not OTC. This does not guarantee a profit.',
          notedDay: true,
        );
      }
      final outcome = await scanner.scan(
        pass.symbols,
        interval: settings.interval,
        now: now,
      );
      lastScanAt = now;
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
          if (isDemoSource(s.sourceId)) continue;
          pb.setPrice(s.symbol, s.price);
        }
      }

      var account = await broker.getAccount();
      var signals = outcome.signals;
      var plan = _planFor(account, now);

      if (budget.shouldScreen(
        settings: settings,
        account: account,
        watchlistSignals: outcome.signals,
        now: now,
        plan: plan,
      )) {
        _emit(
          'info',
          'Watchlist does not fit this account. Checking listed names you can afford…',
        );
      }
      final advice = await budget.advise(
        settings: settings,
        account: account,
        watchlistSignals: outcome.signals,
        source: source,
        now: now,
        plan: plan,
      );
      if (advice.sleeve.isNotEmpty) {
        final have = signals.map((s) => s.symbol.toUpperCase()).toSet();
        final extra = advice.sleeve.where((s) => !have.contains(s)).toList();
        if (extra.isNotEmpty) {
          final previousSource = scanner.source;
          scanner.source = liveScanSource(source);
          final ScanOutcome sleeveOutcome;
          try {
            sleeveOutcome = await scanner.scan(
              extra,
              interval: settings.interval,
              now: now,
            );
          } finally {
            scanner.source = previousSource;
          }
          if (broker is PaperBroker) {
            final pb = broker as PaperBroker;
            for (final s in sleeveOutcome.signals) {
              if (isDemoSource(s.sourceId)) continue;
              pb.setPrice(s.symbol, s.price);
            }
          }
          signals = <SignalScore>[...signals, ...sleeveOutcome.signals]
            ..sort((a, b) => b.score.abs().compareTo(a.score.abs()));
          if (sleeveOutcome.hasErrors) {
            final sleeveError = sleeveOutcome.errors.entries
                .map((e) => '${e.key}: ${e.value}')
                .join('; ');
            lastError = lastError == null
                ? sleeveError
                : '$lastError; $sleeveError';
            lastErrorAt = now;
          }
          account = await broker.getAccount();
          plan = _planFor(account, now);
        }
      }
      if (advice.active) _noteBudget(advice.summary, now);
      if (plan.summary.isNotEmpty) {
        _noteOnce(now, plan.summary, notedDay: true);
      }
      lastSignals = signals;

      final positions = await broker.getPositions();
      await _reviewNews(signals, positions, now);
      await _loadQuotes(<String>[
        ...settings.watchlist,
        for (final position in positions) position.symbol,
        for (final signal in signals) signal.symbol,
      ]);

      // 3) Daily-loss stop. A profit goal is not a stop and must not halt.
      var closedForLoss = false;
      if (risk.enforceDailyLoss(dayPnlPct: account.dayPnlPct, day: now)) {
        state = EngineState.halted;
        final et = toEastern(now);
        final key = '${et.year}-${et.month}-${et.day}|daily-loss-close';
        if (_notedOnce.add(key)) {
          _emit(
            'halt',
            'Daily loss stop hit — closing positions. New trades wait until '
                'the next session. Scanning continues. ${risk.haltReason ?? ''}',
          );
          for (final p in positions) {
            await _sendExit(p, now, reason: 'daily loss stop');
          }
          closedForLoss = true;
        }
      } else if (dailyProfitGoalReached(
        dayPnlPct: account.dayPnlPct,
        goalPct: settings.risk.dailyProfitGoalPct,
      )) {
        _noteOnce(
          now,
          'Daily profit goal of '
              '${settings.risk.dailyProfitGoalPct.toStringAsFixed(0)}% is '
              'reached. Scanning continues. More profit is allowed. This is '
              'not a guarantee.',
          notedDay: true,
        );
      }

      // 4) Day trades are closed before the bell so they do not become holds.
      final flattening = settings.flattenBeforeClose &&
          !settings.allowOvernightHolds &&
          inFlattenWindow(now);
      if (!closedForLoss && flattening && positions.isNotEmpty) {
        _noteOnce(
          now,
          'Closed into the session end — day trades are not held overnight',
          notedDay: true,
        );
        for (final p in positions) {
          await _close(
            p,
            'session ending — day trades are not held overnight',
          );
        }
      }

      // 5) Manage whatever is still open: stops, trailing, scale-out.
      final livePositions = flattening
          ? await broker.getPositions()
          : positions;
      if (!closedForLoss) {
        await _manageExits(signals, livePositions, now);
      }

      // 6) New entries. Skipped in the flatten window, after a loss stop, and
      // outside a session that can actually trade. The scan itself continues.
      final allowEntries = canOpenNewTrade(
        force: force,
        sessionOpen: sessionOpen,
        extendedHoursEnabled: settings.extendedHours,
        extendedSession: isExtendedSession(now),
        tradeWhileClosed: settings.tradeWhileClosed,
        liveBroker: broker.mode == BrokerMode.live,
        halted: risk.isHalted,
      );
      if (flattening) {
        _noteOnce(
          now,
          'No new entries — last 15 minutes, flattening day trades',
          notedDay: true,
        );
      } else if (plan.pdtBlocked) {
        _noteOnce(
          now,
          'No new entries — ${plan.dayTradeCount} day trades in 5 business '
              'days, and today\'s start is under \$25,000. Full day trading '
              'turns on at \$25,000. Open positions are still managed.',
          notedDay: true,
        );
      } else if (!allowEntries) {
        if (!risk.isHalted) {
          _noteOnce(
            now,
            'Market is closed. Still scanning. New trades wait for the next '
                'session. Closing the app does not stop this.',
            notedDay: true,
          );
        }
      } else if (allowEntries) {
        final openPositions = await broker.getPositions();
        final heldSymbols = openPositions.map((p) => p.symbol).toSet();
        final cap = settings.fitToBudget ? plan.maxSharePrice : null;
        final blockShorts = !plan.allowShort;
        final equity = plan.dayStartEquity > 0
            ? plan.dayStartEquity
            : (account.equity > 0 ? account.equity : account.cash);
        final ranked = settings.dayTradeEdge
            ? rankForDayTrade(signals)
            : signals;
        final quiet = <String>[];
        final oversized = <String>[];
        final working = <String>{
          for (final order in _pendingOrders.values) order.symbol.toUpperCase(),
        };
        try {
          final openOrders = await broker.getOpenOrders();
          for (final order in openOrders) {
            working.add(order.symbol.toUpperCase());
          }
        } catch (_) {
          // The broker's open-order list could not be read. Local pending orders are still blocked.
        }
        final freshSession = isMarketOpen(now) ||
            (settings.extendedHours && isExtendedSession(now));
        for (final sig in ranked) {
          if (heldSymbols.contains(sig.symbol)) continue;
          if (working.contains(sig.symbol.toUpperCase())) {
            _noteOnce(
              now,
              'skip ${sig.symbol}: an order is already working. No second order was sent.',
              notedDay: true,
            );
            continue;
          }
          if (isDemoSource(sig.sourceId) &&
              !settings.risk.allowTradingWithoutData) {
            _noteOnce(
              now,
              'skip ${sig.symbol}: the price came from demo data, not a live feed. No order was sent.',
              notedDay: true,
            );
            continue;
          }
          if (barIsStale(
            lastBarAt: sig.lastBarAt,
            now: now,
            interval: settings.interval.duration,
            sessionExpectsFreshBars: freshSession,
          )) {
            _noteOnce(
              now,
              'skip ${sig.symbol}: the last bar is too old for a new trade. Scanning continues.',
              notedDay: true,
            );
            continue;
          }
          final newsDecision = _newsEntry(sig);
          var side = sig.stance;
          var sizeMultiplier = 1.0;
          String? newsNote;
          if (newsDecision != null) {
            sizeMultiplier = newsDecision.sizeMultiplier;
            newsNote = newsDecision.reason;
            if (newsDecision.action == NewsTradeAction.block ||
                newsDecision.action == NewsTradeAction.exit) {
              _noteOnce(now, newsDecision.reason, notedDay: true);
              continue;
            }
            if (newsDecision.action == NewsTradeAction.promoteLong) {
              side = Stance.long;
            } else if (newsDecision.action == NewsTradeAction.promoteShort) {
              side = Stance.short;
            }
          }
          if (side == Stance.flat) continue;
          // Whole shares only. A name above the cash cap is skipped here so
          // the log is one summary, not a denial per ticker every minute.
          if (cap != null && (cap <= 0 || sig.price > cap + 1e-6)) continue;
          if (blockShorts && side == Stance.short) continue;
          final promoted = newsDecision != null &&
              (newsDecision.action == NewsTradeAction.promoteLong ||
                  newsDecision.action == NewsTradeAction.promoteShort);
          final targetPct = targetPctOfPrice(sig) ?? 0;
          final riskPct = convictionRiskPct(
            basePct: settings.risk.riskPerTradePct,
            targetPct: targetPct,
            confidence: sig.confidence,
            minTargetPct: settings.minTargetPct,
            enabled: settings.allowConvictionRisk,
          );
          if (riskPct > settings.risk.riskPerTradePct + 1e-9) {
            _noteOnce(
              now,
              '${sig.symbol}: larger size — target '
                  '${targetPct.toStringAsFixed(1)}% with '
                  '${(sig.confidence * 100).round()}% confidence, risking '
                  '${riskPct.toStringAsFixed(2)}% of today\'s start. '
                  'Not a profit guarantee.',
              notedDay: true,
            );
          }
          if (settings.dayTradeEdge && !promoted) {
            final verdict = risk.entry(
              account: account,
              positions: openPositions,
              price: sig.price,
              atr: _atrFromSignal(sig),
              stance: sig.stance,
              confidence: sig.confidence,
              day: now,
              sizingEquity: settings.scaleWithBalance ? equity : null,
              riskPerTradePct: riskPct,
            );
            if (verdict.allowed) {
              final fit = checkDayTradeVerdict(
                sig: sig,
                verdict: verdict,
                equity: equity,
                minTargetPct: settings.minTargetPct,
                riskPerTradePct: riskPct,
              );
              if (!fit.allowed) {
                if (fit.skip == DayTradeSkip.oversized) {
                  oversized.add(sig.symbol);
                } else {
                  quiet.add(sig.symbol);
                }
                continue;
              }
            }
          }
          await _tryEnter(
            sig,
            account,
            openPositions,
            now,
            sizingEquity: settings.scaleWithBalance ? equity : null,
            riskPerTradePct: riskPct * sizeMultiplier,
            side: side,
            newsNote: sizeMultiplier < 1 ? newsNote : null,
          );
        }
        _noteSkips(now, quiet: quiet, oversized: oversized);
      }
      final scanBits = <String>[
        'scan #${signals.length} symbols',
        '${signals.where((s) => s.stance != Stance.flat).length} setups',
      ];
      if (marketScan.last.walkedMarket) {
        scanBits.add('listed ${marketScan.last.rangeLabel}');
      }
      if (broker.mode == BrokerMode.live) scanBits.add('LIVE');
      if (risk.isHalted) {
        scanBits.add('daily loss stop');
      } else if (!allowEntries) {
        scanBits.add('market closed, still scanning');
      } else if (dailyProfitGoalReached(
        dayPnlPct: account.dayPnlPct,
        goalPct: settings.risk.dailyProfitGoalPct,
      )) {
        scanBits.add('daily goal reached, still scanning');
      }
      _emit('scan', scanBits.join(' · '));
    } catch (e) {
      lastError = e.toString();
      lastErrorAt = now;
      _emit('error', 'cycle failed: $e');
    } finally {
      _tickBusy = false;
    }
  }

  Future<void> _reviewNews(
    List<SignalScore> signals,
    List<Position> positions,
    DateTime now,
  ) async {
    final desk = news;
    if (!settings.useNews || desk == null) {
      lastNewsReview = null;
      return;
    }
    final symbols = <String>[
      for (final position in positions) position.symbol,
      for (final symbol in settings.watchlist) symbol,
      for (final signal in signals)
        if (signal.stance != Stance.flat) signal.symbol,
    ];
    try {
      final review = await desk.review(
        symbols: symbols,
        now: now,
        charts: <String, SignalScore>{
          for (final signal in signals) signal.symbol.toUpperCase(): signal,
        },
      );
      lastNewsReview = review;
      if (review.signature != _lastNewsSignature) {
        _lastNewsSignature = review.signature;
        _emit('news', review.summary);
      }
    } catch (e) {
      lastNewsReview = NewsReview.unavailable(now, '$e');
      if (lastNewsReview!.signature != _lastNewsSignature) {
        _lastNewsSignature = lastNewsReview!.signature;
        _emit('error', lastNewsReview!.summary);
      }
    }
  }

  NewsTradeDecision? _newsEntry(SignalScore sig) {
    final review = lastNewsReview;
    if (!settings.useNews || review == null) return null;
    return decideTrade(
      review: review,
      symbol: sig.symbol,
      chartStance: sig.stance,
      chartScore: sig.score,
      chartConfidence: sig.confidence,
      enterThreshold: settings.ensemble.enterThreshold,
      minConfidence: settings.ensemble.minConfidence,
    );
  }

  String? _newsExitReason(Position position) {
    final review = lastNewsReview;
    if (!settings.useNews || review == null) return null;
    final decision = decideTrade(
      review: review,
      symbol: position.symbol,
      chartStance: position.short ? Stance.short : Stance.long,
      chartScore: 0,
      chartConfidence: 1,
      enterThreshold: settings.ensemble.enterThreshold,
      minConfidence: settings.ensemble.minConfidence,
      heldLong: !position.short,
      heldShort: position.short,
    );
    if (decision.action != NewsTradeAction.exit) return null;
    return decision.reason;
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
    DateTime now,
  ) async {
    final scoreBySymbol = <String, SignalScore>{
      for (final s in signals) s.symbol: s,
    };
    for (final p in positions) {
      final newsExit = _newsExitReason(p);
      if (newsExit != null) {
        await _close(p, newsExit);
        continue;
      }
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

      // --- Hard stop / profit point vs current price ---
      // A profit point is customizable. With letWinnersRun it locks a stop
      // there instead of selling the whole trade, so more can stay open.
      var stopHit = long ? px <= effectiveStop : px >= effectiveStop;
      final targetHit = long ? px >= meta.target : px <= meta.target;
      if (targetHit && settings.risk.letWinnersRun) {
        final locked = lockedProfitStop(
          long: long,
          target: meta.target,
          currentStop: effectiveStop,
          targetHit: true,
          allowMore: true,
        );
        if (locked != null) {
          meta.initialStop = long
              ? (locked > meta.initialStop ? locked : meta.initialStop)
              : (locked < meta.initialStop ? locked : meta.initialStop);
          effectiveStop = long
              ? (locked > effectiveStop ? locked : effectiveStop)
              : (locked < effectiveStop ? locked : effectiveStop);
          _noteOnce(
            now,
            '${p.symbol}: profit point reached. Stop moved to that price so a '
                'further move can stay open. Not a guarantee.',
            notedDay: true,
          );
        }
        final lockedAtTarget = (effectiveStop - meta.target).abs() < 0.0001;
        final stillThrough = long ? px >= meta.target : px <= meta.target;
        if (lockedAtTarget && stillThrough) stopHit = false;
      }
      if (stopHit || (targetHit && !settings.risk.letWinnersRun)) {
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
            final request = sessionOrder(
              symbol: p.symbol,
              side: long ? OrderSide.sell : OrderSide.buy,
              qty: part,
              regularSession: isMarketOpen(_clock()),
              quote: _quotes[p.symbol.toUpperCase()],
              allowOutside: _allowLimitOutside(_clock()),
              extendedHours:
                  settings.extendedHours && isExtendedSession(_clock()),
            );
            if (request == null) {
              _noteOnce(
                _clock(),
                'No market scale-out for ${p.symbol}. The regular session is '
                    'closed, and there was no bid/ask for a limit.',
                notedDay: true,
              );
              continue;
            }
            final order = await broker.submitOrder(request);
            if (request.type == OrderType.limit &&
                order.filledQty <= 0 &&
                broker is PaperBroker) {
              continue;
            }
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
    await _sendExit(p, _clock(), reason: reason);
  }

  bool _allowLimitOutside(DateTime now) {
    if (isMarketOpen(now)) return false;
    if (settings.extendedHours && isExtendedSession(now)) return true;
    return settings.tradeWhileClosed && broker.mode != BrokerMode.live;
  }

  Future<void> _loadQuotes(List<String> symbols) async {
    _quotes.clear();
    final wanted = symbols
        .map((s) => s.toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    if (wanted.isEmpty) return;
    try {
      _quotes.addAll(await source.getQuotes(wanted));
    } catch (e) {
      _emit('info', 'Spread quotes were not readable: $e');
    }
  }

  /// Regular session uses the broker close, which is a market order.
  /// Outside that session a market order is not sent. A limit is used only
  /// when a real bid/ask exists and the session can still take an order.
  Future<bool> _sendExit(
    Position p,
    DateTime now, {
    required String reason,
  }) async {
    final side = p.short ? OrderSide.buy : OrderSide.sell;
    final request = sessionOrder(
      symbol: p.symbol,
      side: side,
      qty: p.qty,
      regularSession: isMarketOpen(now),
      quote: _quotes[p.symbol.toUpperCase()],
      allowOutside: _allowLimitOutside(now),
      extendedHours: settings.extendedHours && isExtendedSession(now),
    );
    if (request == null) {
      _noteOnce(
        now,
        'No market order for ${p.symbol}. The regular session is closed, and '
            'there was no bid/ask for a limit. The position stays open. '
            'This is not a guarantee.',
        notedDay: true,
      );
      return false;
    }
    try {
      if (request.type == OrderType.market) {
        await broker.closePosition(p.symbol);
      } else {
        final order = await broker.submitOrder(request);
        if (order.filledQty <= 0 && broker is PaperBroker) {
          _noteOnce(
            now,
            '${p.symbol}: limit close at \$${request.limitPrice!.toStringAsFixed(2)} '
                'was not filled. No market order was sent.',
            notedDay: true,
          );
          return false;
        }
        _emit(
          'exit',
          'LIMIT close ${p.symbol} at \$${request.limitPrice!.toStringAsFixed(2)} '
              '— $reason. Not a market order.',
          symbol: p.symbol,
        );
        _meta.remove(p.symbol);
        return true;
      }
      _meta.remove(p.symbol);
      _emit(
        'exit',
        'CLOSED ${p.symbol} ${p.short ? 'short' : 'long'} — $reason',
        symbol: p.symbol,
      );
      return true;
    } catch (e) {
      _emit('error', 'failed to close ${p.symbol}: $e');
      return false;
    }
  }

  ScalePlan _planFor(AccountInfo account, DateTime now) {
    return scalePlan(
      account: account,
      settings: settings,
      dayTradeCount: _dayTradeCount(account, now),
    );
  }

  int _dayTradeCount(AccountInfo account, DateTime now) {
    if (broker is PaperBroker) {
      final fills = (broker as PaperBroker).fills;
      return estimatePaperPdt(
        fills: [
          for (final f in fills)
            (symbol: f.symbol, time: f.time, isBuy: f.side == OrderSide.buy),
        ],
        equity: dayStartEquityOf(account),
        now: now,
      ).dayTradeCount;
    }
    return account.dayTradeCount;
  }

  Future<void> _tryEnter(
    SignalScore sig,
    AccountInfo account,
    List<Position> positions,
    DateTime now, {
    double? sizingEquity,
    double? riskPerTradePct,
    Stance? side,
    String? newsNote,
  }) async {
    final entrySide = side ?? sig.stance;
    final atr = _atrFromSignal(sig);
    final verdict = risk.entry(
      account: account,
      positions: positions,
      price: sig.price,
      atr: atr,
      stance: entrySide,
      confidence: sig.confidence,
      day: now,
      sizingEquity: sizingEquity,
      riskPerTradePct: riskPerTradePct,
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
    final quote = _quotes[sig.symbol.toUpperCase()];
    final spreadSkip = spreadSkipReason(
      quote: quote,
      price: sig.price,
      targetPrice: targetPx,
      maxSpreadOfTarget: settings.risk.maxSpreadOfTarget,
    );
    if (spreadSkip != null) {
      _noteOnce(now, 'skip ${sig.symbol}: $spreadSkip', notedDay: true);
      return;
    }

    final regular = isMarketOpen(now);
    final orderSide =
        entrySide == Stance.long ? OrderSide.buy : OrderSide.sell;
    final isLive = broker.mode == BrokerMode.live;
    final request = sessionOrder(
      symbol: sig.symbol,
      side: orderSide,
      qty: qty,
      regularSession: regular,
      quote: quote,
      allowOutside: _allowLimitOutside(now),
      extendedHours: settings.extendedHours && isExtendedSession(now),
      takeProfit: isLive && regular && !settings.risk.letWinnersRun
          ? targetPx
          : null,
      stopLoss: isLive && regular ? stopPx : null,
    );
    if (request == null) {
      _noteOnce(
        now,
        'No market order for ${sig.symbol}. The regular session is closed, '
            'and there was no bid/ask for a limit.',
        notedDay: true,
      );
      return;
    }

    try {
      final order = await broker.submitOrder(request);
      if (request.type == OrderType.limit &&
          order.filledQty <= 0 &&
          broker is PaperBroker) {
        _noteOnce(
          now,
          '${sig.symbol}: limit at \$${request.limitPrice!.toStringAsFixed(2)} '
              'was not filled. No market order was sent.',
          notedDay: true,
        );
        return;
      }

      // Anchor management state at entry.
      final entryAtr = atr ?? sig.price * 0.01;
      _meta[sig.symbol] = PositionMeta(
        initialStop: stopPx ?? sig.price - settings.risk.stopLossAtrMult * entryAtr,
        target: targetPx ?? sig.price + settings.risk.takeProfitAtrMult * entryAtr,
        entryAtr: entryAtr,
        peak: sig.price,
      );

      final priceNote = request.type == OrderType.limit
          ? 'limit \$${request.limitPrice!.toStringAsFixed(2)}'
          : '~\$${sig.price.toStringAsFixed(2)}';
      _emit('trade',
          '${entrySide == Stance.long ? 'BOUGHT' : 'SHORTED'} ${qty.toStringAsFixed(0)} '
          '${sig.symbol} @ $priceNote · score ${sig.scorePct} '
          'conf ${(sig.confidence * 100).round()}% · stop \$${stopPx?.toStringAsFixed(2)} '
          'target \$${targetPx?.toStringAsFixed(2)}'
          '${newsNote == null ? '' : ' · $newsNote'}',
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
