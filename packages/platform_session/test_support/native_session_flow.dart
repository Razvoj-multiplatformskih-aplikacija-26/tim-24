import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:platform_session/platform_session.dart';

/// Shared integration flow, deliberately outside lib/ and the production app.
/// Run prepare, restore and verify-cleared in three separate native processes.
Future<void> runNativeSessionPhase({
  required String phase,
  required String apiUrl,
  required String email,
  required String password,
  required String key,
  required String scope,
  required String expectedRole,
}) async {
  expect(
    kIsWeb,
    isFalse,
    reason: 'This proves native operating-system storage.',
  );
  expect(
    key.startsWith('kt2-native-test-'),
    isTrue,
    reason:
        'The test must use its own key and preserve real application sessions.',
  );
  const nativeStorage = FlutterSecureStorage();
  final SessionStorage storage = SecureSessionStorage(
    key: key,
    storage: nativeStorage,
  );
  final api = HedrionApiClient(
    apiUrl,
    browserSession: false,
    browserScope: scope,
    sessionStorage: storage,
  );
  try {
    if (phase == 'prepare') {
      await storage.clear();
      expect(await storage.read() == null, isTrue);
      await api.login(email, password);
      expect(api.user?['role'] == expectedRole, isTrue);
      final persisted = await storage.read();
      expect(persisted != null, isTrue);
      expect(persisted?.token == api.token, isTrue);
      expect(persisted?.refreshToken == api.refreshToken, isTrue);
      expect(persisted?.user['id'] == api.user?['id'], isTrue);
      await _verifyPasswordAbsent(nativeStorage, key, password);
      debugPrint('KT2_NATIVE_SESSION_PREPARED scope=$scope');
      // Keep the test entry: the next native process must recover it.
    } else if (phase == 'restore') {
      final before = await storage.read();
      expect(
        before != null,
        isTrue,
        reason: 'Run prepare first without clearing or uninstalling app data.',
      );
      expect(api.token == null && api.user == null, isTrue);
      expect(await api.restoreSession(), isTrue);
      final onlineIdentity = await api.me();
      expect(onlineIdentity['id'] == before!.user['id'], isTrue);
      expect(onlineIdentity['role'] == expectedRole, isTrue);
      expect(onlineIdentity['email'] == email, isTrue);
      debugPrint('KT2_NATIVE_SESSION_RESTORED scope=$scope');

      // Force a refresh using the real persisted refresh credential. The API
      // rejects this intentionally invalid access credential, then the shared
      // client rotates the session and writes the new bundle through the port.
      final previousRefresh = api.refreshToken;
      api.token = 'kt2-native-test-expired-access';
      await api.me();
      expect(api.refreshToken != previousRefresh, isTrue);
      final rotated = await storage.read();
      expect(rotated?.token == api.token, isTrue);
      expect(rotated?.refreshToken == api.refreshToken, isTrue);
      await _verifyPasswordAbsent(nativeStorage, key, password);
      debugPrint('KT2_NATIVE_SESSION_REFRESHED scope=$scope');

      final revokedToken = api.token;
      await api.logout();
      expect(
        api.token == null && api.refreshToken == null && api.user == null,
        isTrue,
      );
      expect(await storage.read() == null, isTrue);
      expect(await nativeStorage.read(key: key) == null, isTrue);

      final revoked = HedrionApiClient(apiUrl, browserSession: false)
        ..token = revokedToken;
      try {
        DomainError? denied;
        try {
          await revoked.me();
        } on DomainException catch (error) {
          denied = error.error;
        }
        expect(denied?.code == ErrorCode.sessionExpired, isTrue);
      } finally {
        revoked.close();
      }
      debugPrint('KT2_NATIVE_SESSION_LOGGED_OUT scope=$scope');
    } else if (phase == 'verify-cleared') {
      expect(
        await nativeStorage.read(key: key) == null,
        isTrue,
        reason: 'Logout must remain cleared after a second native restart.',
      );
      expect(await storage.read() == null, isTrue);
      expect(await api.restoreSession(), isFalse);
      expect(
        api.token == null && api.refreshToken == null && api.user == null,
        isTrue,
      );
      debugPrint('KT2_NATIVE_SESSION_CLEAR_CONFIRMED scope=$scope');
    } else {
      fail(
        'Unknown KT2_SESSION_PHASE; use prepare, restore or verify-cleared.',
      );
    }
  } finally {
    api.close();
  }
}

Future<void> _verifyPasswordAbsent(
  FlutterSecureStorage storage,
  String key,
  String password,
) async {
  final raw = await storage.read(key: key);
  expect(raw != null, isTrue);
  final encoded = jsonDecode(raw!) as Map<String, dynamic>;
  expect(
    encoded.keys.toSet().difference({
      'token',
      'refreshToken',
      'user',
      'expiresAt',
      'refreshExpiresAt',
    }).isEmpty,
    isTrue,
  );
  for (final field in ['expiresAt', 'refreshExpiresAt']) {
    if (encoded.containsKey(field)) {
      final value = encoded[field];
      expect(value is String, isTrue);
      expect(value is String && DateTime.tryParse(value) != null, isTrue);
    }
  }
  expect(_containsPasswordField(encoded), isFalse);
  expect(raw.contains(password), isFalse);
}

bool _containsPasswordField(Object? value) => switch (value) {
  Map() => value.entries.any(
    (entry) =>
        entry.key.toString().toLowerCase().contains('password') ||
        _containsPasswordField(entry.value),
  ),
  List() => value.any(_containsPasswordField),
  _ => false,
};
