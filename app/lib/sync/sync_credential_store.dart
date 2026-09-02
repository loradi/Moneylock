import 'package:flutter/services.dart';

abstract class SyncCredentialStore {
  Future<String> readApiKey();
  Future<void> writeApiKey(String apiKey);
  Future<void> clearApiKey();
}

/// Stores the private-sync key in the platform credential vault rather than
/// the app database. On iOS this is backed by the user's Keychain.
class PlatformSyncCredentialStore implements SyncCredentialStore {
  static const _channel = MethodChannel('moneylock/sync_credentials');

  @override
  Future<String> readApiKey() async =>
      await _channel.invokeMethod<String>('readApiKey') ?? '';

  @override
  Future<void> writeApiKey(String apiKey) =>
      _channel.invokeMethod<void>('writeApiKey', {'apiKey': apiKey});

  @override
  Future<void> clearApiKey() => _channel.invokeMethod<void>('clearApiKey');
}
