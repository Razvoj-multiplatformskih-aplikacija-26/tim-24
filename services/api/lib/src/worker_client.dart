import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'database.dart';
import 'security.dart';
import 'service.dart';

/// A submission is sent once. Only status requests are safe to repeat when a
/// remote GPU may already be spending money on an accepted submission.
class WorkerClient {
  WorkerClient({
    required String url,
    required this.secret,
    this.timeout = const Duration(minutes: 45),
    this.pollInterval = const Duration(seconds: 3),
    http.Client? client,
    Future<void> Function(Duration)? delay,
  })  : url = url.replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client(),
        _ownsClient = client == null,
        _delay = delay ?? Future<void>.delayed;

  final String url, secret;
  final Duration timeout, pollInterval;
  final http.Client _client;
  final bool _ownsClient;
  final Future<void> Function(Duration) _delay;
  static const maxResponseBytes = 200000000;

  Future<Json> generate(Json payload) async {
    final watch = Stopwatch()..start();
    Duration remaining() {
      final result = timeout - watch.elapsed;
      if (result <= Duration.zero) {
        throw const ApiFailure(
            504, 'workerTimeout', 'Generisanje je trajalo predugo.');
      }
      return result;
    }

    try {
      var response = await _post('/internal/v1/generate', payload, remaining());
      while (response.$1 == 202) {
        if (response.$2['jobId'] != payload['jobId']) {
          throw const ApiFailure(
              502, 'jobMismatch', 'Worker je vratio drugi zahtev.');
        }
        final rest = remaining();
        await _delay(rest < pollInterval ? rest : pollInterval);
        // Polling never launches a second paid GPU call. Keep polling across a
        // transient gateway outage, without retrying the original submission.
        try {
          final rest = remaining();
          response = await _post(
              '/internal/v1/result',
              {
                'jobId': payload['jobId'],
                'ownerId': payload['ownerId'],
              },
              rest < const Duration(seconds: 30)
                  ? rest
                  : const Duration(seconds: 30));
          if ([502, 503, 504].contains(response.$1)) {
            response = (202, {'jobId': payload['jobId']});
          }
        } on TimeoutException {
          response = (202, {'jobId': payload['jobId']});
        } on http.ClientException {
          response = (202, {'jobId': payload['jobId']});
        }
      }
      if (response.$1 != 200) {
        final remoteCode = response.$2['code'];
        final code = switch (remoteCode) {
          'ModelAccessRequired' => 'modelAccessRequired',
          'UnsupportedModel' || 'ModelUnavailable' => 'modelUnavailable',
          'WorkerTimeout' => 'workerTimeout',
          _ => 'workerFailed',
        };
        throw ApiFailure(502, code, 'Generisanje nije uspelo.');
      }
      if (response.$2['jobId'] != payload['jobId']) {
        throw const ApiFailure(
            502, 'jobMismatch', 'Rezultat pripada drugom zahtevu.');
      }
      return response.$2;
    } on TimeoutException {
      throw const ApiFailure(
          504, 'workerTimeout', 'Generisanje je trajalo predugo.');
    } finally {
      if (_ownsClient) _client.close();
    }
  }

  Future<(int, Json)> _post(
      String path, Json payload, Duration remaining) async {
    final encoded = jsonEncode(payload);
    final timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
    final nonce = newId();
    final request = http.Request('POST', Uri.parse('$url$path'))
      ..followRedirects = false
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer $secret',
        'x-hedrion-timestamp': timestamp,
        'x-hedrion-nonce': nonce,
        'x-hedrion-signature':
            workerSignature(secret, timestamp, nonce, encoded),
      })
      ..body = encoded;
    return (() async {
      final response = await _client.send(request);
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        if (bytes.length + chunk.length > maxResponseBytes) {
          throw const ApiFailure(
              502, 'workerOutputTooLarge', 'Rezultat je prevelik.');
        }
        bytes.add(chunk);
      }
      try {
        final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
        return (response.statusCode, jsonMap(decoded));
      } on FormatException {
        throw const ApiFailure(502, 'invalidWorkerOutput',
            'Worker je vratio neispravan rezultat.');
      }
    })()
        .timeout(remaining);
  }
}
