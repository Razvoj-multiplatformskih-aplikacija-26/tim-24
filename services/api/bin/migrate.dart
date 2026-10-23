import 'dart:io';
import 'package:postgres/postgres.dart';

Future<void> main() async {
  final url = Platform.environment['DATABASE_URL'];
  if (url == null) {
    stderr.writeln('Set DATABASE_URL.');
    exitCode = 64;
    return;
  }
  final connection = await Connection.openFromUrl(url);
  try {
    await connection.runTx((tx) async {
      await tx.execute('SELECT pg_advisory_xact_lock(72419831)');
      await tx.execute(
          'CREATE TABLE IF NOT EXISTS schema_migrations(version integer PRIMARY KEY,applied_at timestamptz NOT NULL DEFAULT now())');
      final applied = await tx
          .execute('SELECT version FROM schema_migrations WHERE version=1');
      if (applied.isNotEmpty) {
        stdout.writeln('Migration 1 already applied.');
        return;
      }
      final file = File(Platform.environment['MIGRATION_FILE'] ??
          '../../infrastructure/migrations/001_initial.sql');
      // This migration contains no procedural SQL; split on statement terminators.
      for (final statement in (await file.readAsString()).split(';')) {
        if (statement.trim().isNotEmpty) await tx.execute(statement);
      }
      stdout.writeln('Applied migration 1.');
    });
  } finally {
    await connection.close();
  }
}
