import 'dart:convert';
import 'dart:io';
import 'package:domain/domain.dart';
import 'database.dart';
import 'security.dart';
import 'service.dart';

/// Creates the schema and optional local demonstration data before HTTP starts.
Future<void> bootstrapDatabase({
  required String databaseUrl,
  required String storagePath,
  bool seedDemo = false,
  String migrationFile = '../../infrastructure/migrations/001_initial.sql',
  String seedAssetPath = '../../infrastructure/seed',
  Map<String, String> environment = const {},
}) async {
  final db = Database.connect(databaseUrl);
  try {
    await migrateDatabase(db, File(migrationFile));
    if (seedDemo) {
      await seedDemoDatabase(db,
          storagePath: storagePath,
          seedAssetPath: seedAssetPath,
          environment: environment);
    }
  } finally {
    await db.close();
  }
}

/// Uses the same transaction lock as API writes, including concurrent startups.
Future<void> migrateDatabase(Database db, File migration) =>
    db.transaction((tx) async {
      await tx.query('''CREATE TABLE IF NOT EXISTS schema_migrations(
        version integer PRIMARY KEY,
        applied_at timestamptz NOT NULL DEFAULT now())''');
      if (await tx
              .one('SELECT version FROM schema_migrations WHERE version=1') !=
          null) {
        return;
      }
      // Migration 1 contains no procedural SQL or embedded semicolons.
      for (final statement in (await migration.readAsString()).split(';')) {
        if (statement.trim().isNotEmpty) await tx.query(statement);
      }
    });

