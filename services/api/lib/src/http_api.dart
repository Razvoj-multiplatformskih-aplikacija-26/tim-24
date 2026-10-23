import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'database.dart';
import 'scheduler.dart';
import 'security.dart';
import 'service.dart';

class HttpApi {
  HttpApi(this.service, this.scheduler,
      {this.origins = const [],
      required this.workerSecret,
      this.secureCookies = true}) {
    _routes();
  }
  final HedrionService service;
  final JobScheduler scheduler;
  final List<String> origins;
  final String workerSecret;
  final bool secureCookies;
  final Router router = Router();
  final Map<String, ({DateTime start, int count})> _rateLimits = {};
  Handler get handler => (request) async {
        final requestId = newId(), origin = request.headers['origin'];
        final headers = <String, String>{
          'x-request-id': requestId,
          'x-content-type-options': 'nosniff',
          'cache-control': 'no-store',
          'referrer-policy': 'no-referrer'
        };
        if (origin != null) {
          if (!origins.contains(origin)) {
            return response(
                403,
                {
                  'code': 'originDenied',
                  'message': 'Poreklo pristupa nije dozvoljeno.',
                  'requestId': requestId
                },
                headers);
          }
          headers.addAll({
            'access-control-allow-origin': origin,
            'access-control-allow-credentials': 'true',
            'vary': 'Origin',
            'access-control-allow-methods': 'GET,POST,PATCH,DELETE,PUT,OPTIONS',
            'access-control-allow-headers':
                'Authorization,Content-Type,Idempotency-Key,If-Match,X-File-Length,Range',
            'access-control-expose-headers':
                'Content-Length,Content-Range,X-Request-Id'
          });
        }
        if (request.method == 'OPTIONS') return Response(204, headers: headers);
        try {
          final path = request.url.path;
          final endpoint = path.contains('/auth/')
              ? 'auth'
              : path.contains('/public/')
                  ? 'public'
                  : path.contains('/generations')
                      ? 'generation'
                      : 'general';
          final info = request.context['shelf.io.connection_info']
              as HttpConnectionInfo?;
          _limit(
              '${info?.remoteAddress.address ?? 'local'}:$endpoint',
              endpoint == 'auth'
                  ? 30
                  : endpoint == 'generation'
                      ? 60
                      : 600);
          return (await router.call(request)).change(headers: headers);
        } on ApiFailure catch (error) {
          return response(
              error.status,
              {
                'code': error.code,
                'message': error.message,
                if (error.details != null) 'details': error.details,
                'requestId': requestId
              },
              headers);
        } on FormatException {
          return response(
              400,
              {
                'code': 'invalidJson',
                'message': 'Neispravan zahtev.',
                'requestId': requestId
              },
              headers);
        } catch (error) {
          stderr
              .writeln('API request $requestId failed (${error.runtimeType}).');
          return response(
              500,
              {
                'code': 'serverError',
                'message': 'Serverska greška. Pokušajte ponovo.',
                'requestId': requestId
              },
              headers);
        }
      };
  void _limit(String key, int max) {
    final now = DateTime.now();
    final old = _rateLimits[key];
    if (old == null || now.difference(old.start) > const Duration(minutes: 1)) {
      _rateLimits[key] = (start: now, count: 1);
    } else {
      if (old.count >= max) {
        throw const ApiFailure(
            429, 'rateLimited', 'Previše zahteva. Sačekajte minut.');
      }
      _rateLimits[key] = (start: old.start, count: old.count + 1);
    }
    if (_rateLimits.length > 10000) {
      _rateLimits.removeWhere((_, value) =>
          now.difference(value.start) > const Duration(minutes: 2));
    }
  }

  String? token(Request request) {
    final header = request.headers['authorization'];
    return header != null && header.startsWith('Bearer ')
        ? header.substring(7)
        : null;
  }

  Future<Identity> user(Request request) =>
      service.authenticate(token(request));
  String key(Request request) {
    final key = request.headers['idempotency-key'];
    if (key == null || key.length < 8 || key.length > 200) {
      throw const ApiFailure(422, 'idempotencyKeyRequired',
          'Potreban je Idempotency-Key od 8 do 200 znakova.');
    }
    return key;
  }

