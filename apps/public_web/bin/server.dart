import 'dart:io';

import 'package:hedrion_public_web/hedrion_public_web.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final env = Platform.environment;
  final config = PublicWebConfig(
    apiOrigin: Uri.parse(env['API_ORIGIN'] ?? 'http://127.0.0.1:8080'),
    publicOrigin: Uri.parse(env['PUBLIC_ORIGIN'] ?? 'http://localhost:8081'),
    studioOrigin: Uri.parse(env['STUDIO_ORIGIN'] ?? 'http://localhost:8082'),
  );
  final client = http.Client();
  final site = PublicSite(config, HttpPublicCatalog(config.apiOrigin, client));
  final server = await shelf_io.serve(
    site.handler,
    env['HOST'] ?? '127.0.0.1',
    int.parse(env['PORT'] ?? '8081'),
  );
  stdout.writeln(
    'Hedrion public web: http://${server.address.host}:${server.port}',
  );
}
