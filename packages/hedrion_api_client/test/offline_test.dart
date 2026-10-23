import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final class MemoryDisk implements OfflinePersistence {
  String? disk;
  @override
  Future<Map<String, dynamic>?> read() async =>
      disk == null ? null : jsonDecode(disk!) as Map<String, dynamic>;
  @override
  Future<void> write(Map<String, dynamic> snapshot) async {
    disk = jsonEncode(snapshot);
  }
}

final class Remote implements AssetRepository, SyncAssetRepository {
  Asset record = seedAssets(
    ownerId: const UserId('owner'),
  ).first.copyWith(favorite: false);
  final Map<String, Asset> applied = {};
  @override
  Future<List<Asset>> loadAssets() async => [record];
  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) async {
    if (record.revision != baseRevision) {
      throw const DomainException(DomainError(ErrorCode.revisionConflict));
    }
    return record = asset.copyWith(revision: record.revision + 1);
  }

  @override
  Future<Asset> syncAsset(
    Asset asset,
    int baseRevision, {
    required String operationId,
  }) async => applied[operationId] ??= await updateAsset(asset, baseRevision);
  @override
  Future<Asset> createAsset(AssetDraft draft) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteAsset(AssetId id, int baseRevision) async =>
      throw UnimplementedError();
  @override
  Future<Asset> transitionAsset(
    AssetId id,
    AssetLifecycle target, {
    required int baseRevision,
    String? reason,
    String? idempotencyKey,
  }) async => throw UnimplementedError();
}