  Future<Json> body(Request request, {int max = 32768}) async {
    final bytes = BytesBuilder();
    await for (final chunk in request.read()) {
      bytes.add(chunk);
      if (bytes.length > max) {
        throw const ApiFailure(413, 'requestTooLarge', 'Zahtev je prevelik.');
      }
    }
    if (bytes.length == 0) return {};
    final decoded = jsonDecode(utf8.decode(bytes.takeBytes()));
    if (decoded is! Map) throw const FormatException('JSON object required');
    return Map<String, dynamic>.from(decoded);
  }

  Future<Json> revisionBody(Request request) async {
    final input = await body(request);
    if (!input.containsKey('baseRevision') &&
        request.headers['if-match'] != null) {
      input['baseRevision'] =
          int.tryParse(request.headers['if-match']!.replaceAll('"', ''));
    }
    return input;
  }

  void _routes() {
    router.get(
        '/api/v1/capabilities',
        (_) => response(200, {
              'provider': service.generationProvider,
              'imageTo3d': true,
              'textTo3d': service.generationProvider == 'fake',
              'demo': service.generationProvider == 'fake'
            }));
    router.get('/health',
        (_) => response(200, {'status': 'ok', 'service': 'hedrion-api'}));
    router.post('/api/v1/auth/register', (Request r) async {
      final input = await body(r);
      _browserOrigin(r, input);
      return _authResponse(201, await service.register(input),
          browser: input['browserSession'] == true, scope: _scope(input));
    });
    router.post('/api/v1/auth/login', (Request r) async {
      final input = await body(r);
      _browserOrigin(r, input);
      return _authResponse(200, await service.login(input),
          browser: input['browserSession'] == true, scope: _scope(input));
    });
    router.post('/api/v1/auth/refresh', (Request r) async {
      final input = await body(r);
      _browserOrigin(r, input);
      if (input['browserSession'] == true) {
        final token = _refreshCookie(r, _scope(input));
        if (token == null) {
          throw const ApiFailure(401, 'invalidRefresh', 'Sesija je istekla.');
        }
        input['refreshToken'] = token;
      }
      return _authResponse(200, await service.refresh(input),
          browser: input['browserSession'] == true, scope: _scope(input));
    });
    router.post('/api/v1/auth/logout', (Request r) async {
      final input = await body(r);
      _browserOrigin(r, input);
      await user(r);
      await service.logout(token(r)!);
      return response(200, {'loggedOut': true},
          {'set-cookie': _cookie('', _scope(input), maxAge: 0)});
    });
    router.get('/api/v1/me',
        (Request r) async => response(200, (await user(r)).toJson()));
    router.get('/api/v1/assets', (Request r) async {
      final limit =
          (int.tryParse(r.url.queryParameters['limit'] ?? '100') ?? 100)
              .clamp(1, 100);
      final assets = await service.listAssets(await user(r),
          cursor: r.url.queryParameters['cursor'], limit: limit + 1);
      final page = assets.take(limit).toList();
      return response(200, {
        'assets': page,
        'nextCursor': assets.length > limit ? page.last['id'] : null,
      });
    });
    router.post(
        '/api/v1/assets',
        (Request r) async => response(
            201, await service.createAsset(await user(r), await body(r))));
    router.get(
        '/api/v1/assets/<id>',
        (Request r, String id) async =>
            response(200, await service.getAsset(await user(r), id)));
    router.patch(
        '/api/v1/assets/<id>',
        (Request r, String id) async => response(
            200,
            await service.updateAsset(await user(r), id, await revisionBody(r),
                key: r.headers['idempotency-key'])));
    router.delete(
        '/api/v1/assets/<id>',
        (Request r, String id) async => response(
            200,
            await service.deleteAsset(
                await user(r), id, await revisionBody(r))));
    router.post(
        '/api/v1/assets/<id>/transition',
        (Request r, String id) async => response(
            200,
            await service.transition(
                await user(r), id, await revisionBody(r))));
    router.post('/api/v1/assets/<id>/upload-url', (Request r, String id) async {
      final identity = await user(r), input = await body(r);
      await service.getAsset(identity, id);
      final length = input['byteLength'];
      if (length is! int ||
          length <= 0 ||
          length > HedrionService.maxUploadBytes) {
        throw const ApiFailure(
            422, 'imageSize', 'Slika može imati najviše 10 MB.');
      }
      return response(200, {
        'url': '/api/v1/assets/$id/source',
        'method': 'PUT',
        'maxBytes': HedrionService.maxUploadBytes,
        'headers': {'Content-Type': input['mime'], 'X-File-Length': '$length'},
        'note':
            'Quota is atomically reserved when the transfer starts; this URL grants no bypass.'
      });
    });
    router.put('/api/v1/assets/<id>/source', _upload);
    router.get('/api/v1/assets/<id>/download-url',
        (Request r, String id) async {
      final identity = await user(r),
          asset = await service.getAsset(identity, id);
      final fileId = asset['outputFileId'];
      if (fileId == null) {
        throw const ApiFailure(404, 'missingOutput', 'Model nema rezultat.');
      }
      final info = await service.fileInfo(identity, fileId as String);
      return response(200, {
        'url': '/api/v1/files/$fileId',
        'byteLength': info['byte_length'],
        'mime': info['mime']
      });
    });
    router.get(
        '/api/v1/files/<id>',
        (Request r, String id) async =>
            _download(r, await service.fileInfo(await user(r), id)));
    router.post(
        '/api/v1/assets/<id>/generations',
        (Request r, String id) async => response(202,
            await service.generate(await user(r), id, await body(r), key(r))));
    router.get(
        '/api/v1/assets/<id>/generations',
        (Request r, String id) async =>
            response(200, {'jobs': await service.jobs(await user(r), id)}));
    router.get(
        '/api/v1/generations/<id>',
        (Request r, String id) async =>
            response(200, await service.job(await user(r), id)));
    router.post(
        '/api/v1/generations/<id>/cancel',
        (Request r, String id) async =>
            response(200, await service.cancel(await user(r), id)));
    router.post('/api/v1/generations/<id>/retry', (Request r, String id) async {
      final identity = await user(r),
          old = await service.job(identity, id),
          input = await revisionBody(r);
      if (old['status'] != 'failed') {
        throw const ApiFailure(409, 'invalidRetry',
            'Ponovni pokušaj je dostupan za neuspešan zahtev.');
      }
      return response(
          202,
          await service.generate(
              identity,
              old['assetId'] as String,
              {
                'inputType': old['inputType'],
                'sourcePrompt': old['sourcePrompt'],
                'baseRevision': input['baseRevision']
              },
              key(r)));
    });
    router.post(
        '/api/v1/assets/<id>/submissions',
        (Request r, String id) async => response(201,
            await service.submit(await user(r), id, await body(r), key(r))));
    router.get(
        '/api/v1/my/submissions',
        (Request r) async => response(
            200,
            await service.moderation(await user(r),
                mine: true,
                cursor: r.url.queryParameters['cursor'],
                limit: int.tryParse(r.url.queryParameters['limit'] ?? '100') ??
                    100)));
    router.post(
        '/api/v1/submissions/<id>/withdraw',
        (Request r, String id) async =>
            response(200, await service.withdraw(await user(r), id)));
    router.get(
        '/api/v1/moderation/submissions',
        (Request r) async => response(
            200,
            await service.moderation(await user(r),
                cursor: r.url.queryParameters['cursor'],
                limit: int.tryParse(r.url.queryParameters['limit'] ?? '100') ??
                    100)));
    router.get('/api/v1/moderation/submissions/<id>',
        (Request r, String id) async {
      return response(
          200, await service.moderationSubmission(await user(r), id));
    });
    router.post(
        '/api/v1/moderation/submissions/<id>/approve',
        (Request r, String id) async => response(
            200,
            await service.moderate(
                await user(r), id, true, await revisionBody(r), key(r))));
    router.post(
        '/api/v1/moderation/submissions/<id>/reject',
        (Request r, String id) async => response(
            200,
            await service.moderate(
                await user(r), id, false, await revisionBody(r), key(r))));
    router.get(
        '/api/v1/projects',
        (Request r) async =>
            response(200, {'projects': await service.projects(await user(r))}));
    router.post(
        '/api/v1/projects',
        (Request r) async =>
            response(201, await service.project(await user(r), await body(r))));
    router.patch(
        '/api/v1/projects/<id>',
        (Request r, String id) async => response(
            200,
            await service.project(await user(r), await revisionBody(r),
                id: id)));
    router.post('/api/v1/sync/operations', (Request r) async {
      final identity = await user(r), input = await body(r);
      final operations = input['operations'];
      if (operations is! List || operations.length > 100) {
        throw const ApiFailure(422, 'invalidOperations',
            'Najviše 100 operacija po sinhronizaciji.');
      }
      final results = <Json>[];
      for (final operation in operations) {
        final op = jsonMap(operation),
            operationId = op['clientOperationId'] ?? op['id'];
        try {
          final asset = await service.updateAsset(
              identity,
              text(op, 'entityId'),
              {...jsonMap(op['payload']), 'baseRevision': op['baseRevision']},
              key: op['idempotencyKey'] as String? ?? operationId as String?);
          results.add({
            'id': operationId,
            'clientOperationId': operationId,
            'status': 'applied',
            'asset': asset
          });
        } on ApiFailure catch (error) {
          results.add({
            'id': operationId,
            'clientOperationId': operationId,
            'status': error.status == 409 ? 'conflict' : 'failed',
            'code': error.code,
            'message': error.message
          });
        }
      }
      return response(200, {'results': results});
    });
    router.get(
        '/api/v1/public/assets',
        (Request r) async => response(200, {
              'assets': await service.publicAssets(
                  query: r.url.queryParameters['q'] ?? '',
                  category: r.url.queryParameters['category'],
                  cursor: r.url.queryParameters['cursor'],
                  limit: int.tryParse(r.url.queryParameters['limit'] ?? '24') ??
                      24)
            }));
    router.get(
        '/api/v1/public/assets/<slug>',
        (Request r, String slug) async =>
            response(200, await service.publicAsset(slug)));
    router.get('/api/v1/public/assets/<slug>/files/<kind>',
        (Request r, String slug, String kind) async {
      if (!['model', 'preview'].contains(kind)) {
        throw const ApiFailure(404, 'notFound', 'Fajl nije pronađen.');
      }
      return _download(
          r, await service.fileInfo(null, '', slug: slug, kind: kind));
    });
    router.get(
        '/api/v1/public/categories',
        (Request r) async => response(200, {
              'categories': await service.db.transaction((tx) async =>
                  (await tx.query(
                          "SELECT DISTINCT snapshot->>'category' AS category FROM publication_submissions WHERE status='approved' ORDER BY category"))
                      .map((r) => r['category'])
                      .toList())
            }));
    router.post('/internal/v1/generations/<id>/callback', _callback);
    router.all(
        '/<ignored|.*>',
        (Request _, String ignored) => response(
            404, {'code': 'notFound', 'message': 'Putanja nije pronađena.'}));
  }

