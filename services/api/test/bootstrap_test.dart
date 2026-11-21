import 'dart:convert';
import 'dart:io';
import 'package:domain/domain.dart';
import 'package:hedrion_api/hedrion_api.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  group('KT2 database bootstrap', () {
    late Connection admin;
    late Database db;
    late Directory objects;
    final schema = 'hedrion_bootstrap_${DateTime.now().microsecondsSinceEpoch}';
    final rootMigration = File('infrastructure/migrations/001_initial.sql');
    final migration = rootMigration.existsSync()
        ? rootMigration
        : File('../../infrastructure/migrations/001_initial.sql');
    final rootSeed = Directory('infrastructure/seed');
    final seedPath =
        rootSeed.existsSync() ? rootSeed.path : '../../infrastructure/seed';

    setUpAll(() async {
      admin = await Connection.openFromUrl(url!);
      await admin.execute('CREATE SCHEMA $schema');
      db = Database(Pool.withUrl(url), schema: schema);
      objects = await Directory.systemTemp.createTemp('hedrion-bootstrap-');
    });
    tearDownAll(() async {
      await db.close();
      await admin.execute('DROP SCHEMA $schema CASCADE');
      await admin.close();
      await objects.delete(recursive: true);
    });

    test('migrates, seeds every state and preserves edits on a second startup',
        () async {
      await migrateDatabase(db, migration);
      await migrateDatabase(db, migration);
      await db.transaction((tx) async {
        await tx.query('''INSERT INTO users(
          id,email,password_hash,display_name,role)
          VALUES('existing-user','existing@example.test','existing-hash',
          'Existing creator','creator')''');
      });
      await seedDemoDatabase(db,
          storagePath: objects.path, seedAssetPath: seedPath);
      await db.transaction((tx) async {
        expect((await tx.one('SELECT count(*) AS n FROM users'))!['n'], 5);
        expect((await tx.one('SELECT count(*) AS n FROM assets'))!['n'], 16);
        expect(
            (await tx.one('SELECT count(*) AS n FROM stored_files'))!['n'], 16);
        expect(
            (await tx.one(
                'SELECT count(*) AS n FROM publication_submissions'))!['n'],
            6);
        final states = await tx.query('''SELECT owner_id,
          count(DISTINCT data->>'lifecycle') AS states FROM assets
          GROUP BY owner_id''');
        expect(states, hasLength(2));
        expect(
            states
                .every((row) => row['states'] == AssetLifecycle.values.length),
            isTrue);
        final roles = await tx.query('SELECT DISTINCT role FROM users');
        expect(roles.map((row) => row['role']).toSet(),
            {'creator', 'moderator', 'admin'});
        final creator = await tx.one(
            "SELECT password_hash FROM users WHERE id='kt2-demo-creator-1'");
        final hash = creator!['password_hash'] as String;
        expect(hash, startsWith('pbkdf2-sha256\$600000\$'));
        expect(await Passwords.verify('HedrionCreator123!', hash), isTrue);
        final fileBytes = (await tx.one(
            'SELECT sum(byte_length)::bigint AS n FROM stored_files'))!['n'];
        expect(
            (await tx.one(
                'SELECT stored_bytes FROM storage_usage'))!['stored_bytes'],
            fileBytes);
        final asset = jsonMap((await tx.one(
            "SELECT data FROM assets WHERE id='kt2-demo-asset-1-1'"))!['data']);
        asset['title'] = 'User edited this model';
        await tx.query(
            "UPDATE assets SET data=@data::jsonb,revision=2 WHERE id='kt2-demo-asset-1-1'",
            {'data': jsonEncode(asset)});
        await tx.query(
            "UPDATE assets SET deleted_at=now() WHERE id='kt2-demo-asset-1-2'");
        await tx.query(
            "UPDATE users SET password_hash='user-changed-password' WHERE id='kt2-demo-creator-2'");
      });
      final before = await db.transaction((tx) => tx.query('''SELECT
        (SELECT count(*) FROM assets) AS assets,
        (SELECT count(*) FROM stored_files) AS files,
        stored_bytes,reserved_bytes FROM storage_usage'''));
      final diskCount = await objects.list().length;
      await migrateDatabase(db, migration);
      await seedDemoDatabase(db,
          storagePath: objects.path, seedAssetPath: seedPath);
      final after = await db.transaction((tx) async {
        final asset = await tx.one(
            "SELECT data,revision FROM assets WHERE id='kt2-demo-asset-1-1'");
        expect(jsonMap(asset!['data'])['title'], 'User edited this model');
        expect(asset['revision'], 2);
        expect(
            (await tx.one(
                    "SELECT deleted_at FROM assets WHERE id='kt2-demo-asset-1-2'"))![
                'deleted_at'],
            isNotNull);
        expect(
            (await tx.one(
                    "SELECT password_hash FROM users WHERE id='kt2-demo-creator-2'"))![
                'password_hash'],
            'user-changed-password');
        expect(
            (await tx.one(
                    "SELECT password_hash FROM users WHERE id='existing-user'"))![
                'password_hash'],
            'existing-hash');
        return tx.query('''SELECT
          (SELECT count(*) FROM assets) AS assets,
          (SELECT count(*) FROM stored_files) AS files,
          stored_bytes,reserved_bytes FROM storage_usage''');
      });
      expect(after, before);
      expect(await objects.list().length, diskCount);
    }, timeout: const Timeout(Duration(minutes: 2)));
  },
      skip: url == null
          ? 'Set TEST_DATABASE_URL for isolated PostgreSQL tests.'
          : false);
}
