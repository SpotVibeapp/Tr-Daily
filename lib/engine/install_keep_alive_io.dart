import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'keep_alive_hooks.dart';
import 'keep_alive_task.dart';

/// Android foreground service. Desktop tests load this file but never start
/// the service, because [KeepAliveHooks.supported] stays false off Android.
Future<void> installKeepAlive() async {
  final android = !kIsWeb && Platform.isAndroid;
  if (android) {
    FlutterForegroundTask.initCommunicationPort();
  }
  KeepAliveHooks.install(
    supported: android,
    prepare: () async {},
    isRunning: () async {
      if (!android) return false;
      return FlutterForegroundTask.isRunningService;
    },
    start: (seconds) => _start(seconds),
    stop: _stop,
    restart: (seconds) async {
      await _stop();
      await _start(seconds);
    },
    send: (command) async {
      if (!android) return;
      FlutterForegroundTask.sendDataToTask(command);
    },
    wrap: (child) => android ? WithForegroundTask(child: child) : child,
  );
}

Future<void> _initOptions(int seconds) async {
  final interval = seconds.clamp(15, 3600);
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'tr_daily_engine',
      channelName: 'Tr-Daily engine',
      channelDescription:
          'Stays up while the scan keeps running after the app is closed.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: false,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(interval * 1000),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

bool _askedBattery = false;

Future<void> _askPermissions() async {
  final permission = await FlutterForegroundTask.checkNotificationPermission();
  if (permission != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  if (_askedBattery) return;
  _askedBattery = true;
  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
}

Future<bool> _start(int seconds) async {
  if (!KeepAliveHooks.supported) return false;
  await _initOptions(seconds);
  await _askPermissions();
  if (await FlutterForegroundTask.isRunningService) {
    final restarted = await FlutterForegroundTask.restartService();
    return restarted is ServiceRequestSuccess;
  }
  final result = await FlutterForegroundTask.startService(
    serviceId: 256,
    serviceTypes: const <ForegroundServiceTypes>[
      ForegroundServiceTypes.specialUse,
    ],
    notificationTitle: 'Tr-Daily is scanning',
    notificationText: 'Closing the app does not stop this. Tap to open.',
    notificationButtons: const <NotificationButton>[
      NotificationButton(id: 'stop', text: 'Stop'),
    ],
    callback: tradingKeepAliveCallback,
  );
  return result is ServiceRequestSuccess;
}

Future<void> _stop() async {
  if (!KeepAliveHooks.supported) return;
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.stopService();
  }
}
