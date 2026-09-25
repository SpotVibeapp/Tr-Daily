import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/state/app_state.dart';
import 'package:tr_daily/storage/local_store.dart';
import 'package:tr_daily/storage/persistent_store_io.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('settings remember that the user started the engine', () {
    final defaults = AppSettings();
    expect(defaults.engineArmed, isFalse);
    expect(defaults.keepRunningWhenClosed, isTrue);

    final saved = AppSettings.fromJson(<String, dynamic>{
      'engineArmed': true,
      'keepRunningWhenClosed': false,
    });
    expect(saved.engineArmed, isTrue);
    expect(saved.keepRunningWhenClosed, isFalse);
    expect(saved.toJson()['engineArmed'], isTrue);
  });

  test('file store keeps paper cash after a new store opens the same folder',
      () async {
    final dir = await Directory.systemTemp.createTemp('trdaily-store');
    addTearDown(() => dir.delete(recursive: true));
    final first = FileStore(dir);
    await first.write('trdaily.paper.v1', '{"cash":1250.5}');
    final second = FileStore(dir);
    expect(await second.read('trdaily.paper.v1'), '{"cash":1250.5}');
    await second.delete('trdaily.paper.v1');
    expect(await first.read('trdaily.paper.v1'), isNull);
  });

  test('closing the UI does not clear the armed flag or paper cash', () async {
    final store = MemoryStore();
    final state = AppState(store: store);
    await state.init();
    state.settings.paperStartingCash = 800;
    await state.resetPaperAccount();
    state.settings.engineArmed = true;
    await state.persistSettings();
    expect(state.backgroundRunning, isFalse);

    state.dispose();

    final reopened = AppState(store: store);
    await reopened.init(launchEngine: false);
    expect(reopened.settings.engineArmed, isTrue);
    expect(reopened.account.equity, closeTo(800, 0.01));
    reopened.dispose();
  });
}