void main() {
  test(
    'online metadata persists tags while offline edits never silently drop them',
    () async {
      final remote = Remote(), disk = MemoryDisk();
      final cache = OfflineAssetRepository(
        remote,
        disk,
        ownerId: const UserId('owner'),
      );
      await cache.initialize();
      final original = (await cache.loadAssets()).single;
      final saved = await cache.updateAsset(
        original.copyWith(tags: ['drvo', 'igra'], projectId: 'project-1'),
        original.revision,
      );
      expect(remote.record.tags, ['drvo', 'igra']);
      expect(saved.projectId, 'project-1');
      cache.online = false;
      await expectLater(
        cache.updateAsset(saved.copyWith(tags: ['novo']), saved.revision),
        throwsA(isA<DomainException>()),
      );
      expect(cache.pendingCount, 0);
      expect((await cache.loadAssets()).single.tags, ['drvo', 'igra']);
    },
  );
  test(
    'browser refresh keeps scopes separate and persists session rotation',
    () async {
      var rotations = 0;
      final client = HedrionApiClient(
        'http://localhost:8080',
        browserSession: true,
        browserScope: 'backoffice',
        client: MockClient((request) async {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['browserSession'], isTrue);
          expect(body['browserSessionScope'], 'backoffice');
          if (request.url.path.endsWith('/logout')) {
            return http.Response('{}', 200);
          }
          expect(body.containsKey('refreshToken'), isFalse);
          return http.Response(
            jsonEncode({
              'token': 'rotated',
              'user': {'id': 'm', 'role': 'moderator'},
            }),
            200,
          );
        }),
      );
      client.onSessionChanged = () async {
        rotations++;
      };
      await client.refresh();
      expect(client.token, 'rotated');
      expect(client.refreshToken, isNull);
      await client.logout();
      expect(client.token, isNull);
      expect(rotations, 2);
      client.close();
    },
  );
  test(
    'expired metadata session refreshes once and retries with the new token',
    () async {
      var refreshes = 0;
      final client =
          HedrionApiClient(
              'http://localhost:8080',
              client: MockClient((request) async {
                if (request.url.path.endsWith('/refresh')) {
                  refreshes++;
                  return http.Response(
                    jsonEncode({
                      'token': 'new-token',
                      'refreshToken': 'new-refresh',
                      'user': {'id': 'u', 'role': 'creator'},
                    }),
                    200,
                  );
                }
                if (request.headers['Authorization'] == 'Bearer old-token') {
                  return http.Response('{"code":"sessionExpired"}', 401);
                }
                expect(request.headers['Authorization'], 'Bearer new-token');
                return http.Response('{"id":"u","role":"creator"}', 200);
              }),
            )
            ..token = 'old-token'
            ..refreshToken = 'old-refresh';
      expect((await client.me())['id'], 'u');
      expect(refreshes, 1);
      expect(client.refreshToken, 'new-refresh');
      client.close();
    },
  );
  test(
    'offline edits and durable outbox survive a new repository instance then sync',
    () async {
      final disk = MemoryDisk();
      final remote = Remote();
      final first = OfflineAssetRepository(
        remote,
        disk,
        ownerId: const UserId('owner'),
      );
      await first.initialize();
      await first.loadAssets();
      first.online = false;
      await first.updateAsset(
        remote.record.copyWith(title: 'Izmena bez mreže', favorite: true),
        remote.record.revision,
      );
      expect(first.pendingCount, 1);
      expect(remote.record.favorite, isFalse);
      final restarted = OfflineAssetRepository(
        remote,
        disk,
        ownerId: const UserId('owner'),
      );
      await restarted.initialize();
      expect(restarted.pendingCount, 1);
      expect((await restarted.loadAssets()).single.title, 'Izmena bez mreže');
      expect(await restarted.sync(), 1);
      expect(remote.record.favorite, isTrue);
      expect(restarted.pendingCount, 0);
      expect(remote.applied.length, 1);
    },
  );
  test(
    'new browser revision produces persistent conflict and explicit reapply',
    () async {
      final disk = MemoryDisk();
      final remote = Remote();
      final offline = OfflineAssetRepository(
        remote,
        disk,
        ownerId: const UserId('owner'),
      );
      await offline.initialize();
      await offline.loadAssets();
      offline.online = false;
      await offline.updateAsset(
        remote.record.copyWith(title: 'Telefon'),
        remote.record.revision,
      );
      remote.record = remote.record.copyWith(title: 'Pregledač', revision: 2);
      offline.online = true;
      expect(await offline.sync(), 0);
      expect(offline.conflicts.single.server.title, 'Pregledač');
      expect((await offline.loadAssets()).single.title, 'Telefon');
      final restarted = OfflineAssetRepository(
        remote,
        disk,
        ownerId: const UserId('owner'),
      );
      await restarted.initialize();
      expect(restarted.conflicts.length, 1);
      await restarted.resolveConflict(remote.record.id, keepLocal: true);
      expect(await restarted.sync(), 1);
      expect(remote.record.title, 'Telefon');
      expect(remote.record.revision, 3);
    },
  );
  test(
    'discarding a conflict keeps server changes and user cache is isolated',
    () async {
      final disk = MemoryDisk();
      final remote = Remote();
      final offline = OfflineAssetRepository(
        remote,
        disk,
        ownerId: const UserId('owner'),
      );
      await offline.loadAssets();
      offline.online = false;
      await offline.updateAsset(remote.record.copyWith(title: 'Telefon'), 1);
      remote.record = remote.record.copyWith(title: 'Pregledač', revision: 2);
      offline.online = true;
      await offline.sync();
      await offline.resolveConflict(remote.record.id, keepLocal: false);
      expect(offline.pendingCount, 0);
      expect((await offline.loadAssets()).single.title, 'Pregledač');
      final stranger = OfflineAssetRepository(
        remote,
        disk,
        ownerId: const UserId('other'),
      )..online = false;
      await stranger.initialize();
      expect(await stranger.loadAssets(), isEmpty);
    },
  );
  test('generation is explicitly unavailable offline', () async {
    final remote = Remote();
    final offline = OfflineAssetRepository(
      remote,
      MemoryDisk(),
      ownerId: const UserId('owner'),
    )..online = false;
    await expectLater(
      offline.transitionAsset(
        remote.record.id,
        AssetLifecycle.queued,
        baseRevision: 1,
      ),
      throwsA(
        isA<DomainException>().having(
          (e) => e.error.code,
          'code',
          ErrorCode.unavailable,
        ),
      ),
    );
  });
  test(
    'HTTP client transmits session/revision and maps quota errors',
    () async {
      final mock = MockClient((request) async {
        if (request.url.path.endsWith('/login')) {
          return http.Response(
            jsonEncode({
              'token': 'session',
              'user': {'id': 'a', 'role': 'creator'},
            }),
            200,
          );
        }
        expect(request.headers['Authorization'], 'Bearer session');
        expect(request.headers['If-Match'], '7');
        expect(request.headers['Idempotency-Key'], 'stable');
        return http.Response(
          jsonEncode({'code': 'DAILY_GENERATION_QUOTA_EXCEEDED'}),
          429,
        );
      });
      final client = HedrionApiClient('http://localhost:8080', client: mock);
      await client.login('a@b.test', 'long-password');
      await expectLater(
        client.generate(
          const AssetId('asset'),
          baseRevision: 7,
          idempotencyKey: 'stable',
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.error.code,
            'code',
            ErrorCode.dailyGenerationQuotaExceeded,
          ),
        ),
      );
      client.close();
    },
  );
}