  void _browserOrigin(Request request, Json input) {
    _scope(input);
    if (input['browserSession'] == true &&
        !origins.contains(request.headers['origin'])) {
      throw const ApiFailure(
          403, 'originRequired', 'Browser sesija zahteva dozvoljeno poreklo.');
    }
  }

  String _scope(Json input) {
    final scope = input['browserSessionScope'] ?? 'studio';
    if (scope != 'studio' && scope != 'backoffice') {
      throw const ApiFailure(
          422, 'invalidBrowserScope', 'Nepodržana browser sesija.');
    }
    return scope as String;
  }

  String? _refreshCookie(Request request, String scope) {
    for (final part in (request.headers['cookie'] ?? '').split(';')) {
      final pair = part.trim().split('=');
      if (pair.length == 2 && pair.first == 'hedrion_refresh_$scope') {
        return pair[1];
      }
    }
    return null;
  }

  String _cookie(String value, String scope, {int maxAge = 2592000}) =>
      'hedrion_refresh_$scope=$value; Path=/api/v1/auth; Max-Age=$maxAge; HttpOnly; SameSite=Strict${secureCookies ? '; Secure' : ''}';
  Response _authResponse(int status, Json session,
      {required bool browser, required String scope}) {
    if (!browser) return response(status, session);
    final refresh = session.remove('refreshToken') as String;
    return response(status, session, {'set-cookie': _cookie(refresh, scope)});
  }

