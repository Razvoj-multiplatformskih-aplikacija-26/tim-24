import 'dart:io';
import 'package:hedrion_api/src/bootstrap.dart';

Future<void> main() async {
  final env = Platform.environment;
  final url = env['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('Set DATABASE_URL before bootstrapping the database.');
    exitCode = 64;
    return;
  }
  await bootstrapDatabase(
    databaseUrl: url,
    storagePath: env['OBJECT_STORAGE_PATH'] ?? '../../.local/objects',
    seedDemo: env['SEED_DEMO_DATA'] == 'true',
    migrationFile: env['MIGRATION_FILE'] ??
        '../../infrastructure/migrations/001_initial.sql',
    seedAssetPath: env['SEED_ASSET_PATH'] ?? '../../infrastructure/seed',
    environment: env,
  );
  stdout.writeln('Database schema and requested demonstration seed are ready.');
}
