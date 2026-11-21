import 'dart:async';
import 'dart:convert';
import 'package:hedrion_api/hedrion_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  const secret = 'test-remote-worker-secret-at-least-32';
  const input = <String, dynamic>{
    'jobId': 'test-job',
    'ownerId': 'creator',
    'inputType': 'text_to_3d',
    'sourcePrompt': 'A clockwork owl',
    'modelProvider': 'trellis2',
    'seed': 42,
  };
  test('one signed submission polls asynchronously using new signed nonces',
      () async {
    final paths = <String>[], nonces = <String>{};
    final client = MockClient((request) async {
      paths.add(request.url.path);
      expect(request.followRedirects, isFalse);
      expect(request.headers['authorization'], 'Bearer $secret');
      final timestamp = request.headers['x-hedrion-timestamp']!;
      final nonce = request.headers['x-hedrion-nonce']!;
      expect(nonces.add(nonce), isTrue);
      expect(request.headers['x-hedrion-signature'],
          workerSignature(secret, timestamp, nonce, request.body));
      if (request.url.path.endsWith('generate')) {
        expect(jsonDecode(request.body), input);
        return http.Response('{"jobId":"test-job","status":"running"}', 202);
      }
      expect(jsonDecode(request.body),
          {'jobId': 'test-job', 'ownerId': 'creator'});
      return http.Response(
          jsonEncode({'jobId': 'test-job', 'provider': 'trellis2'}), 200);
    });
    final result = await WorkerClient(
            url: 'https://worker.example/',
            secret: secret,
            client: client,
            delay: (_) async {})
        .generate(input);
    expect(result['provider'], 'trellis2');
    expect(paths, ['/internal/v1/generate', '/internal/v1/result']);
    client.close();
  });

  test('a temporary polling outage does not resubmit the paid generation',
      () async {
    var submissions = 0, polls = 0;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('generate')) {
        submissions++;
        return http.Response('{"jobId":"test-job"}', 202);
      }
      polls++;
      if (polls == 1) return http.Response('{"code":"Unavailable"}', 503);
      if (polls == 2) {
        throw http.ClientException('Temporary connection failure');
      }
      return http.Response('{"jobId":"test-job","provider":"trellis2"}', 200);
    });
    await WorkerClient(
            url: 'https://worker.example',
            secret: secret,
            client: client,
            delay: (_) async {})
        .generate(input);
    expect(submissions, 1);
    expect(polls, 3);
    client.close();
  });

  test('an ambiguous submission transport failure is never repeated', () async {
    var submissions = 0;
    final client = MockClient((request) async {
      submissions++;
      throw http.ClientException('Response lost after submit');
    });
    await expectLater(
        WorkerClient(
                url: 'https://worker.example',
                secret: secret,
                client: client,
                delay: (_) async {})
            .generate(input),
        throwsA(isA<http.ClientException>()));
    expect(submissions, 1);
    client.close();
  });

  test('terminal failure and mismatched job IDs fail without a paid retry',
      () async {
    for (final response in [
      http.Response('{"code":"GenerationFailed"}', 422),
      http.Response('{"jobId":"another-job"}', 202),
      http.Response('{"jobId":"another-job"}', 200),
    ]) {
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return response;
      });
      await expectLater(
          WorkerClient(
                  url: 'https://worker.example',
                  secret: secret,
                  client: client,
                  delay: (_) async {})
              .generate(input),
          throwsA(isA<ApiFailure>()));
      expect(calls, 1);
      client.close();
    }
  });

  test('submission timeout is bounded and never causes automatic resubmission',
      () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      return http.Response('{"jobId":"test-job"}', 202);
    });
    await expectLater(
        WorkerClient(
                url: 'https://worker.example',
                secret: secret,
                client: client,
                timeout: const Duration(milliseconds: 2))
            .generate(input),
        throwsA(
            isA<ApiFailure>().having((e) => e.code, 'code', 'workerTimeout')));
    expect(calls, 1);
    client.close();
  });

  group('model options before paid admission', () {
    late Database db;
    late HedrionService service;
    setUp(() {
      db = Database.connect(
          'postgres://unused:unused@127.0.0.1:1/unused?sslmode=disable');
      service = HedrionService(db, 'unused',
          generationProvider: 'modal',
          enabledGenerationModels: ['trellis2', 'hunyuan3d_21']);
    });
    tearDown(() => db.close());
    test('advertises configured availability and accepts image and text inputs',
        () {
      expect(service.defaultGenerationModel, 'trellis2');
      expect(service.generationCapabilities['demo'], false);
      expect(service.generationCapabilities['textTo3d'], true);
      final models = service.generationCapabilities['generationModels'] as List;
      expect(models.first['available'], false);
      expect(
          service.validateGenerationOptions({})['modelProvider'], 'trellis2');
      expect(
          service.validateGenerationOptions({
            'inputType': 'text_to_3d',
            'sourcePrompt': 'An owl',
            'modelProvider': 'hunyuan3d_21',
            'seed': 123
          })['seed'],
          123);
    });
    test('rejects unavailable models, bad seeds and oversized prompts', () {
      for (final input in [
        {'modelProvider': 'spar3d'},
        {'modelProvider': 'unknown'},
        {'seed': -1},
        {'seed': 4294967296},
        {'seed': 1.5},
        {'sourcePrompt': List.filled(2001, 'a').join()},
        {'inputType': 'text_to_3d', 'sourcePrompt': '  '},
        {'inputType': 'other'},
      ]) {
        expect(() => service.validateGenerationOptions(input),
            throwsA(isA<ApiFailure>()));
      }
    });
  });
}
