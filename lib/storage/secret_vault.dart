import 'dart:convert';

import '../core/secrets.dart';
import 'local_store.dart';

/// Where broker API keys live, apart from the rest of the settings.
///
/// Settings are a plain JSON file. Android's auto-backup can copy that file
/// off the phone, so live keys that can place real orders do not belong in
/// it. The app uses [SecureVault] (Android Keystore). Tests use [StoreVault].
abstract class SecretVault {
  /// Saved keys, or null when none are saved. Throws when the store cannot
  /// be read, so a caller never mistakes "unreadable" for "no keys" and
  /// overwrites them.
  Future<TradingKeys?> readKeys();

  /// Save [keys]. Empty keys clear the vault.
  Future<void> writeKeys(TradingKeys keys);

  Future<void> clear();
}

/// Keys in their own entry of a [KeyValueStore]. Not encrypted. For tests
/// and anywhere a secure store is not available.
class StoreVault implements SecretVault {
  StoreVault(this._store);

  final KeyValueStore _store;
  static const String storageKey = 'trdaily.keys.v1';

  @override
  Future<TradingKeys?> readKeys() async {
    final raw = await _store.read(storageKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      return TradingKeys(
        keyId: json['keyId']?.toString() ?? '',
        secretKey: json['secretKey']?.toString() ?? '',
      );
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> writeKeys(TradingKeys keys) async {
    if (keys.keyId.isEmpty && keys.secretKey.isEmpty) {
      await clear();
      return;
    }
    await _store.write(
      storageKey,
      jsonEncode(<String, String>{
        'keyId': keys.keyId,
        'secretKey': keys.secretKey,
      }),
    );
  }

  @override
  Future<void> clear() => _store.delete(storageKey);
}
