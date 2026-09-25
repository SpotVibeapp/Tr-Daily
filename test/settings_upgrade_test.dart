import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tr_daily/core/config.dart';
import 'package:tr_daily/core/secrets.dart';
import 'package:tr_daily/risk/risk_manager.dart';
import 'package:tr_daily/state/app_state.dart';
import 'package:tr_daily/storage/local_store.dart';
import 'package:tr_daily/storage/secret_vault.dart';

const _settingsKey = 'trdaily.settings.v1';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('starter limits', () {
    test('new installs start at 0.5% risk and one position', () {
      final s = AppSettings();
      expect(s.risk.riskPerTradePct, 0.5);
      expect(s.risk.maxOpenPositions, 1);
      expect(s.minSharePrice, 1.0);
      expect(s.minDollarVolume, 1000000);
      expect(s.toJson()['defaultsVersion'], AppSettings.currentDefaultsVersion);
    });

    test('old saved defaults move to the new ones', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'risk': <String, dynamic>{
          'riskPerTradePct': 0.75,
          'maxOpenPositions': 3,
        },
      });
      expect(s.risk.riskPerTradePct, 0.5);
      expect(s.risk.maxOpenPositions, 1);
      expect(s.upgradedDefaults, isTrue);
    });

    test('values the user picked are kept', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'risk': <String, dynamic>{
          'riskPerTradePct': 1.25,
          'maxOpenPositions': 2,
        },
      });
      expect(s.risk.riskPerTradePct, 1.25);
      expect(s.risk.maxOpenPositions, 2);
      expect(s.upgradedDefaults, isFalse);
    });

    test('settings saved after the upgrade are left alone', () {
      final s = AppSettings.fromJson(<String, dynamic>{
        'defaultsVersion': 2,
        'risk': <String, dynamic>{
          'riskPerTradePct': 0.75,
          'maxOpenPositions': 3,
        },
      });
      expect(s.risk.riskPerTradePct, 0.75);
      expect(s.risk.maxOpenPositions, 3);
      expect(s.upgradedDefaults, isFalse);
    });

    test('the upgrade only touches the values that were old defaults', () {
      final r = upgradeRiskDefaultsV2(
        const RiskConfig(riskPerTradePct: 0.75, maxOpenPositions: 2),
      );
      expect(r.riskPerTradePct, 0.5);
      expect(r.maxOpenPositions, 2);
    });

    test('an installed app saves the upgrade once and logs it', () async {
      final store = MemoryStore();
      store.data[_settingsKey] = jsonEncode(<String, dynamic>{
        'risk': <String, dynamic>{
          'riskPerTradePct': 0.75,
          'maxOpenPositions': 3,
        },
      });
      final state = AppState(store: store);
      await state.init(launchEngine: false);
      expect(state.settings.risk.maxOpenPositions, 1);
      expect(
        state.log.any((l) => l.message.contains('safer starting defaults')),
        isTrue,
      );
      final saved = jsonDecode(store.data[_settingsKey]!) as Map<String, dynamic>;
      expect(saved['defaultsVersion'], AppSettings.currentDefaultsVersion);
      state.dispose();
    });
  });

  group('broker keys', () {
    test('keys are kept out of the settings file', () async {
      final store = MemoryStore();
      final state = AppState(store: store);
      await state.init(launchEngine: false);
      state.settings.keys =
          const TradingKeys(keyId: 'PK123', secretKey: 'shh-secret');
      await state.persistSettings();

      final file = store.data[_settingsKey]!;
      expect(file, isNot(contains('shh-secret')));
      expect(file, isNot(contains('PK123')));
      final vaulted = await StoreVault(store).readKeys();
      expect(vaulted?.secretKey, 'shh-secret');
      state.dispose();

      final reopened = AppState(store: store);
      await reopened.init(launchEngine: false);
      expect(reopened.settings.keys.keyId, 'PK123');
      expect(reopened.settings.keys.secretKey, 'shh-secret');
      reopened.dispose();
    });

    test('keys from an older install move into the vault', () async {
      final store = MemoryStore();
      store.data[_settingsKey] = jsonEncode(<String, dynamic>{
        'defaultsVersion': 2,
        'keyId': 'PKOLD',
        'secretKey': 'old-secret',
      });
      final state = AppState(store: store);
      await state.init(launchEngine: false);
      expect(state.settings.keys.secretKey, 'old-secret');
      expect(store.data[_settingsKey], isNot(contains('old-secret')));
      expect((await StoreVault(store).readKeys())?.keyId, 'PKOLD');
      state.dispose();
    });

    test('a broken vault keeps keys in the file so trading still works',
        () async {
      final store = MemoryStore();
      final state = AppState(store: store, vault: _BrokenVault());
      await state.init(launchEngine: false);
      state.settings.keys =
          const TradingKeys(keyId: 'PK1', secretKey: 'fallback');
      await state.persistSettings();
      expect(state.keysInPlainFile, isTrue);
      expect(store.data[_settingsKey], contains('fallback'));
      state.dispose();
    });
  });
}

class _BrokenVault implements SecretVault {
  @override
  Future<TradingKeys?> readKeys() async => throw StateError('no keystore');

  @override
  Future<void> writeKeys(TradingKeys keys) async =>
      throw StateError('no keystore');

  @override
  Future<void> clear() async {}
}