/// A seed is applied once, atomically. Restarting never resets edits, passwords,
/// deleted records, quota usage, or any unrelated account/data in an existing DB.
Future<void> seedDemoDatabase(Database db,
    {required String storagePath,
    required String seedAssetPath,
    Map<String, String> environment = const {}}) async {
  final service = HedrionService(db, storagePath);
  await db.transaction((tx) async {
    await tx.query('''CREATE TABLE IF NOT EXISTS bootstrap_seeds(
      name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())''');
    const seedName = 'kt2_demo_v1';
    if (await tx.one('SELECT name FROM bootstrap_seeds WHERE name=@name',
            {'name': seedName}) !=
        null) {
      return;
    }
    final creatorPassword =
        environment['DEMO_CREATOR_PASSWORD'] ?? 'HedrionCreator123!';
    final moderatorPassword =
        environment['DEMO_MODERATOR_PASSWORD'] ?? 'HedrionModerator123!';
    final adminPassword =
        environment['DEMO_ADMIN_PASSWORD'] ?? 'HedrionAdmin123!';
    final accounts = [
      (
        id: 'kt2-demo-creator-1',
        email: 'creator1@hedrion.test',
        name: 'Demo kreator 1',
        role: 'creator',
        password: creatorPassword,
      ),
      (
        id: 'kt2-demo-creator-2',
        email: 'creator2@hedrion.test',
        name: 'Demo kreator 2',
        role: 'creator',
        password: creatorPassword,
      ),
      (
        id: 'kt2-demo-moderator',
        email: 'moderator@hedrion.test',
        name: 'Demo moderator',
        role: 'moderator',
        password: moderatorPassword,
      ),
      (
        id: 'kt2-demo-admin',
        email: 'admin@hedrion.test',
        name: 'Demo administrator',
        role: 'admin',
        password: adminPassword,
      ),
    ];
    for (final account in accounts) {
      if (account.password.length < 12) {
        throw StateError('Demo passwords must contain at least 12 characters.');
      }
      // Never appropriate or overwrite an account that predates this seed.
      final existing = await tx.one(
          'SELECT id FROM users WHERE id=@id OR email=@email',
          {'id': account.id, 'email': account.email});
      if (existing != null) {
        throw StateError(
            'Demo account already exists without a seed marker; disable SEED_DEMO_DATA for this database.');
      }
      await tx.query('''INSERT INTO users(
        id,email,password_hash,display_name,role)
        VALUES(@id,@email,@hash,@name,@role)''', {
        'id': account.id,
        'email': account.email,
        'hash': await Passwords.hash(account.password),
        'name': account.name,
        'role': account.role,
      });
    }
    final model = await File('$seedAssetPath/demo-model.glb').readAsBytes();
    final preview = await File('$seedAssetPath/demo-preview.png').readAsBytes();
    final now = DateTime.now().toUtc();
    for (var creator = 1; creator <= 2; creator++) {
      final ownerId = 'kt2-demo-creator-$creator';
      final projectId = 'kt2-demo-project-$creator';
      await tx.query('''INSERT INTO projects(id,owner_id,name)
        VALUES(@id,@owner,@name)''', {
        'id': projectId,
        'owner': ownerId,
        'name': 'Demo kolekcija $creator',
      });
      final examples = seedAssets(
          ownerId: UserId(ownerId),
          count: AssetLifecycle.values.length,
          now: now);
      for (var index = 0; index < examples.length; index++) {
        final example = examples[index];
        final id = 'kt2-demo-asset-$creator-${index + 1}';
        final data = <String, dynamic>{
          ...example.toJson(),
          'id': id,
          'projectId': projectId,
          'description':
              'Početni demonstracioni model za KT2. Geometrija je lokalni CPU primer.',
          'outputFileId': null,
          'previewFileId': null,
        };
        await tx.query('''INSERT INTO assets(id,owner_id,data)
          VALUES(@id,@owner,@data::jsonb)''', {
          'id': id,
          'owner': ownerId,
          'data': jsonEncode(data),
        });
        if (example.hasOutput) {
          final output = await service.persistFile(
              tx, ownerId, id, 'model', model, 'model/gltf-binary');
          final image = await service.persistFile(
              tx, ownerId, id, 'preview', preview, 'image/png');
          data['outputFileId'] = output['id'];
          data['previewFileId'] = image['id'];
          await tx.query('UPDATE assets SET data=@data::jsonb WHERE id=@id',
              {'id': id, 'data': jsonEncode(data)});
        }
        final status = switch (example.lifecycle) {
          AssetLifecycle.pendingReview => 'pending_review',
          AssetLifecycle.published => 'approved',
          AssetLifecycle.rejected => 'rejected',
          _ => null,
        };
        if (status != null) {
          final submissionId = 'kt2-demo-submission-$creator-${index + 1}';
          final reviewed = status != 'pending_review';
          final snapshot = {...data, 'lifecycle': 'ready'};
          await tx.query('''INSERT INTO publication_submissions(
            id,asset_id,submitter_id,status,snapshot,slug,submitted_at,
            reviewed_at,reviewed_by,rejection_reason)
            VALUES(@id,@asset,@owner,@status,@snapshot::jsonb,@slug,@now,
            @reviewedAt,@reviewer,@reason)''', {
            'id': submissionId,
            'asset': id,
            'owner': ownerId,
            'status': status,
            'snapshot': jsonEncode(snapshot),
            'slug': id,
            'now': now,
            'reviewedAt': reviewed ? now : null,
            'reviewer': reviewed ? 'kt2-demo-moderator' : null,
            'reason': status == 'rejected' ? example.rejectionReason : null,
          });
          if (reviewed) {
            await tx.query('''INSERT INTO moderation_events(
              id,submission_id,moderator_id,action,reason)
              VALUES(@id,@submission,'kt2-demo-moderator',@action,@reason)''', {
              'id': 'kt2-demo-event-$creator-${index + 1}',
              'submission': submissionId,
              'action': status,
              'reason': status == 'rejected' ? example.rejectionReason : null,
            });
          }
        }
      }
    }
    await tx.query(
        'INSERT INTO bootstrap_seeds(name) VALUES(@name)', {'name': seedName});
  });
}
