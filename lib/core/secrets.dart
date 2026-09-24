/// Broker credential container.
///
/// Keys live only on-device (never committed — see .gitignore). Bank linking
/// itself always happens on the broker's website; the app only ever holds
/// these API keys afterward.
class TradingKeys {
  const TradingKeys({required this.keyId, required this.secretKey});

  final String keyId;
  final String secretKey;

  bool get isConfigured => keyId.trim().isNotEmpty && secretKey.trim().isNotEmpty;

  @override
  bool operator ==(Object other) =>
      other is TradingKeys && other.keyId == keyId && other.secretKey == secretKey;

  @override
  int get hashCode => Object.hash(keyId, secretKey);
}
