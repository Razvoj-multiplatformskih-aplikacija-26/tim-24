import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final provider in ['spar3d', 'hunyuan3d_21', 'trellis2']) {
    for (final input in ['image_to_3d', 'text_to_3d']) {
      test(
        'generation sends $provider and $input without provider credentials',
        () async {
          final api = HedrionApiClient(
            'https://studio.test',
            client: MockClient((request) async {
              expect(request.method, 'POST');
              expect(request.url.path, '/api/v1/assets/asset-1/generations');
              expect(request.headers['if-match'], '4');
              expect(request.headers['idempotency-key'], 'request-1');
              expect(jsonDecode(request.body), {
                'inputType': input,
                'sourcePrompt': input == 'text_to_3d'
                    ? 'Brass clockwork owl'
                    : null,
                'modelProvider': provider,
                'seed': 123,
                'baseRevision': 4,
              });
              return http.Response(
                '{"job":{"id":"job-1","status":"queued"}}',
                202,
              );
            }),
          );
          final result = await api.generate(
            const AssetId('asset-1'),
            baseRevision: 4,
            idempotencyKey: 'request-1',
            modelProvider: provider,
            inputType: input,
            sourcePrompt: input == 'text_to_3d' ? 'Brass clockwork owl' : null,
            seed: 123,
          );
          expect((result['job'] as Map)['status'], 'queued');
          api.close();
        },
      );
    }
  }
}
