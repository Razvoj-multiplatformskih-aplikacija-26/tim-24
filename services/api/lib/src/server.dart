import 'dart:io';
import 'package:relic/relic.dart';
import 'bootstrap.dart';
import 'database.dart';
import 'http_api.dart';
import 'scheduler.dart';
import 'service.dart';

/// Shared startup for apps/server and the legacy CLI path.
/// Requests, routing and streaming bodies use native Relic 1.2.0 types.
Future<void> runHedrionServer() async {
  final env = Platform.environment, url = env['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln('Set DATABASE_URL or start docker compose up --build.');
    exitCode = 64;
    return;
  }
  final secret = env['WORKER_SHARED_SECRET'] ?? '';
  if (secret.length < 32) {
    stderr.writeln('WORKER_SHARED_SECRET must contain at least 32 characters.');
    exitCode = 64;
    return;
  }
  final prefix = Directory('infrastructure').existsSync() ? '' : '../../';
  final storagePath = env['OBJECT_STORAGE_PATH'] ?? '$prefix.data/objects';
  await bootstrapDatabase(
    databaseUrl: url,
    storagePath: storagePath,
    seedDemo: env['SEED_DEMO_DATA'] == 'true',
    migrationFile: env['MIGRATION_FILE'] ??
        '${prefix}infrastructure/migrations/001_initial.sql',
    seedAssetPath: env['SEED_ASSET_PATH'] ?? '${prefix}infrastructure/seed',
    environment: env,
  );
  Duration ttl(String key, int fallback) {
    final seconds = int.tryParse(env[key] ?? '$fallback');
    if (seconds == null || seconds <= 0) {
      throw FormatException('$key must be a positive number of seconds.');
    }
    return Duration(seconds: seconds);
  }

  final database = Database.connect(url);
  final service = HedrionService(
    database,
    storagePath,
    sessionAccessTtl: ttl('SESSION_ACCESS_TTL_SECONDS', 3600),
    sessionRefreshTtl: ttl('SESSION_REFRESH_TTL_SECONDS', 2592000),
    generationProvider: env['GENERATION_PROVIDER'] ?? 'fake',
    enabledGenerationModels:
        (env['ENABLED_GENERATION_MODELS'] ?? 'spar3d,hunyuan3d_21,trellis2')
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
  );
  await service.reconcileStorage();
  final scheduler = JobScheduler(
    service,
    workerUrl: env['WORKER_URL'] ?? 'http://127.0.0.1:8091',
    workerSecret: secret,
  );
  final api = HttpApi(
    service,
    scheduler,
    secureCookies: env['SECURE_COOKIES'] != 'false',
    origins:
        (env['CORS_ORIGINS'] ?? 'http://localhost:8082,http://localhost:8083')
            .split(',')
            .where((s) => s.isNotEmpty)
            .toList(),
    workerSecret: secret,
  );
  final app = RelicApp()..fallback = api.handler;
  final bind = env['API_BIND'] ?? '127.0.0.1';
  final address = InternetAddress.tryParse(bind) ??
      (await InternetAddress.lookup(bind)).first;
  final port = int.parse(env['API_PORT'] ?? '8080');
  await app.serve(address: address, port: port);
  scheduler.start();
  stdout.writeln('Hedrion API http://$bind:$port (Relic 1.2.0, PostgreSQL)');
  Future<void> stop(ProcessSignal _) async {
    await app.close();
    await scheduler.close();
    await database.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
}
