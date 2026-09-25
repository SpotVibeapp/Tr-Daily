import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../state/app_state.dart';
import '../storage/persistent_store_io.dart';

/// Entry point for the Android foreground service. Must stay a top-level
/// function so the process can resume it after the UI isolate is gone.
@pragma('vm:entry-point')
void tradingKeepAliveCallback() {
  FlutterForegroundTask.setTaskHandler(TradingKeepAliveHandler());
}

class TradingKeepAliveHandler extends TaskHandler {
  AppState? _state;

  Future<void> _note(String title, String text) {
    return FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: text,
    );
  }

  String _title(AppState state) => state.settings.liveTrading
      ? 'Tr-Daily LIVE scan'
      : 'Tr-Daily is scanning';

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    DartPluginRegistrant.ensureInitialized();
    WidgetsFlutterBinding.ensureInitialized();
    final state = AppState(store: await FileStore.open());
    _state = state;
    await state.init(launchEngine: false);
    if (!state.settings.engineArmed || !state.settings.keepRunningWhenClosed) {
      await state.writeKeepAliveStatus(
        running: false,
        note: 'Background scan is off.',
      );
      await FlutterForegroundTask.stopService();
      return;
    }
    state.engine?.start(periodic: false);
    final live = state.settings.liveTrading;
    await state.writeKeepAliveStatus(
      running: true,
      note: live
          ? 'LIVE scan. Closing the app does not stop orders.'
          : 'Scanning. Closing the app does not stop this.',
    );
    await _note(
      _title(state),
      live
          ? 'LIVE. Closing the app does not stop orders. Tap Stop to stop.'
          : 'Closing the app does not stop this. Not a profit guarantee.',
    );
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    final state = _state;
    if (state == null || state.engine == null) return;
    unawaited(() async {
      await state.engine!.tick();
      final last = state.log.isEmpty
          ? 'Scanning. Closing the app does not stop this.'
          : state.log.last.message;
      final text = last.length > 90 ? '${last.substring(0, 87)}...' : last;
      await state.writeKeepAliveStatus(running: true, note: text);
      await _note(_title(state), text);
    }());
  }

  Future<void> _reload(AppState state) async {
    await state.reloadSettingsFromDisk();
  }

  Future<void> _stopArmed(AppState state) async {
    state.settings.engineArmed = false;
    await state.persistSettings();
    state.engine?.stop();
    await state.writeKeepAliveStatus(running: false, note: 'Stopped.');
    await FlutterForegroundTask.stopService();
  }

  @override
  void onReceiveData(Object data) {
    final state = _state;
    if (state == null || data is! Map) return;
    final cmd = data['cmd']?.toString();
    if (cmd == 'close') {
      final symbol = data['symbol']?.toString() ?? '';
      if (symbol.isNotEmpty) unawaited(state.closePosition(symbol));
    } else if (cmd == 'reload') {
      unawaited(_reload(state));
    } else if (cmd == 'tick') {
      unawaited(state.engine?.tick(force: true));
    } else if (cmd == 'stop') {
      unawaited(_stopArmed(state));
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    final state = _state;
    state?.engine?.stop();
    await state?.writeKeepAliveStatus(
      running: false,
      note: isTimeout
          ? 'Android stopped the background scan. Open the app to start it again.'
          : 'Background scan stopped.',
    );
  }

  @override
  void onNotificationButtonPressed(String id) {
    final state = _state;
    if (id == 'stop' && state != null) {
      unawaited(_stopArmed(state));
    }
  }

  @override
  void onNotificationPressed() {}

  @override
  void onNotificationDismissed() {}
}