  Future<Response> _upload(Request request, String id) async {
    final identity = await user(request),
        length = int.tryParse(request.headers['x-file-length'] ?? '');
    if (length == null ||
        length <= 0 ||
        length > HedrionService.maxUploadBytes) {
      throw const ApiFailure(
          422, 'imageSize', 'X-File-Length mora biti do 10 MB.');
    }
    // Use HTTP framing as the authoritative size. A caller must not obtain a
    // small reservation while streaming an unbounded/chunked request body.
    if (request.contentLength == null) {
      throw const ApiFailure(411, 'lengthRequired',
          'Otpremanje zahteva unapred poznatu Content-Length veličinu.');
    }
    if (request.contentLength != length) {
      throw const ApiFailure(422, 'lengthMismatch',
          'Content-Length i X-File-Length moraju biti jednaki.');
    }
    final mime = request.headers['content-type']?.split(';').first;
    if (!['image/png', 'image/jpeg'].contains(mime)) {
      throw const ApiFailure(422, 'invalidMime', 'Podržani su PNG i JPEG.');
    }
    var reservation = await service.db.transaction((tx) async {
      await service.owned(tx, identity, id);
      return service.reserveTransfer(tx, length);
    });
    var transferDay = service.day, charged = 0, total = 0;
    final builder = BytesBuilder();
    try {
      await for (final chunk in request.read()) {
        if (total + chunk.length > length) {
          charged += length - total;
          throw const ApiFailure(
              413, 'lengthExceeded', 'Prenos je veći od najavljene veličine.');
        }
        if (service.day != transferDay) {
          await service.finishTransfer(reservation, charged);
          reservation = await service.db
              .transaction((tx) => service.reserveTransfer(tx, length - total));
          charged = 0;
          transferDay = service.day;
        }
        builder.add(chunk);
        total += chunk.length;
        charged += chunk.length;
      }
      if (total != length) {
        throw const ApiFailure(422, 'lengthMismatch', 'Prenos nije završen.');
      }
      final bytes = builder.takeBytes();
      if (!HedrionService.validImage(bytes, mime!)) {
        throw const ApiFailure(422, 'invalidImage',
            'Slika nije ispravna ili prelazi 8192 piksela.');
      }
      final result = await service.db.transaction((tx) async {
        final asset = await service.owned(tx, identity, id);
        if (!['draft', 'failed'].contains(asset.lifecycle.name)) {
          throw const ApiFailure(
              409, 'cannotUpload', 'Ulaz menjajte pre generisanja.');
        }
        final file = await service.persistFile(
            tx, identity.id, id, 'source', bytes, mime);
        final data = asset.toJson()
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = service.now.toIso8601String();
        await service.saveAsset(tx, data);
        return {'asset': data, 'file': file};
      });
      return response(201, result);
    } finally {
      await service.finishTransfer(reservation, charged);
    }
  }

