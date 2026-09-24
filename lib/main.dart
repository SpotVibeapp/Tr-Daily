import 'package:flutter/material.dart';

import 'state/app_state.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final state = AppState();
  // Initialize storage + engine wiring before first frame (fast, local-only).
  try {
    await state.init();
  } catch (e) {
    // Init failures should never hard-crash the UI; state surfaces the error.
    debugPrint('init error: $e');
  }

  runApp(TrDailyApp(state: state));
}
