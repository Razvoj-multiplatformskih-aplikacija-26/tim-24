import 'dart:io';
import 'package:hedrion_api/hedrion_api.dart';

Future<void> main(List<String> args) async {
  if (args.contains('--healthcheck')) {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    try {
      final port = Platform.environment['API_PORT'] ?? '8080';
      final request = await client.getUrl(
        Uri.parse('http://127.0.0.1:$port/health'),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 3),
      );
      await response.drain<void>();
      exitCode = response.statusCode == 200 ? 0 : 1;
    } catch (_) {
      exitCode = 1;
    } finally {
      client.close(force: true);
    }
    return;
  }
  await runHedrionServer();
}
