import 'package:flutter/material.dart';

import 'engine/install_keep_alive.dart'
    if (dart.library.io) 'engine/install_keep_alive_io.dart';
import 'state/app_state.dart';
import 'storage/secure_vault.dart';
import 'storage/persistent_store.dart'
    if (dart.library.io) 'storage/persistent_store_io.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await installKeepAlive();

  final state = AppState(
    store: await openPersistentStore(),
    vault: SecureVault(),
  );
  // Initialize storage + engine wiring before first frame (fast, local-only).
  try {
    await state.init();
  } catch (e) {
    // Init failures should never hard-crash the UI; state surfaces the error.
    debugPrint('init error: $e');
  }

  runApp(TrDailyApp(state: state));
}