  Future<Response> _download(Request request, Json info) async {
    final file = File(
        '${service.storagePath}${Platform.pathSeparator}${info['storage_key']}');
    if (!await file.exists()) {
      throw const ApiFailure(404, 'fileMissing', 'Fajl nije dostupan.');
    }
    final length = info['byte_length'] as int;
    var start = 0, end = length - 1, status = 200;
    final range = request.headers['range'];
    if (range != null) {
      final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(range);
      if (match == null || length == 0) {
        throw const ApiFailure(416, 'invalidRange', 'Nepodržan opseg.');
      }
      if (match[1]!.isEmpty) {
        final suffix = int.tryParse(match[2]!) ?? 0;
        if (suffix <= 0) {
          throw const ApiFailure(416, 'invalidRange', 'Nepodržan opseg.');
        }
        start = (length - suffix).clamp(0, length);
      } else {
        start = int.parse(match[1]!);
        if (match[2]!.isNotEmpty) {
          end = int.parse(match[2]!).clamp(0, length - 1);
        }
      }
      if (start > end || start >= length) {
        throw const ApiFailure(416, 'invalidRange', 'Opseg nije dostupan.');
      }
      status = 206;
    }
    var reservation = await service.db
        .transaction((tx) => service.reserveTransfer(tx, end - start + 1));
    var charged = 0, total = 0, transferDay = service.day;
    Stream<List<int>> stream() async* {
      try {
        await for (final chunk in file.openRead(start, end + 1)) {
          if (service.day != transferDay) {
            await service.finishTransfer(reservation, charged);
            reservation = await service.db.transaction(
                (tx) => service.reserveTransfer(tx, end - start + 1 - total));
            charged = 0;
            transferDay = service.day;
          }
          charged += chunk.length;
          total += chunk.length;
          yield chunk;
        }
      } finally {
        await service.finishTransfer(reservation, charged);
      }
    }

    return Response(status, body: stream(), headers: {
      'content-type': info['mime'] as String,
      'content-length': '${end - start + 1}',
      'accept-ranges': 'bytes',
      if (status == 206) 'content-range': 'bytes $start-$end/$length',
      'content-disposition':
          '${info['kind'] == 'model' ? 'attachment' : 'inline'}; filename="hedrion-${info['id']}.${info['kind'] == 'model' ? 'glb' : info['mime'] == 'image/png' ? 'png' : 'jpg'}"'
    });
  }

