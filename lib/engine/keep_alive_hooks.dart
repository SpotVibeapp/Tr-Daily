import 'package:flutter/widgets.dart';

/// Filled in by [installKeepAlive] on Android. Empty on web and in tests,
/// so closing the app is a no-op there instead of a missing plugin.
class KeepAliveHooks {
  const KeepAliveHooks._();

  static bool supported = false;

  static Future<void> Function()? prepare;
  static Future<bool> Function()? isRunning;
  static Future<bool> Function(int scanIntervalSeconds)? start;
  static Future<void> Function()? stop;
  static Future<void> Function(int scanIntervalSeconds)? restart;
  static Future<void> Function(Map<String, String> command)? send;

  static Widget wrap(Widget child) => _wrap?.call(child) ?? child;

  static Widget Function(Widget child)? _wrap;

  static void install({
    required bool supported,
    required Future<void> Function() prepare,
    required Future<bool> Function() isRunning,
    required Future<bool> Function(int scanIntervalSeconds) start,
    required Future<void> Function() stop,
    required Future<void> Function(int scanIntervalSeconds) restart,
    required Future<void> Function(Map<String, String> command) send,
    required Widget Function(Widget child) wrap,
  }) {
    KeepAliveHooks.supported = supported;
    KeepAliveHooks.prepare = prepare;
    KeepAliveHooks.isRunning = isRunning;
    KeepAliveHooks.start = start;
    KeepAliveHooks.stop = stop;
    KeepAliveHooks.restart = restart;
    KeepAliveHooks.send = send;
    _wrap = wrap;
  }
}
