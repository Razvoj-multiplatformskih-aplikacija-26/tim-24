import 'dart:io';
import 'package:hedrion_api/hedrion_api.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  group('server-configured sessions', () {
    late Connection admin;
    late Database db;
    late HedrionService service;
    final schema =
        'hedrion_session_test_${DateTime.now().microsecondsSinceEpoch}';
    final started = DateTime.utc(2026, 11, 14, 12);
    var current = DateTime.utc(2026, 11, 14, 12);
    const password = 'session-test-password';
    setUpAll(() async {
      admin = await Connection.openFromUrl(url!);
      await admin.execute('CREATE SCHEMA $schema');
      await admin.execute('SET search_path TO $schema');
      final rootMigration = File('infrastructure/migrations/001_initial.sql');
      final migration = await rootMigration.exists()
          ? rootMigration
          : File('../../infrastructure/migrations/001_initial.sql');
      for (final sql in (await migration.readAsString()).split(';')) {
        if (sql.trim().isNotEmpty) await admin.execute(sql);
      }
      db = Database(Pool.withUrl(url), schema: schema);
      service = HedrionService(db, Directory.systemTemp.path,
          clock: () => current,
          sessionAccessTtl: const Duration(seconds: 2),
          sessionRefreshTtl: const Duration(seconds: 5));
    });
    tearDownAll(() async {
      await db.close();
      await admin.execute('SET search_path TO public');
      await admin.execute('DROP SCHEMA $schema CASCADE');
      await admin.close();
    });
    setUp(() async {
      current = started;
      await db.transaction((tx) => tx.query('TRUNCATE users CASCADE'));
    });
    Future<Json> register() => service.register({
          'email': 'session@example.test',
          'password': password,
          'displayName': 'Session test'
        });
    Matcher failure(int status, String code) => isA<ApiFailure>()
        .having((e) => e.status, 'status', status)
        .having((e) => e.code, 'code', code);

    test(
        'configured access and refresh expiry are enforced by the server clock',
        () async {
      final session = await register();
      expect(DateTime.parse(session['expiresAt'] as String),
          started.add(const Duration(seconds: 2)));
      expect(DateTime.parse(session['refreshExpiresAt'] as String),
          started.add(const Duration(seconds: 5)));
      await service.authenticate(session['token'] as String);
      current = started.add(const Duration(seconds: 3));
      await expectLater(service.authenticate(session['token'] as String),
          throwsA(failure(401, 'sessionExpired')));
      current = started.add(const Duration(seconds: 6));
      await expectLater(
          service.refresh({'refreshToken': session['refreshToken']}),
          throwsA(failure(401, 'invalidRefresh')));
    });

    test(
        'logout revokes a refresh session even after its access credential expired',
        () async {
      final session = await register();
      current = started.add(const Duration(seconds: 3));
      await service.logout(session['token'] as String,
          refreshToken: session['refreshToken'] as String);
      await expectLater(
          service.refresh({'refreshToken': session['refreshToken']}),
          throwsA(failure(401, 'invalidRefresh')));
    });

    test('refresh rotation keeps the configured absolute login deadline',
        () async {
      final first = await register();
      current = started.add(const Duration(seconds: 4));
      final rotated =
          await service.refresh({'refreshToken': first['refreshToken']});
      expect(DateTime.parse(rotated['refreshExpiresAt'] as String),
          started.add(const Duration(seconds: 5)));
      expect(DateTime.parse(rotated['expiresAt'] as String),
          started.add(const Duration(seconds: 5)));
      current = started.add(const Duration(seconds: 5));
      await expectLater(service.authenticate(rotated['token'] as String),
          throwsA(failure(401, 'sessionExpired')));
      await expectLater(
          service.refresh({'refreshToken': rotated['refreshToken']}),
          throwsA(failure(401, 'invalidRefresh')));
    });

    test('backoffice scope rejects mobile user with the shared domain reason',
        () async {
      await register();
      await expectLater(
          service.login({
            'email': 'session@example.test',
            'password': password,
            'browserSessionScope': 'backoffice'
          }),
          throwsA(failure(403, 'backofficeRoleRequired')));
    });
  },
      skip: url == null
          ? 'Set TEST_DATABASE_URL for isolated PostgreSQL session tests.'
          : false);
}