  Future<Response> _callback(Request request, String id) async {
    if (!constantTimeEqual(token(request) ?? '', workerSecret)) {
      throw const ApiFailure(
          401, 'workerUnauthorized', 'Neispravan worker nalog.');
    }
    final timestamp = request.headers['x-hedrion-timestamp'] ?? '',
        nonce = request.headers['x-hedrion-nonce'] ?? '',
        signature = request.headers['x-hedrion-signature'] ?? '';
    final seconds = int.tryParse(timestamp);
    if (seconds == null ||
        (DateTime.now().millisecondsSinceEpoch ~/ 1000 - seconds).abs() > 300 ||
        nonce.length < 8 ||
        nonce.length > 200) {
      throw const ApiFailure(
          401, 'staleWorkerEvent', 'Worker poruka je istekla.');
    }
    final rawBytes = BytesBuilder();
    await for (final chunk in request.read()) {
      rawBytes.add(chunk);
      if (rawBytes.length > 200000000) {
        throw const ApiFailure(413, 'requestTooLarge', 'Rezultat je prevelik.');
      }
    }
    final encoded = utf8.decode(rawBytes.takeBytes()),
        input = jsonMap(jsonDecode(encoded));
    if (!constantTimeEqual(
        signature, workerSignature(workerSecret, timestamp, nonce, encoded))) {
      throw const ApiFailure(401, 'invalidSignature', 'Neispravan potpis.');
    }
    await service.db.transaction((tx) async {
      if (await tx.one(
              'SELECT nonce FROM worker_callback_nonces WHERE nonce=@nonce',
              {'nonce': nonce}) !=
          null) {
        throw const ApiFailure(
            409, 'replayedCallback', 'Poruka je već obrađena.');
      }
      await tx.query('INSERT INTO worker_callback_nonces(nonce) VALUES(@nonce)',
          {'nonce': nonce});
    });
    await scheduler.complete(id, input);
    return response(200, {'accepted': true});
  }
}

Response response(int status, Object data,
        [Map<String, String> headers = const {}]) =>
    Response(status, body: jsonEncode(data), headers: {
      'content-type': 'application/json; charset=utf-8',
      ...headers
    });
