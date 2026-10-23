import 'dart:convert';
import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

void main() {
  final records = seedAssets(ownerId: const UserId('creator'));
  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json'},
  );
  test(
    'private library follows every cursor page beyond first hundred',
    () async {
      final cursors = <String?>[];
      final api = HedrionApiClient(
        'http://localhost:8080',
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/assets');
          final cursor = request.url.queryParameters['cursor'];
          cursors.add(cursor);
          return json({
            'assets':
                (cursor == null ? records.take(2) : records.skip(2).take(2))
                    .map((a) => a.toJson())
                    .toList(),
            'nextCursor': cursor == null ? 'opaque cursor/+' : null,
          });
        }),
      );
      final loaded = await ApiAssetRepository(api).loadAssets();
      expect(
        loaded.map((a) => a.id.value),
        records.take(4).map((a) => a.id.value),
      );
      expect(cursors, [null, 'opaque cursor/+']);
      api.close();
    },
  );
  test(
    'moderation paging commits stats and audit metadata with all records',
    () async {
      final api = HedrionApiClient(
        'http://localhost:8080',
        client: MockClient((request) async {
          final index = request.url.queryParameters.containsKey('cursor')
                  ? 1
                  : 0,
              asset = records[index];
          return json({
            'assets': [asset.toJson()],
            'nextCursor': index == 0 ? 'second-page' : null,
            'stats': {
              'reviewedToday': 3,
              'approvalRate': 2 / 3,
              'activeJobs': 2,
            },
            'submissions': [
              {
                'id': 'submission-$index',
                'assetId': asset.id.value,
                'revision': 4,
                'status': 'pending_review',
                'submitterName': 'Kreator $index',
                'submittedAt': '2026-10-22T01:00:00Z',
                'reviewedAt': null,
                'reviewedBy': null,
                'audit': [
                  {
                    'actorName': 'Moderator',
                    'action': 'rejected',
                    'createdAt': '2026-10-21T01:00:00Z',
                    'reason': 'Dopunite opis.',
                  },
                ],
                'snapshot': asset.toJson(),
              },
            ],
          });
        }),
      );
      final repository = ApiAssetRepository(api, moderator: true);
      expect((await repository.loadAssets()).length, 2);
      expect(repository.moderationStats['reviewedToday'], 3);
      expect(
        repository.submissionsByAssetId[records[1].id.value]!['submitterName'],
        'Kreator 1',
      );
      expect(
        (repository.submissionsByAssetId[records[1].id.value]!['audit'] as List)
            .single['reason'],
        'Dopunite opis.',
      );
      api.close();
    },
  );
  test(
    'repeated pagination cursor fails without committing partial metadata',
    () async {
      var valid = true;
      final api = HedrionApiClient(
        'http://localhost:8080',
        client: MockClient(
          (request) async => json({
            'assets': [records[0].toJson()],
            'submissions': [],
            'stats': {'reviewedToday': valid ? 1 : 99},
            'nextCursor': valid ? null : 'loop',
          }),
        ),
      );
      final repository = ApiAssetRepository(api, moderator: true);
      await repository.loadAssets();
      valid = false;
      await expectLater(
        repository.loadAssets(),
        throwsA(isA<DomainException>()),
      );
      expect(repository.moderationStats['reviewedToday'], 1);
      api.close();
    },
  );
  test(
    'expired upload authorization refreshes once before retrying same bytes',
    () async {
      var uploads = 0, refreshes = 0;
      final payload = Uint8List.fromList([137, 80, 78, 71]);
      final api =
          HedrionApiClient(
              'http://localhost:8080',
              client: MockClient((request) async {
                if (request.url.path.endsWith('/refresh')) {
                  refreshes++;
                  return json({
                    'token': 'fresh',
                    'refreshToken': 'rotated',
                    'user': {'id': 'creator', 'role': 'creator'},
                  });
                }
                uploads++;
                expect(request.bodyBytes, payload);
                if (uploads == 1) {
                  expect(request.headers['Authorization'], 'Bearer stale');
                  return json({'code': 'unauthenticated'}, 401);
                }
                expect(request.headers['Authorization'], 'Bearer fresh');
                return json({'asset': records[0].toJson()});
              }),
            )
            ..token = 'stale'
            ..refreshToken = 'refresh';
      await api.uploadImage(records[0].id, payload, mime: 'image/png');
      expect(uploads, 2);
      expect(refreshes, 1);
      api.close();
    },
  );
  test(
    'file authorization refresh is bounded and quota failure never retries',
    () async {
      var downloads = 0, refreshes = 0;
      final api =
          HedrionApiClient(
              'http://localhost:8080',
              client: MockClient((request) async {
                if (request.url.path.endsWith('/refresh')) {
                  refreshes++;
                  return json({
                    'token': 'fresh',
                    'refreshToken': 'rotated',
                    'user': {'id': 'creator'},
                  });
                }
                downloads++;
                return json({'code': 'unauthenticated'}, 401);
              }),
            )
            ..token = 'stale'
            ..refreshToken = 'refresh';
      await expectLater(
        api.fileBytes('/api/v1/files/model'),
        throwsA(
          isA<DomainException>().having(
            (e) => e.error.code,
            'unauthenticated',
            ErrorCode.unauthenticated,
          ),
        ),
      );
      expect(downloads, 2);
      expect(refreshes, 1);
      api.close();
      var attempts = 0;
      final quota = HedrionApiClient(
        'http://localhost:8080',
        client: MockClient((request) async {
          attempts++;
          return json({'code': 'dailyTransferQuotaExceeded'}, 429);
        }),
      )..refreshToken = 'refresh';
      await expectLater(
        quota.fileBytes('/api/v1/files/model'),
        throwsA(
          isA<DomainException>().having(
            (e) => e.error.code,
            'quota',
            ErrorCode.dailyTransferQuotaExceeded,
          ),
        ),
      );
      expect(attempts, 1);
      quota.close();
    },
  );
  test('interrupted upload is not automatically sent twice', () async {
    var attempts = 0;
    final api = HedrionApiClient(
      'http://localhost:8080',
      client: MockClient((request) async {
        attempts++;
        throw http.ClientException('connection interrupted');
      }),
    )..refreshToken = 'refresh';
    await expectLater(
      api.uploadImage(
        records[0].id,
        Uint8List.fromList([1, 2, 3]),
        mime: 'image/png',
      ),
      throwsA(isA<DomainException>()),
    );
    expect(attempts, 1);
    api.close();
  });
}
