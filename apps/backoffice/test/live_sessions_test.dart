import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:hedrion_backoffice/live_backoffice.dart';
import 'package:hedrion_backoffice/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final class FakeSessionStorage implements SessionStorage {
  StoredSession? value;
  @override
  Future<StoredSession?> read() async => value;
  @override
  Future<void> write(StoredSession session) async => value = session;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  const moderator = {
    'id': 'm',
    'role': 'moderator',
    'displayName': 'Moderator',
    'email': 'm@example.test',
  };
  http.Response reply(Object data, [int status = 200]) =>
      http.Response(jsonEncode(data), status);

  testWidgets(
    'desktop persisted login restores, expired refresh returns to login with explanation',
    (tester) async {
      final storage = FakeSessionStorage()
        ..value = StoredSession(
          token: 'access',
          refreshToken: 'refresh',
          user: moderator,
        );
      var expired = false;
      final api = HedrionApiClient(
        'http://localhost',
        browserSession: false,
        browserScope: 'backoffice',
        sessionStorage: storage,
        client: MockClient((request) async {
          if (request.url.path.endsWith('/me')) {
            return expired
                ? reply({'code': 'sessionExpired'}, 401)
                : reply(moderator);
          }
          if (request.url.path.endsWith('/refresh')) {
            return reply({'code': 'invalidRefresh'}, 401);
          }
          return reply({'assets': [], 'submissions': [], 'stats': {}});
        }),
      );
      await tester.pumpWidget(LiveBackoffice(client: api));
      await tester.pumpAndSettle();
      expect(find.byType(HedrionBackoffice), findsOneWidget);
      expired = true;
      await expectLater(
        api.me(),
        throwsA(
          isA<DomainException>().having(
            (e) => e.error.code,
            'code',
            ErrorCode.sessionExpired,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HedrionBackoffice), findsNothing);
      expect(
        find.text('Sesija je istekla. Prijavite se ponovo.'),
        findsOneWidget,
      );
      expect(storage.value, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('creator login shows the shared backoffice role explanation', (
    tester,
  ) async {
    final api = HedrionApiClient(
      'http://localhost',
      browserSession: false,
      browserScope: 'backoffice',
      sessionStorage: FakeSessionStorage(),
      client: MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          expect(
            (jsonDecode(request.body) as Map)['browserSessionScope'],
            'backoffice',
          );
          return reply({'code': 'backofficeRoleRequired'}, 403);
        }
        return reply({'loggedOut': true});
      }),
    );
    await tester.pumpWidget(LiveBackoffice(client: api));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).first,
      'creator@example.test',
    );
    await tester.enterText(find.byType(TextField).last, 'test-password');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(
      find.text('Backoffice je namenjen moderatorima i administratorima.'),
      findsOneWidget,
    );
    expect(find.byType(HedrionBackoffice), findsNothing);
  });
}
