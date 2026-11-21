import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:hedrion_mobile/memory_asset_repository.dart';
import 'package:hedrion_mobile/studio_workflow_adapters.dart';
import 'package:hedrion_mobile/studio_workflows.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'local workflow preserves project revision conflicts and generation idempotence',
    () async {
      final assets = MemoryAssetRepository(latency: Duration.zero);
      final StudioWorkflows work = MemoryStudioWorkflows(assets);
      final project = await work.saveProject('Owl props');
      await work.saveProject(
        'Owl collection',
        id: project['id'] as String,
        baseRevision: 1,
      );
      await expectLater(
        work.saveProject(
          'Stale name',
          id: project['id'] as String,
          baseRevision: 1,
        ),
        throwsA(
          isA<DomainException>().having(
            (error) => error.error.code,
            'code',
            ErrorCode.revisionConflict,
          ),
        ),
      );
      expect((await work.loadProjects()).single['name'], 'Owl collection');
      final draft = await assets.createAsset(AssetDraft(title: 'Owl model'));
      await work.generate(draft, idempotencyKey: 'owl-request');
      await work.generate(draft, idempotencyKey: 'owl-request');
      expect(assets.acceptedToday, 19);
      expect(
        (await assets.loadAssets()).first.lifecycle,
        AssetLifecycle.queued,
      );
    },
  );

  test(
    'HTTP workflow assigns through shared asset adapter and sends selected generation',
    () async {
      final asset = seedAssets(ownerId: const UserId('creator')).first;
      final writes = <String>[];
      final observed = <http.Request>[];
      final api = HedrionApiClient(
        'https://studio.test',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/capabilities')) {
            return http.Response('{"demo":false}', 200);
          }
          observed.add(request);
          writes.add(request.method);
          if (request.method == 'PATCH') {
            return http.Response(
              jsonEncode({
                'asset': asset
                    .copyWith(
                      projectId: 'project-1',
                      revision: asset.revision + 1,
                    )
                    .toJson(),
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('{"job":{"id":"job-1","status":"queued"}}', 202);
        }),
      );
      final StudioWorkflows work = HttpStudioWorkflows(api);
      final assigned = await work.assignProject(asset, 'project-1');
      expect(assigned.projectId, 'project-1');
      await work.generate(
        assigned,
        idempotencyKey: 'owl-request',
        modelProvider: 'trellis2',
        inputType: 'text_to_3d',
        sourcePrompt: 'Owl model',
        seed: 17,
      );
      expect(writes, ['PATCH', 'POST']);
      expect(observed.first.headers['if-match'], '${asset.revision}');
      expect(
        (jsonDecode(observed.first.body) as Map)['projectId'],
        'project-1',
      );
      final body = jsonDecode(observed.last.body) as Map;
      expect(body['modelProvider'], 'trellis2');
      expect(body['inputType'], 'text_to_3d');
      expect(body['sourcePrompt'], 'Owl model');
      expect(body['seed'], 17);
      expect(observed.last.headers['idempotency-key'], 'owl-request');
      api.close();
    },
  );
}
