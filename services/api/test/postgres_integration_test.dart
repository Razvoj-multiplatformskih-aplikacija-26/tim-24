import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:hedrion_api/hedrion_api.dart';
import 'package:image/image.dart' as image;
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';
import 'security_test.dart' show makeGlb;

void main() {
  final url = Platform.environment['TEST_DATABASE_URL'];
  group('real PostgreSQL authoritative integration', () {
    late Database db;
    late HedrionService service;
    late Connection admin;
    late Directory objects;
    late JobScheduler scheduler;
    late HttpApi api;
    final schema = 'hedrion_test_${DateTime.now().microsecondsSinceEpoch}';
    var current = DateTime.utc(2026, 10, 21, 12);
    final a = Identity('a', 'creator', 'Kreator A', 'a@example.test'),
        b = Identity('b', 'creator', 'Kreator B', 'b@example.test'),
        moderator =
            Identity('moderator', 'moderator', 'Moderator', 'm@example.test');
    setUpAll(() async {
      admin = await Connection.openFromUrl(url!);
      await admin.execute('CREATE SCHEMA $schema');
      await admin.execute('SET search_path TO $schema');
      final localMigration = File('infrastructure/migrations/001_initial.sql');
      final migration = await localMigration.exists()
          ? localMigration
          : File('../../infrastructure/migrations/001_initial.sql');
      for (final statement in (await migration.readAsString()).split(';')) {
        if (statement.trim().isNotEmpty) await admin.execute(statement);
      }
      db = Database(Pool.withUrl(url), schema: schema);
      objects =
          await Directory.systemTemp.createTemp('hedrion-api-integration-');
      service = HedrionService(db, objects.path, clock: () => current);
      scheduler = JobScheduler(service,
          workerUrl: 'http://127.0.0.1:1',
          workerSecret: 'test-worker-secret-at-least-32-characters');
      api = HttpApi(service, scheduler,
          origins: ['https://studio.example.test'],
          workerSecret: 'test-worker-secret-at-least-32-characters');
    });
    tearDownAll(() async {
      await db.close();
      await admin.execute('SET search_path TO public');
      await admin.execute('DROP SCHEMA $schema CASCADE');
      await admin.close();
      await objects.delete(recursive: true);
    });
    setUp(() async {
      current = DateTime.utc(2026, 10, 21, 12);
      await db.transaction((tx) async {
        await tx.query('TRUNCATE users CASCADE');
        await tx.query('TRUNCATE daily_usage CASCADE');
        await tx
            .query('UPDATE storage_usage SET stored_bytes=0,reserved_bytes=0');
        for (final person in [a, b, moderator]) {
          await tx.query(
              'INSERT INTO users(id,email,password_hash,display_name,role) VALUES(@id,@email,\'test-no-login\',@name,@role)',
              {
                'id': person.id,
                'email': person.email,
                'name': person.displayName,
                'role': person.role
              });
        }
      });
      await for (final file in objects.list()) {
        if (file is File) await file.delete();
      }
    });
    Future<Json> draft(Identity owner, {String title = 'Kameni sanduk'}) =>
        service.createAsset(owner, {'title': title, 'category': 'props'});
    Future<Json> ready(Identity owner) async {
      final asset = await draft(owner);
      return db.transaction((tx) async {
        final file = await service.persistFile(tx, owner.id,
            asset['id'] as String, 'model', makeGlb(), 'model/gltf-binary');
        final preview = await service.persistFile(
            tx,
            owner.id,
            asset['id'] as String,
            'preview',
            image.encodePng(image.Image(width: 2, height: 2)),
            'image/png');
        asset['outputFileId'] = file['id'];
        asset['previewFileId'] = preview['id'];
        asset['lifecycle'] = 'ready';
        await service.saveAsset(tx, asset);
        return asset;
      });
    }

    Future<void> admissions(int count) async {
      final asset = await draft(a);
      await db.transaction((tx) async {
        for (var i = 0; i < count; i++) {
          final owner = i < 12 ? 'a' : 'b';
          await tx.query(
              "INSERT INTO generation_jobs(id,asset_id,owner_id,status,accepted_at,data,idempotency_key) VALUES(@id,@asset,@owner,'succeeded',@now,'{}'::jsonb,@key)",
              {
                'id': 'seed-$i',
                'asset': asset['id'],
                'owner': owner,
                'now': current,
                'key': 'seed-key-$i'
              });
        }
        await tx.query(
            'INSERT INTO daily_usage(day,accepted_generations) VALUES(@day::date,@count)',
            {'day': service.day, 'count': count});
      });
    }

    Future<Json> generate(Identity owner, Json asset, String key) =>
        service.generate(
            owner,
            asset['id'] as String,
            {
              'inputType': 'text_to_3d',
              'sourcePrompt': 'Kameni sanduk',
              'baseRevision': asset['revision']
            },
            key);
    Future<String> sessionFor(Identity owner) async {
      final token = 'test-access-token-${owner.id}';
      await db.transaction((tx) async {
        await tx.query(
            'INSERT INTO sessions(token_hash,refresh_hash,user_id,expires_at,refresh_expires_at) VALUES(@token,@refresh,@owner,@expires,@expires)',
            {
              'token': digest(token),
              'refresh': digest('refresh-${owner.id}'),
              'owner': owner.id,
              'expires': current.add(const Duration(hours: 1))
            });
      });
      return token;
    }

    test('ownership, roles and revision conflicts are authoritative', () async {
      final asset = await draft(a);
      await expectLater(service.getAsset(b, asset['id'] as String),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)));
      await expectLater(service.moderation(a),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 403)));
      final updated = await service.updateAsset(
          a, asset['id'] as String, {'title': 'Novi sanduk', 'baseRevision': 1},
          key: 'rename-operation-1');
      expect(updated['revision'], 2);
      await expectLater(
          service.updateAsset(a, asset['id'] as String,
              {'title': 'Stara izmena', 'baseRevision': 1}),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)));
      expect((await service.getAsset(a, asset['id'] as String))['title'],
          'Novi sanduk');
    });
    test(
        'private and moderation pagination expose every record and audit detail',
        () async {
      final template = await ready(a);
      await db.transaction((tx) async {
        for (var i = 0; i < 101; i++) {
          final suffix = i.toString().padLeft(3, '0');
          final data = {
            ...template,
            'id': 'paged-$suffix',
            'lifecycle': 'pendingReview'
          };
          await tx.query(
              'INSERT INTO assets(id,owner_id,data) VALUES(@id,@owner,@data::jsonb)',
              {'id': data['id'], 'owner': a.id, 'data': jsonEncode(data)});
          await tx.query(
              "INSERT INTO publication_submissions(id,asset_id,submitter_id,status,snapshot,slug,submitted_at) VALUES(@id,@asset,@owner,'pending_review',@snapshot::jsonb,@slug,@now)",
              {
                'id': 'submission-$suffix',
                'asset': data['id'],
                'owner': a.id,
                'snapshot': jsonEncode(data),
                'slug': 'paged-$suffix',
                'now': current
              });
        }
      });
      final creatorToken = await sessionFor(a),
          moderatorToken = await sessionFor(moderator);
      Future<Json> get(String path, String token) async {
        final response = await api.handler(Request(
            'GET', Uri.parse('http://localhost$path'),
            headers: {'authorization': 'Bearer $token'}));
        expect(response.statusCode, 200);
        return jsonDecode(await response.readAsString()) as Json;
      }

      final privateFirst = await get('/api/v1/assets', creatorToken);
      expect(privateFirst['assets'], hasLength(100));
      final privateLast = await get(
          '/api/v1/assets?cursor=${privateFirst['nextCursor']}', creatorToken);
      expect(privateLast['assets'], hasLength(2));
      expect(privateLast['nextCursor'], isNull);
      final first = await service.moderation(moderator);
      expect(first['assets'], hasLength(100));
      expect(first['nextCursor'], 'paged-099');
      final second = await get(
          '/api/v1/moderation/submissions?cursor=${first['nextCursor']}',
          moderatorToken);
      expect((second['submissions'] as List).single['id'], 'submission-100');
      expect(second['nextCursor'], isNull);
      await service.moderate(moderator, 'submission-100', true,
          {'baseRevision': 1}, 'approve-last-page');
      final detail = await get(
          '/api/v1/moderation/submissions/submission-100', moderatorToken);
      expect(detail['submitterName'], 'Kreator A');
      expect(detail['reviewedAt'], current.toIso8601String());
      expect((detail['audit'] as List).single['actorName'], 'Moderator');
      expect((detail['audit'] as List).single['action'], 'approved');
      final stats = (await service.moderation(moderator))['stats'] as Json;
      expect(stats['reviewedToday'], 1);
      expect(stats['approvalRate'], 1.0);
      expect(stats['activeJobs'], 0);
      final denied = await api.handler(Request(
          'GET',
          Uri.parse(
              'http://localhost/api/v1/moderation/submissions/submission-100'),
          headers: {'authorization': 'Bearer $creatorToken'}));
      expect(denied.statusCode, 403);
    });
    test(
        'moderator retains reviewed snapshot preview but cannot access private source',
        () async {
      for (final approve in [true, false]) {
        final asset = await ready(a);
        final result = await service.submit(
            a,
            asset['id'] as String,
            {
              'baseRevision': asset['revision'],
              'license': 'ccBy',
              'allowDownload': false,
              'confirmRights': true
            },
            'reviewed-snapshot-$approve');
        final submission = result['submission'] as Json;
        await service.moderate(
            moderator,
            submission['id'] as String,
            approve,
            {'baseRevision': 1, 'reason': 'Dopunite opis modela.'},
            'snapshot-decision-$approve');
        final preview =
            await service.fileInfo(moderator, asset['previewFileId'] as String);
        expect(preview['kind'], 'preview');
        final privateFile = await db.transaction((tx) => service.persistFile(
            tx,
            a.id,
            asset['id'] as String,
            'source',
            Uint8List.fromList([1, 2, 3]),
            'image/png'));
        await expectLater(
            service.fileInfo(moderator, privateFile['id'] as String),
            throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)));
      }
      final neverSubmitted = await ready(a);
      await expectLater(
          service.fileInfo(
              moderator, neverSubmitted['previewFileId'] as String),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)));
    });
    test('chunked uploads are rejected without consuming an unreserved body',
        () async {
      final asset = await draft(a), token = await sessionFor(a);
      var read = false;
      Stream<List<int>> unboundedBody() async* {
        read = true;
        yield Uint8List(1000);
      }

      final result = await api.handler(Request('PUT',
          Uri.parse('http://localhost/api/v1/assets/${asset['id']}/source'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'image/png',
            'x-file-length': '1'
          },
          body: unboundedBody()));
      expect(result.statusCode, 411);
      expect(read, isFalse);
      expect(await db.transaction((tx) => tx.one('SELECT * FROM daily_usage')),
          isNull);
    });
    test('idempotent offline replay returns original result after later edits',
        () async {
      final asset = await draft(a),
          input = {'title': 'Prva promena', 'baseRevision': 1};
      final first = await service.updateAsset(a, asset['id'] as String, input,
          key: 'offline-command-1');
      await service.updateAsset(a, asset['id'] as String,
          {'title': 'Novija promena', 'baseRevision': 2});
      final replay = await service.updateAsset(a, asset['id'] as String, input,
          key: 'offline-command-1');
      expect(replay, first);
      expect((await service.getAsset(a, asset['id'] as String))['title'],
          'Novija promena');
    });
    test('20 shared admissions reject a new write and preserve draft',
        () async {
      await admissions(20);
      final asset = await draft(b);
      await expectLater(
          generate(b, asset, 'quota-rejection-key'),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'dailyGenerationQuotaExceeded')));
      expect((await service.getAsset(b, asset['id'] as String))['lifecycle'],
          'draft');
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT count(*) AS count FROM generation_jobs'))!['count']),
          20);
      current = DateTime.utc(2026, 10, 22);
      expect((await generate(b, asset, 'next-day-new-key'))['job'], isNotNull);
    });
    test(
        'two concurrent final-slot claims admit exactly one job; replay costs nothing',
        () async {
      await admissions(19);
      final assetA = await draft(a), assetB = await draft(b);
      final results = await Future.wait([
        generate(a, assetA, 'concurrent-a-key')
            .then<Object>((v) => v)
            .catchError((Object e) => e),
        generate(b, assetB, 'concurrent-b-key')
            .then<Object>((v) => v)
            .catchError((Object e) => e)
      ]);
      expect(results.whereType<Json>(), hasLength(1));
      expect(results.whereType<ApiFailure>(), hasLength(1));
      final winner = results.firstWhere((r) => r is Json) as Json;
      final owner = (winner['asset'] as Json)['ownerId'] == 'a' ? a : b;
      final original = owner.id == 'a' ? assetA : assetB;
      final key = owner.id == 'a' ? 'concurrent-a-key' : 'concurrent-b-key';
      expect(await generate(owner, original, key), winner);
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT count(*) AS count FROM generation_jobs'))!['count']),
          20);
    });
    test(
        'transfer reservations prevent concurrent oversubscription and release unused bytes',
        () async {
      await db.transaction((tx) async {
        await tx.query(
            'INSERT INTO daily_usage(day,transferred_bytes) VALUES(@day::date,950000000)',
            {'day': service.day});
      });
      await expectLater(
          db.transaction((tx) => service.reserveTransfer(tx, 100000000)),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'dailyTransferQuotaExceeded')));
      final reservation =
          await db.transaction((tx) => service.reserveTransfer(tx, 50000000));
      await expectLater(db.transaction((tx) => service.reserveTransfer(tx, 1)),
          throwsA(isA<ApiFailure>()));
      await service.finishTransfer(reservation, 10000000);
      await service.finishTransfer(reservation, 10000000);
      final usage =
          await db.transaction((tx) => tx.one('SELECT * FROM daily_usage'));
      expect(usage!['transferred_bytes'], 960000000);
      expect(usage['reserved_transfer_bytes'], 0);
    });
    test('storage boundary rollback never makes unpersisted output ready',
        () async {
      await db.transaction((tx) async {
        await tx.query('UPDATE storage_usage SET stored_bytes=9900000000');
      });
      await expectLater(
          db.transaction((tx) => service.reserveStorage(tx, 200000000)),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'storageQuotaExceeded')));
      expect(
          await db.transaction((tx) async => (await tx.one(
              'SELECT reserved_bytes FROM storage_usage'))!['reserved_bytes']),
          0);
    });
    test(
        'moderation races resolve once and public metadata remains an immutable snapshot',
        () async {
      final asset = await ready(a);
      final submitted = await service.submit(
          a,
          asset['id'] as String,
          {
            'baseRevision': 1,
            'confirmRights': true,
            'license': 'ccBy',
            'allowDownload': true
          },
          'submit-operation-1');
      final submission = submitted['submission'] as Json;
      await service.updateAsset(a, asset['id'] as String,
          {'title': 'Privatni noviji naziv', 'baseRevision': 2});
      final attempts = await Future.wait([
        service
            .moderate(moderator, submission['id'] as String, true,
                {'baseRevision': 1}, 'approve-operation-1')
            .then<Object>((v) => v)
            .catchError((Object e) => e),
        service
            .moderate(
                moderator,
                submission['id'] as String,
                false,
                {'baseRevision': 1, 'reason': 'Nedostaje opis'},
                'reject-operation-2')
            .then<Object>((v) => v)
            .catchError((Object e) => e)
      ]);
      expect(attempts.whereType<Json>(), hasLength(1));
      expect(attempts.whereType<ApiFailure>(), hasLength(1));
      final public = await service.publicAssets();
      if (public.isNotEmpty) {
        expect(public.single['title'], asset['title']);
        expect(public.single.containsKey('ownerId'), isFalse);
        expect(public.single.containsKey('outputFileId'), isFalse);
      }
      expect(
          await db.transaction((tx) async => (await tx.one(
              'SELECT count(*) AS count FROM moderation_events'))!['count']),
          1);
    });
    test(
        'rejected publication retains generated private output and can be revised',
        () async {
      final asset = await ready(a);
      final submitted = await service.submit(
          a,
          asset['id'] as String,
          {'baseRevision': 1, 'confirmRights': true, 'license': 'ccBy'},
          'submit-reject-key');
      final id = (submitted['submission'] as Json)['id'] as String;
      await service.moderate(moderator, id, false, {'reason': 'Dopunite opis'},
          'reject-reason-key');
      final rejected = await service.getAsset(a, asset['id'] as String);
      expect(rejected['outputFileId'], asset['outputFileId']);
      expect(await service.publicAssets(), isEmpty);
      expect(
          (await service.transition(a, asset['id'] as String, {
            'target': 'ready',
            'baseRevision': rejected['revision']
          }))['lifecycle'],
          'ready');
    });
    test('scheduler globally claims no more than two jobs', () async {
      final first = await generate(a, await draft(a), 'scheduler-job-a'),
          second = await generate(b, await draft(b), 'scheduler-job-b');
      expect(first, isNotNull);
      expect(second, isNotNull);
      final claims = await Future.wait(
          [scheduler.claim(), scheduler.claim(), scheduler.claim()]);
      expect(claims.whereType<Json>(), hasLength(2));
      expect(
          await db.transaction((tx) async => (await tx.one(
                  "SELECT count(*) AS count FROM generation_jobs WHERE status='running'"))![
              'count']),
          2);
    });
    test('malformed worker output fails before a ready result is visible',
        () async {
      final generated =
          await generate(a, await draft(a), 'malformed-worker-key');
      final job = (generated['job'] as Json)['id'] as String;
      await scheduler.claim();
      await expectLater(
          scheduler.complete(job, {
            'jobId': job,
            'modelBase64': base64Encode([1, 2, 3]),
            'previewBase64': base64Encode([1, 2, 3])
          }),
          throwsA(isA<ApiFailure>()));
      expect(
          (await service.getAsset(
              a, (generated['asset'] as Json)['id'] as String))['outputFileId'],
          isNull);
    });
    test('HTTP auth, approved CORS and callback signature protection',
        () async {
      expect(
          (await api.handler(
                  Request('GET', Uri.parse('http://localhost/api/v1/assets'))))
              .statusCode,
          401);
      expect(
          (await api.handler(Request(
                  'GET', Uri.parse('http://localhost/health'),
                  headers: {'origin': 'https://untrusted.example'})))
              .statusCode,
          403);
      expect(
          (await api.handler(Request(
                  'OPTIONS', Uri.parse('http://localhost/api/v1/assets'),
                  headers: {'origin': 'https://studio.example.test'})))
              .headers['access-control-allow-origin'],
          'https://studio.example.test');
      expect(
          (await api.handler(Request(
                  'POST',
                  Uri.parse(
                      'http://localhost/internal/v1/generations/fake/callback'),
                  body: '{}')))
              .statusCode,
          401);
    });
    test('real raw uploads and ranged downloads account exact payloads',
        () async {
      final asset = await draft(a),
          token = await sessionFor(a),
          png = image.encodePng(image.Image(width: 2, height: 2));
      final uploaded = await api.handler(Request('PUT',
          Uri.parse('http://localhost/api/v1/assets/${asset['id']}/source'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'image/png',
            'x-file-length': '${png.length}'
          },
          body: png));
      expect(uploaded.statusCode, 201);
      final body = jsonMap(jsonDecode(await uploaded.readAsString())),
          file = body['file'] as Json;
      final download = await api.handler(Request(
          'GET', Uri.parse('http://localhost/api/v1/files/${file['id']}'),
          headers: {'authorization': 'Bearer $token', 'range': 'bytes=2-5'}));
      expect(download.statusCode, 206);
      expect(download.headers['content-range'], 'bytes 2-5/${png.length}');
      final bytes = await download.read().expand((v) => v).toList();
      expect(bytes, png.sublist(2, 6));
      final usage =
          await db.transaction((tx) => tx.one('SELECT * FROM daily_usage'));
      expect(usage!['transferred_bytes'], png.length + 4);
      expect(usage['reserved_transfer_bytes'], 0);
    });
    test('partial upload preserves received-byte charge and releases remainder',
        () async {
      final asset = await draft(a), token = await sessionFor(a);
      final uploaded = await api.handler(Request('PUT',
          Uri.parse('http://localhost/api/v1/assets/${asset['id']}/source'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'image/png',
            'content-length': '10',
            'x-file-length': '10'
          },
          // A transport stream can terminate before its declared length. A
          // byte-list body would make Shelf normalize Content-Length to 3 and
          // test header rejection instead of an interrupted upload.
          body: Stream<List<int>>.value([1, 2, 3])));
      expect(uploaded.statusCode, 422);
      final usage =
          await db.transaction((tx) => tx.one('SELECT * FROM daily_usage'));
      expect(usage!['transferred_bytes'], 3);
      expect(usage['reserved_transfer_bytes'], 0);
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT count(*) AS count FROM stored_files'))!['count']),
          0);
    });
    test(
        'signed callback persists validated GLB before ready and rejects nonce replay',
        () async {
      final generated =
          await generate(a, await draft(a), 'signed-worker-result');
      final job = (generated['job'] as Json)['id'] as String;
      await scheduler.claim();
      final payload = jsonEncode({
            'jobId': job,
            'provider': 'fake',
            'modelBase64': base64Encode(makeGlb()),
            'previewBase64':
                base64Encode(image.encodePng(image.Image(width: 2, height: 2))),
            'metadata': {'triangleCount': 0},
            'metrics': {'output_size_bytes': makeGlb().length}
          }),
          timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          nonce = 'valid-callback-nonce';
      const secret = 'test-worker-secret-at-least-32-characters';
      final headers = {
        'authorization': 'Bearer $secret',
        'content-type': 'application/json',
        'x-hedrion-timestamp': timestamp,
        'x-hedrion-nonce': nonce,
        'x-hedrion-signature':
            workerSignature(secret, timestamp, nonce, payload)
      };
      final first = await api.handler(Request('POST',
          Uri.parse('http://localhost/internal/v1/generations/$job/callback'),
          headers: headers, body: payload));
      expect(first.statusCode, 200);
      final asset = await service.getAsset(
          a, (generated['asset'] as Json)['id'] as String);
      expect(asset['lifecycle'], 'ready');
      expect(asset['outputFileId'], isNotNull);
      expect(await service.job(a, job), containsPair('status', 'succeeded'));
      final replay = await api.handler(Request('POST',
          Uri.parse('http://localhost/internal/v1/generations/$job/callback'),
          headers: headers, body: payload));
      expect(replay.statusCode, 409);
    });
    test('anonymous approved downloads share global quota', () async {
      final asset = await ready(a),
          submitted = await service.submit(
              a,
              asset['id'] as String,
              {
                'baseRevision': 1,
                'confirmRights': true,
                'license': 'ccBy',
                'allowDownload': true
              },
              'public-transfer-submit');
      final submission = submitted['submission'] as Json;
      await service.moderate(moderator, submission['id'] as String, true,
          {'baseRevision': 1}, 'public-transfer-approve');
      final download = await api.handler(Request(
          'GET',
          Uri.parse(
              'http://localhost/api/v1/public/assets/${submission['slug']}/files/model')));
      expect(download.statusCode, 200);
      expect(await download.read().expand((v) => v).toList(), makeGlb());
      expect(
          await db.transaction((tx) async =>
              (await tx.one('SELECT transferred_bytes FROM daily_usage'))![
                  'transferred_bytes']),
          makeGlb().length);
      await db.transaction((tx) async {
        await tx.query('UPDATE daily_usage SET transferred_bytes=1000000000');
      });
      final exhausted = await api.handler(Request(
          'GET',
          Uri.parse(
              'http://localhost/api/v1/public/assets/${submission['slug']}/files/model')));
      expect(exhausted.statusCode, 429);
    });
    test(
        'browser refresh uses HttpOnly strict cookies, rotates, and rejects missing origin',
        () async {
      const origin = 'https://studio.example.test';
      final registered = await api.handler(
          Request('POST', Uri.parse('http://localhost/api/v1/auth/register'),
              headers: {'origin': origin, 'content-type': 'application/json'},
              body: jsonEncode({
                'email': 'browser@example.test',
                'displayName': 'Browser kreator',
                'password': 'a-long-browser-password',
                'browserSession': true,
                'role': 'moderator'
              })));
      expect(registered.statusCode, 201);
      expect(registered.headers['access-control-allow-credentials'], 'true');
      final session = jsonMap(jsonDecode(await registered.readAsString()));
      expect(session.containsKey('refreshToken'), isFalse);
      expect((session['user'] as Json)['role'], 'creator');
      final cookie = registered.headers['set-cookie']!;
      expect(cookie, contains('HttpOnly'));
      expect(cookie, contains('SameSite=Strict'));
      expect(cookie, contains('Path=/api/v1/auth'));
      expect(cookie, contains('Secure'));
      final missingOrigin = await api.handler(Request(
          'POST', Uri.parse('http://localhost/api/v1/auth/refresh'),
          headers: {'cookie': cookie.split(';').first},
          body: '{"browserSession":true}'));
      expect(missingOrigin.statusCode, 403);
      final refreshed = await api.handler(Request(
          'POST', Uri.parse('http://localhost/api/v1/auth/refresh'),
          headers: {'origin': origin, 'cookie': cookie.split(';').first},
          body: '{"browserSession":true}'));
      expect(refreshed.statusCode, 200);
      expect(refreshed.headers['set-cookie'], isNot(cookie));
      final rotated = jsonMap(jsonDecode(await refreshed.readAsString()));
      expect(rotated.containsKey('refreshToken'), isFalse);
      expect(
          (await api.handler(Request(
                  'POST', Uri.parse('http://localhost/api/v1/auth/refresh'),
                  headers: {
                    'origin': origin,
                    'cookie': cookie.split(';').first
                  },
                  body: '{"browserSession":true}')))
              .statusCode,
          401);
      final loggedOut = await api.handler(Request(
          'POST', Uri.parse('http://localhost/api/v1/auth/logout'), headers: {
        'origin': origin,
        'authorization': 'Bearer ${rotated['token']}'
      }));
      expect(loggedOut.statusCode, 200);
      expect(loggedOut.headers['set-cookie'], contains('Max-Age=0'));
    });
    test(
        'delete commits tombstone before file cleanup and resumes after a partial failure',
        () async {
      final asset = await ready(a);
      var calls = 0;
      final failingService = HedrionService(db, objects.path,
          clock: () => current,
          fileRemover: (file) async {
            calls++;
            if (calls == 2) {
              throw const FileSystemException('injected cleanup failure');
            }
            await file.delete();
          });
      final deleted = await failingService
          .deleteAsset(a, asset['id'] as String, {'baseRevision': 1});
      expect(deleted['deleted'], isTrue);
      expect(deleted['cleanupPending'], isTrue);
      await expectLater(service.getAsset(a, asset['id'] as String),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)));
      final retained = await db.transaction((tx) => tx.query(
          'SELECT byte_length FROM stored_files WHERE deleted_at IS NULL'));
      expect(retained, hasLength(1));
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT stored_bytes FROM storage_usage'))!['stored_bytes']),
          retained.single['byte_length']);
      await service.reconcileStorage();
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT stored_bytes FROM storage_usage'))!['stored_bytes']),
          0);
      expect(
          (await service.deleteAsset(
              a, asset['id'] as String, {'baseRevision': 1}))['cleanupPending'],
          isFalse);
    });
    test(
        'mismatched HTTP upload length is rejected before reserving or reading',
        () async {
      final asset = await draft(a), token = await sessionFor(a);
      final uploaded = await api.handler(Request('PUT',
          Uri.parse('http://localhost/api/v1/assets/${asset['id']}/source'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'image/png',
            'x-file-length': '10'
          },
          body: Uint8List(12)));
      expect(uploaded.statusCode, 422);
      final usage =
          await db.transaction((tx) => tx.one('SELECT * FROM daily_usage'));
      expect(usage, isNull);
    });
    test('upload crossing UTC midnight obtains fresh quota before continuing',
        () async {
      final asset = await draft(a),
          token = await sessionFor(a),
          png = image.encodePng(image.Image(width: 2, height: 2));
      final split = png.length ~/ 2;
      Stream<List<int>> source() async* {
        yield png.sublist(0, split);
        current = DateTime.utc(2026, 10, 22);
        yield png.sublist(split);
      }

      final uploaded = await api.handler(Request('PUT',
          Uri.parse('http://localhost/api/v1/assets/${asset['id']}/source'),
          headers: {
            'authorization': 'Bearer $token',
            'content-type': 'image/png',
            'content-length': '${png.length}',
            'x-file-length': '${png.length}'
          },
          body: source()));
      expect(uploaded.statusCode, 201);
      final usage = await db.transaction((tx) => tx.query(
          'SELECT transferred_bytes,reserved_transfer_bytes FROM daily_usage ORDER BY day'));
      expect(usage.map((r) => r['transferred_bytes']).toList(),
          [split, png.length - split]);
      expect(usage.every((r) => r['reserved_transfer_bytes'] == 0), isTrue);
    });
    test(
        'real provider rejects unsupported text before admission and history is owner-only',
        () async {
      final asset = await draft(a),
          real = HedrionService(db, objects.path,
              clock: () => current, generationProvider: 'pixal3d');
      await expectLater(
          real.generate(
              a,
              asset['id'] as String,
              {
                'baseRevision': 1,
                'inputType': 'text_to_3d',
                'sourcePrompt': 'Sanduk'
              },
              'real-text-unsupported'),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'unsupportedInput')));
      expect(await service.jobs(a, asset['id'] as String), isEmpty);
      await expectLater(service.jobs(b, asset['id'] as String),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 404)));
      expect(
          (await api.handler(
                  Request('GET', Uri.parse('http://localhost/unknown-route'))))
              .statusCode,
          404);
    });
    test(
        'studio and backoffice cookies preserve independent identities and logout scopes',
        () async {
      await sessionFor(a);
      await sessionFor(moderator);
      const origin = 'https://studio.example.test';
      const cookies =
          'hedrion_refresh_studio=refresh-a; hedrion_refresh_backoffice=refresh-moderator';
      final studio = await api.handler(Request(
          'POST', Uri.parse('http://localhost/api/v1/auth/refresh'),
          headers: {'origin': origin, 'cookie': cookies},
          body: '{"browserSession":true,"browserSessionScope":"studio"}'));
      expect(studio.statusCode, 200);
      expect(
          studio.headers['set-cookie'], startsWith('hedrion_refresh_studio='));
      final studioSession = jsonMap(jsonDecode(await studio.readAsString()));
      expect((studioSession['user'] as Json)['id'], 'a');
      final logout = await api.handler(Request(
          'POST', Uri.parse('http://localhost/api/v1/auth/logout'),
          headers: {
            'origin': origin,
            'authorization': 'Bearer ${studioSession['token']}'
          },
          body: '{"browserSession":true,"browserSessionScope":"studio"}'));
      expect(
          logout.headers['set-cookie'], startsWith('hedrion_refresh_studio='));
      final office = await api.handler(Request(
          'POST', Uri.parse('http://localhost/api/v1/auth/refresh'),
          headers: {'origin': origin, 'cookie': cookies},
          body: '{"browserSession":true,"browserSessionScope":"backoffice"}'));
      expect(office.statusCode, 200);
      expect(office.headers['set-cookie'],
          startsWith('hedrion_refresh_backoffice='));
      final officeSession = jsonMap(jsonDecode(await office.readAsString()));
      expect((officeSession['user'] as Json)['role'], 'moderator');
      expect(
          (await api.handler(Request(
                  'POST', Uri.parse('http://localhost/api/v1/auth/refresh'),
                  headers: {'origin': origin, 'cookie': cookies},
                  body:
                      '{"browserSession":true,"browserSessionScope":"other"}')))
              .statusCode,
          422);
    });
    test('idempotent update keys cannot replay across entities', () async {
      final first = await draft(a),
          second = await draft(a),
          input = {'title': 'Isti naziv', 'baseRevision': 1};
      await service.updateAsset(a, first['id'] as String, input,
          key: 'entity-scoped-key');
      await expectLater(
          service.updateAsset(a, second['id'] as String, input,
              key: 'entity-scoped-key'),
          throwsA(isA<ApiFailure>().having((e) => e.status, 'status', 409)));
      expect(
          (await service.getAsset(a, second['id'] as String))['revision'], 1);
    });
    test(
        'failed rollback cleanup retains orphan bytes across restart reconciliation',
        () async {
      final asset = await draft(a),
          model = makeGlb(),
          preview = image.encodePng(image.Image(width: 2, height: 2));
      final expected = model.length + preview.length;
      final failingService = HedrionService(db, objects.path,
          clock: () => current,
          fileRemover: (_) =>
              throw StateError('Injected unexpected cleanup adapter error'));
      await expectLater(db.transaction((tx) async {
        final output = await failingService.persistFile(tx, a.id,
            asset['id'] as String, 'model', model, 'model/gltf-binary');
        await failingService.persistFile(
            tx, a.id, asset['id'] as String, 'preview', preview, 'image/png');
        final changed = {
          ...asset,
          'lifecycle': 'ready',
          'outputFileId': output['id'],
          'revision': 2
        };
        await failingService.saveAsset(tx, changed);
        throw const ApiFailure(422, 'injectedFinalizationFailure',
            'Test failure after persistent writes.');
      }),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'injectedFinalizationFailure')));
      final after = await service.getAsset(a, asset['id'] as String);
      expect(after['lifecycle'], 'draft');
      expect(after['outputFileId'], isNull);
      expect(after['revision'], 1);
      final retained =
          await db.transaction((tx) => tx.one('SELECT * FROM storage_usage'));
      expect(retained!['stored_bytes'], expected);
      expect(retained['reserved_bytes'], 0);
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT count(*) AS count FROM stored_files'))!['count']),
          0);
      expect(await objects.list().where((entry) => entry is File).length, 2);
      await expectLater(
          db.transaction(
              (tx) => service.reserveStorage(tx, 10000000000 - expected + 1)),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'storageQuotaExceeded')));
      await service.reconcileStorage();
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT stored_bytes FROM storage_usage'))!['stored_bytes']),
          expected);
      // Unknown orphan files are intentionally retained; a confirmed physical
      // cleanup followed by reconciliation is the point at which space is free.
      await for (final file in objects.list()) {
        if (file is File) await file.delete();
      }
      await service.reconcileStorage();
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT stored_bytes FROM storage_usage'))!['stored_bytes']),
          0);
    });
    test(
        'normal rollback removes all candidates and preserves original SQL failure',
        () async {
      final asset = await draft(a), model = makeGlb();
      await expectLater(db.transaction((tx) async {
        await service.persistFile(tx, a.id, asset['id'] as String, 'model',
            model, 'model/gltf-binary');
        await tx.query(
            'INSERT INTO projects(id,owner_id,name) VALUES(\'duplicate-project\',@owner,\'Valid project\')',
            {'owner': a.id});
        await tx.query(
            'INSERT INTO projects(id,owner_id,name) VALUES(\'duplicate-project\',@owner,\'Duplicate\')',
            {'owner': a.id});
      }), throwsA(isA<ServerException>()));
      expect(await objects.list().where((entry) => entry is File).length, 0);
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT stored_bytes FROM storage_usage'))!['stored_bytes']),
          0);
      expect(
          await db.transaction((tx) async => (await tx
              .one('SELECT count(*) AS count FROM projects'))!['count']),
          0);
    });
    test(
        'expired worker lease cannot commit a result or erase original admission',
        () async {
      final generated = await generate(a, await draft(a), 'expired-lease-test'),
          job = (generated['job'] as Json)['id'] as String;
      await scheduler.claim();
      current = current.add(const Duration(minutes: 6));
      await expectLater(
          scheduler.complete(job, {
            'jobId': job,
            'modelBase64': base64Encode(makeGlb()),
            'previewBase64':
                base64Encode(image.encodePng(image.Image(width: 2, height: 2)))
          }),
          throwsA(isA<ApiFailure>()
              .having((e) => e.code, 'code', 'staleCallback')));
      await scheduler.claim();
      expect((await service.job(a, job))['status'], 'failed');
      expect((await service.job(a, job))['failureCode'], 'workerLeaseExpired');
      expect(
          (await service.getAsset(
              a, (generated['asset'] as Json)['id'] as String))['outputFileId'],
          isNull);
      expect(
          await db.transaction((tx) async =>
              (await tx.one('SELECT accepted_generations FROM daily_usage'))![
                  'accepted_generations']),
          1);
    });
  },
      skip: url == null
          ? 'Set TEST_DATABASE_URL to run isolated-schema real PostgreSQL integration tests.'
          : false,
      timeout: const Timeout(Duration(minutes: 2)));
}
