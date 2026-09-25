import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:tr_daily/analysis/estimator.dart';
import 'package:tr_daily/broker/alpaca_broker.dart';
import 'package:tr_daily/broker/paper_broker.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/core/notifications.dart';
import 'package:tr_daily/core/server_config.dart';
import 'package:tr_daily/data/market_data_source.dart';
import 'package:tr_daily/data/news_feed.dart';
import 'package:tr_daily/engine/scanner.dart';
import 'package:tr_daily/engine/trader_engine.dart';
import 'package:tr_daily/risk/risk_manager.dart';
import 'package:tr_daily/strategy/ensemble.dart';

/// 24/7 Headless Server Entrypoint for Tr-Daily.
///
/// Runs the autonomous trading engine in the cloud, VPS, Docker container,
/// or home server without needing a mobile screen active. Dispatches alerts
/// to Discord/Telegram webhooks and serves an HTTP healthcheck.
void main(List<String> args) async {
  // ignore: avoid_print
  print('===========================================================');
  // ignore: avoid_print
  print('  🚀 Tr-Daily Autonomous Day-Trading Server v0.1');
  // ignore: avoid_print
  print('  24/7 Cloud & Headless Engine Runtime');
  // ignore: avoid_print
  print('===========================================================');
  // ignore: avoid_print
  print('⚠️  SAFETY & RISK DISCLAIMER:');
  // ignore: avoid_print
  print('  Tr-Daily is an automated day-trading software assistant.');
  // ignore: avoid_print
  print('  No guarantee of profit is claimed or implied. Automated');
  // ignore: avoid_print
  print('  trading involves significant financial risk. Default is');
  // ignore: avoid_print
  print('  simulated paper trading. Live mode routes real money orders.');
  // ignore: avoid_print
  print('===========================================================\n');

  final config = ServerConfig.fromEnvironment(Platform.environment);
  final s = config.settings;

  // ignore: avoid_print
  print('Mode:        ${s.brokerMode.name.toUpperCase()}');
  // ignore: avoid_print
  print('Watchlist:   ${s.watchlist.join(', ')}');
  // ignore: avoid_print
  print('Interval:    ${s.interval.code} (scan every ${s.scanIntervalSeconds}s)');
  // ignore: avoid_print
  print('Risk/Trade:  ${s.risk.riskPerTradePct}% of equity');
  // ignore: avoid_print
  print('Daily Stop:  ${s.risk.maxDailyLossPct}% max daily loss circuit breaker');
  // ignore: avoid_print
  print('Webhooks:    ${s.notifications.hasWebhook ? "Configured" : "None"}');
  // ignore: avoid_print
  print('Telegram:    ${s.notifications.hasTelegram ? "Configured" : "None"}\n');

  final notifs = NotificationService(config: s.notifications);

  // Initialize Market Data Source
  final yahoo = YahooFinanceSource();
  final synthetic = SyntheticMarketSource();
  final MarketDataSource dataSource = switch (s.dataProvider) {
    DataProviderMode.yahoo => CompositeDataSource(<MarketDataSource>[yahoo, synthetic]),
    DataProviderMode.alpaca => s.keys.isConfigured
        ? CompositeDataSource(<MarketDataSource>[AlpacaDataSource(keys: s.keys), yahoo, synthetic])
        : CompositeDataSource(<MarketDataSource>[yahoo, synthetic]),
    DataProviderMode.synthetic => synthetic,
    DataProviderMode.auto => CompositeDataSource(<MarketDataSource>[yahoo, synthetic]),
  };

  // Initialize Broker
  final Broker broker = s.keys.isConfigured
      ? AlpacaBroker(keys: s.keys, mode: s.brokerMode)
      : PaperBroker(startingCash: s.paperStartingCash);

  final ensemble = SignalEnsemble(config: s.ensemble);
  final risk = RiskManager(config: s.risk);
  final scanner = MarketScanner(
    source: dataSource,
    estimator: const TrendEstimator(),
    ensemble: ensemble,
  );

  final engine = TraderEngine(
    broker: broker,
    source: dataSource,
    scanner: scanner,
    settings: s,
    risk: risk,
    news: LiveNewsDesk(),
  );

  // Wire Engine Events to Notification Service & Terminal Log
  engine.events.listen((ev) {
    final timeStr = DateTime.now().toUtc().toIso8601String().substring(11, 19);
    // ignore: avoid_print
    print('[$timeStr UTC] [${ev.type.toUpperCase()}] ${ev.message}');

    if (ev.type == 'trade') {
      unawaited(notifs.dispatch(
        title: 'Trade Executed · ${ev.symbol ?? "Order"}',
        body: ev.message,
        type: NotificationType.tradeFill,
        severity: NotificationSeverity.info,
        symbol: ev.symbol,
      ));
    } else if (ev.type == 'exit') {
      final msg = ev.message.toLowerCase();
      final isStop = msg.contains('stop');
      final isTarget = msg.contains('profit');
      unawaited(notifs.dispatch(
        title: isStop
            ? 'Stop Triggered · ${ev.symbol ?? ""}'
            : (isTarget ? 'Target Reached · ${ev.symbol ?? ""}' : 'Position Closed · ${ev.symbol ?? ""}'),
        body: ev.message,
        type: isStop
            ? NotificationType.stopLoss
            : (isTarget ? NotificationType.takeProfit : NotificationType.tradeFill),
        severity: isTarget ? NotificationSeverity.success : NotificationSeverity.warning,
        symbol: ev.symbol,
      ));
    } else if (ev.type == 'halt') {
      unawaited(notifs.dispatch(
        title: '🚨 Circuit Breaker Halted',
        body: ev.message,
        type: NotificationType.dailyLossHalt,
        severity: NotificationSeverity.critical,
        symbol: ev.symbol,
      ));
    }
  });

  // Start HTTP Health Check Server
  HttpServer? server;
  try {
    server = await HttpServer.bind(config.host, config.port);
    // ignore: avoid_print
    print('🌐 Health check server listening on http://${config.host}:${config.port}');

    server.listen((HttpRequest request) async {
      final path = request.uri.path;
      final response = request.response;
      response.headers.contentType = ContentType.json;

      if (path == '/health' || path == '/healthz') {
        response.statusCode = HttpStatus.ok;
        response.write(jsonEncode(<String, dynamic>{
          'status': 'healthy',
          'engineState': engine.state.name,
          'cycleCount': engine.cycleCount,
          'broker': broker.id,
          'mode': broker.mode.name,
        }));
      } else if (path == '/status') {
        try {
          final account = await broker.getAccount();
          final positions = await broker.getPositions();
          response.statusCode = HttpStatus.ok;
          response.write(jsonEncode(<String, dynamic>{
            'status': 'ok',
            'engineState': engine.state.name,
            'cycles': engine.cycleCount,
            'lastScan': engine.lastScanAt?.toIso8601String(),
            'account': <String, dynamic>{
              'equity': account.equity,
              'cash': account.cash,
              'dayPnl': account.dayPnl,
              'dayPnlPct': account.dayPnlPct,
            },
            'openPositions': positions.length,
            'positions': positions
                .map((p) => <String, dynamic>{
                      'symbol': p.symbol,
                      'qty': p.qty,
                      'entry': p.avgEntryPrice,
                      'current': p.currentPrice,
                      'uPnl': p.unrealizedPnl,
                      'short': p.short,
                    })
                .toList(),
            'lastSignals': engine.lastSignals
                .map((sig) => <String, dynamic>{
                      'symbol': sig.symbol,
                      'score': sig.score,
                      'stance': sig.stance.name,
                      'price': sig.price,
                    })
                .toList(),
          }));
        } catch (e) {
          response.statusCode = HttpStatus.internalServerError;
          response.write(jsonEncode(<String, dynamic>{'error': '$e'}));
        }
      } else {
        response.statusCode = HttpStatus.ok;
        response.write(jsonEncode(<String, dynamic>{
          'service': 'Tr-Daily Autonomous Day-Trading Engine',
          'version': '0.1.0',
          'mode': s.brokerMode.name,
          'engineState': engine.state.name,
          'disclaimer': 'Simulation by default. Past performance != future results. No profit guarantee.',
        }));
      }
      await response.close();
    });
  } catch (e) {
    // ignore: avoid_print
    print('⚠️  Warning: could not bind HTTP server on port ${config.port}: $e');
  }

  // Graceful Shutdown Handling
  void shutdown() async {
    // ignore: avoid_print
    print('\n🛑 Shutting down Tr-Daily server...');
    engine.stop();
    engine.dispose();
    notifs.dispose();
    await server?.close(force: true);
    // ignore: avoid_print
    print('👋 Server exited cleanly.');
    exit(0);
  }

  ProcessSignal.sigint.watch().listen((_) => shutdown());
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) => shutdown());
  }

  // Start Autonomous Trading Engine
  // ignore: avoid_print
  print('🚀 Starting Trader Engine...');
  engine.start();

  await notifs.dispatch(
    title: '🟢 Tr-Daily 24/7 Engine Started',
    body: 'Running in ${s.brokerMode.name.toUpperCase()} mode on ${s.watchlist.length} watchlist symbols.',
    type: NotificationType.system,
    severity: NotificationSeverity.info,
  );
}
