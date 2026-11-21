import 'dart:async';
import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final class MemorySessionStorage implements SessionStorage {
  StoredSession? value;
  int writes = 0, clears = 0;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession session) async {
    value = session;
    writes++;
  }

  @override
  Future<void> clear() async {
    value = null;
    clears++;
  }
}

void main() {
  const user = {
    'id': 'creator',
    'role': 'creator',
    'displayName': 'Creator',
    'email': 'creator@example.test',
  };
  http.Response reply(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);
  StoredSession saved() => StoredSession(
    token: 'old-access',
    refreshToken: 'old-refresh',
    user: user,
  );
  Matcher sessionExpired() => isA<DomainException>().having(
    (e) => e.error.code,
    'code',
    ErrorCode.sessionExpired,
  );

  test(
    'native login persists through port, restart refreshes and saves rotated credentials',
    () async {
      final storage = MemorySessionStorage();
      var fresh = false;
      final transport = MockClient((request) async {
        final body = request.body.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(request.body) as Map<String, dynamic>;
        if (request.url.path.endsWith('/login')) {
          expect(body['browserSessionScope'], 'studio');
          return reply({
            'token': 'old-access',
            'refreshToken': 'old-refresh',
            'user': user,
          });
        }
        if (request.url.path.endsWith('/refresh')) {
          expect(body['refreshToken'], 'old-refresh');
          fresh = true;
          return reply({
            'token': 'fresh-access',
            'refreshToken': 'fresh-refresh',
            'user': user,
          });
        }
        expect(request.url.path, '/api/v1/me');
        expect(
          request.headers['authorization'],
          'Bearer ${fresh ? 'fresh-access' : 'old-access'}',
        );
        return fresh ? reply(user) : reply({'code': 'sessionExpired'}, 401);
      });
      final first = HedrionApiClient(
        'http://localhost',
        client: transport,
        sessionStorage: storage,
      );
      await first.login('creator@example.test', 'password-is-never-stored');
      expect(
        jsonEncode(storage.value!.toJson()),
        isNot(contains('password-is-never-stored')),
      );
      final restarted = HedrionApiClient(
        'http://localhost',
        client: transport,
        sessionStorage: storage,
      );
      expect(await restarted.restoreSession(), isTrue);
      expect(restarted.user, user);
      expect(storage.value!.token, 'fresh-access');
      expect(storage.value!.refreshToken, 'fresh-refresh');
      expect(storage.writes, 2);
    },
  );

  test(
    'expired refresh removes native persistence and notifies UI exactly once',
    () async {
      final storage = MemorySessionStorage()..value = saved();
      var expired = 0;
      final api =
          HedrionApiClient(
              'http://localhost',
              sessionStorage: storage,
              client: MockClient(
                (request) async => reply({
                  'code': request.url.path.endsWith('/refresh')
                      ? 'invalidRefresh'
                      : 'sessionExpired',
                }, 401),
              ),
            )
            ..onSessionExpired = () async {
              expired++;
            };
      await expectLater(api.restoreSession(), throwsA(sessionExpired()));
      expect(expired, 1);
      expect(storage.value, isNull);
      expect(api.token, isNull);
      expect(api.refreshToken, isNull);
      expect(api.user, isNull);
    },
  );

  test(
    'native restart without network keeps identity for durable offline workspace',
    () async {
      final storage = MemorySessionStorage()..value = saved();
      final api = HedrionApiClient(
        'http://localhost',
        sessionStorage: storage,
        client: MockClient((_) async => throw http.ClientException('offline')),
      );
      expect(await api.restoreSession(), isTrue);
      expect(api.user, user);
      expect(storage.clears, 0);
    },
  );

  test(
    'server-provided refresh deadline also expires native offline restore',
    () async {
      final deadline = DateTime.utc(2026, 11, 14, 12);
      final storage = MemorySessionStorage()
        ..value = StoredSession(
          token: 'old-access',
          refreshToken: 'old-refresh',
          user: user,
          refreshExpiresAt: deadline,
        );
      var requests = 0, expired = 0;
      final api =
          HedrionApiClient(
              'http://localhost',
              sessionStorage: storage,
              clock: () => deadline,
              client: MockClient((_) async {
                requests++;
                throw http.ClientException('offline');
              }),
            )
            ..onSessionExpired = () async {
              expired++;
            };
      await expectLater(api.restoreSession(), throwsA(sessionExpired()));
      expect(requests, 0);
      expect(expired, 1);
      expect(storage.value, isNull);
    },
  );

  test(
    'logout submits refresh credential even with expired access and clears persisted session',
    () async {
      final storage = MemorySessionStorage()..value = saved();
      var calls = 0;
      final api =
          HedrionApiClient(
              'http://localhost',
              browserScope: 'backoffice',
              sessionStorage: storage,
              client: MockClient((request) async {
                calls++;
                expect(request.url.path, '/api/v1/auth/logout');
                expect(request.headers['authorization'], 'Bearer old-access');
                expect(
                  (jsonDecode(request.body) as Map)['refreshToken'],
                  'old-refresh',
                );
                return reply({'loggedOut': true});
              }),
            )
            ..token = 'old-access'
            ..refreshToken = 'old-refresh'
            ..user = user;
      await api.logout();
      expect(calls, 1);
      expect(storage.value, isNull);
      expect(api.user, isNull);
    },
  );

  test(
    'failed network logout still clears the native secure-storage port',
    () async {
      final storage = MemorySessionStorage()..value = saved();
      final api =
          HedrionApiClient(
              'http://localhost',
              sessionStorage: storage,
              client: MockClient(
                (_) async => throw http.ClientException('offline'),
              ),
            )
            ..token = 'old-access'
            ..refreshToken = 'old-refresh'
            ..user = user;
      await expectLater(api.logout(), throwsA(isA<DomainException>()));
      expect(storage.value, isNull);
      expect(api.token, isNull);
    },
  );

  test(
    'browser restore uses scoped cookie transport and never calls native storage',
    () async {
      final storage = MemorySessionStorage();
      final api = HedrionApiClient(
        'http://localhost',
        browserSession: true,
        browserScope: 'backoffice',
        sessionStorage: storage,
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map;
          expect(body['browserSession'], isTrue);
          expect(body['browserSessionScope'], 'backoffice');
          expect(body.containsKey('refreshToken'), isFalse);
          return reply({'token': 'cookie-access', 'user': user});
        }),
      );
      expect(await api.restoreSession(), isTrue);
      expect(api.refreshToken, isNull);
      expect(storage.writes, 0);
      expect(storage.clears, 0);
    },
  );

  test(
    'new browser visitor has no expiry warning when cookie is absent',
    () async {
      var expired = false;
      final api =
          HedrionApiClient(
              'http://localhost',
              browserSession: true,
              client: MockClient(
                (_) async => reply({'code': 'unauthenticated'}, 401),
              ),
            )
            ..onSessionExpired = () async {
              expired = true;
            };
      expect(await api.restoreSession(), isFalse);
      expect(expired, isFalse);
    },
  );

  test(
    'idle client expires at the server deadline without waiting for another request',
    () async {
      final storage = MemorySessionStorage();
      final expired = Completer<void>();
      final api =
          HedrionApiClient(
              'http://localhost',
              sessionStorage: storage,
              client: MockClient(
                (_) async => reply({
                  'token': 'access',
                  'refreshToken': 'refresh',
                  'user': user,
                  'refreshExpiresAt': DateTime.now()
                      .toUtc()
                      .add(const Duration(milliseconds: 20))
                      .toIso8601String(),
                }),
              ),
            )
            ..onSessionExpired = () async {
              expired.complete();
            };
      await api.login('creator@example.test', 'password');
      await expired.future.timeout(const Duration(seconds: 5));
      expect(api.user, isNull);
      expect(storage.value, isNull);
      api.close();
    },
  );
}
