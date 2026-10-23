import 'dart:io';
import 'package:hedrion_api/hedrion_api.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final env = Platform.environment, url = env['DATABASE_URL'];
  if (url == null || url.isEmpty) {
    stderr.writeln(
        'Set DATABASE_URL. Run dart run bin/migrate.dart before starting API.');
    exitCode = 64;
    return;
  }
  final secret = env['WORKER_SHARED_SECRET'] ?? '';
  if (secret.length < 32) {
    stderr.writeln('WORKER_SHARED_SECRET must contain at least 32 characters.');
    exitCode = 64;
    return;
  }
  final database = Database.connect(url),
      service = HedrionService(
          database, env['OBJECT_STORAGE_PATH'] ?? '../../.data/objects',
          generationProvider: env['GENERATION_PROVIDER'] ?? 'fake');
  await database.transaction((tx) =>
      tx.query('SELECT version FROM schema_migrations WHERE version=1'));
  await service.reconcileStorage();
  final scheduler = JobScheduler(service,
      workerUrl: env['WORKER_URL'] ?? 'http://127.0.0.1:8091',
      workerSecret: secret);
  final api = HttpApi(service, scheduler,
      secureCookies: env['SECURE_COOKIES'] != 'false',
      origins:
          (env['CORS_ORIGINS'] ?? 'http://localhost:8082,http://localhost:8083')
              .split(',')
              .where((s) => s.isNotEmpty)
              .toList(),
      workerSecret: secret);
  final server = await io.serve(api.handler, env['API_BIND'] ?? '127.0.0.1',
      int.parse(env['API_PORT'] ?? '8080'));
  scheduler.start();
  stdout.writeln(
      'Hedrion API http://${server.address.host}:${server.port} (PostgreSQL, worker-backed)');
  Future<void> stop(ProcessSignal _) async {
    await server.close(force: true);
    await scheduler.close();
    await database.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(stop);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(stop);
}
