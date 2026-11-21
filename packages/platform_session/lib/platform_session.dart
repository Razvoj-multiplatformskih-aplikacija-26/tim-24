import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';

/// Uses Keychain, Android Keystore, Windows Credential Manager or libsecret
/// through flutter_secure_storage. Each application owns a separate entry.
final class SecureSessionStorage implements SessionStorage {
  const SecureSessionStorage({
    required this.key,
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final String key;
  final FlutterSecureStorage _storage;

  @override
  Future<StoredSession?> read() async {
    final value = await _storage.read(key: key);
    if (value == null) return null;
    try {
      return StoredSession.fromJson(jsonDecode(value) as Map<String, dynamic>);
    } catch (_) {
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(StoredSession session) =>
      _storage.write(key: key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: key);
}
