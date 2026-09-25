import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/secrets.dart';
import 'secret_vault.dart';

/// Broker keys in the platform's encrypted store: Android Keystore-backed
/// ciphers, iOS/macOS Keychain, and the platform equivalents elsewhere.
///
/// A backup restored onto another phone cannot decrypt the old entries (the
/// Keystore key stays on the original device). That read throws, the app
/// reports it, and the user pastes the keys again. The release APK turns
/// Android backups off, so this should not come up.
class SecureVault implements SecretVault {
  SecureVault([FlutterSecureStorage? storage])
      : _storage = storage ?? FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  static const String _kId = 'trdaily.alpaca.keyId';
  static const String _kSecret = 'trdaily.alpaca.secretKey';

  @override
  Future<TradingKeys?> readKeys() async {
    final id = await _storage.read(key: _kId);
    final secret = await _storage.read(key: _kSecret);
    if (id == null && secret == null) return null;
    return TradingKeys(keyId: id ?? '', secretKey: secret ?? '');
  }

  @override
  Future<void> writeKeys(TradingKeys keys) async {
    if (keys.keyId.isEmpty && keys.secretKey.isEmpty) {
      await clear();
      return;
    }
    await _storage.write(key: _kId, value: keys.keyId);
    await _storage.write(key: _kSecret, value: keys.secretKey);
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _kId);
      await _storage.delete(key: _kSecret);
    } catch (_) {
      // Nothing readable to remove.
    }
  }
}
