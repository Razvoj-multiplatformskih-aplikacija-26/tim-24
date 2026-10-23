import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'database.dart';
import 'security.dart';
import 'service.dart';

/// The API owns admission and persistence. A worker only returns candidate bytes.
class JobScheduler {
  JobScheduler(this.service,
      {required this.workerUrl, required this.workerSecret});
  final HedrionService service;
  final String workerUrl, workerSecret;
  Timer? _timer;
  bool _claiming = false;
  final Set<Future<void>> _active = {};
  void start() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => tick());
    unawaited(tick());
  }

  Future<void> close() async {
    _timer?.cancel();
    await Future.wait(_active);
  }

  Future<void> tick() async {
    if (_claiming) return;
    _claiming = true;
    try {
      for (var slot = 0; slot < 2; slot++) {
        final job = await claim();
        if (job == null) break;
        late Future<void> work;
        work = run(job).whenComplete(() => _active.remove(work));
        _active.add(work);
      }
    } catch (_) {
      stderr.writeln('Scheduler database temporarily unavailable.');
    } finally {
      _claiming = false;
    }
  }

  Future<Json?> claim() => service.db.transaction((tx) async {
        // An interrupted job consumes its original admission and is never silently
        // resubmitted to a paid provider. The owner may intentionally create a retry.
        final expired = await tx.query(
            "SELECT id,asset_id FROM generation_jobs WHERE status='running' AND lease_until<@now",
            {'now': service.now});
        for (final row in expired) {
          await tx.query(
              "UPDATE generation_jobs SET status='failed',failure_code='workerLeaseExpired',finished_at=@now WHERE id=@id",
              {'now': service.now, 'id': row['id']});
          final asset = await tx.one(
              'SELECT data FROM assets WHERE id=@id', {'id': row['asset_id']});
          if (asset != null) {
            final data = jsonMap(asset['data'])
              ..['lifecycle'] = 'failed'
              ..['revision'] = (jsonMap(asset['data'])['revision'] as int) + 1
              ..['updatedAt'] = service.now.toIso8601String();
            await service.saveAsset(tx, data);
          }
        }
        final count = (await tx.one(
                "SELECT count(*) AS count FROM generation_jobs WHERE status='running'"))![
            'count'] as int;
        if (count >= 2) return null;
        final row = await tx.one(
            "SELECT * FROM generation_jobs WHERE status='queued' ORDER BY accepted_at,id LIMIT 1 FOR UPDATE SKIP LOCKED");
        if (row == null) return null;
        await tx.query(
            "UPDATE generation_jobs SET status='running',started_at=@now,lease_until=@lease,attempt=attempt+1 WHERE id=@id",
            {
              'id': row['id'],
              'now': service.now,
              'lease': service.now.add(const Duration(minutes: 5))
            });
        final assetRow = await tx.one(
            'SELECT data FROM assets WHERE id=@id AND deleted_at IS NULL',
            {'id': row['asset_id']});
        if (assetRow == null) {
          await tx.query(
              "UPDATE generation_jobs SET status='failed',failure_code='assetDeleted' WHERE id=@id",
              {'id': row['id']});
          return null;
        }
        final asset = Asset.fromJson(jsonMap(assetRow['data']));
        service.validated(validateTransition(asset, AssetLifecycle.generating,
            const Actor(id: UserId('scheduler'), role: UserRole.admin)));
        final data = asset.toJson()
          ..['lifecycle'] = 'generating'
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = service.now.toIso8601String();
        await service.saveAsset(tx, data);
        return jsonMap(row['data']);
      });
  Future<void> run(Json job) async {
    final heartbeat = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(service.db.transaction((tx) async {
        await tx.query(
            "UPDATE generation_jobs SET lease_until=@lease WHERE id=@id AND status='running' AND lease_until>@now",
            {
              'id': job['id'],
              'now': service.now,
              'lease': service.now.add(const Duration(minutes: 5))
            });
      }).catchError((_) {}));
    });
    try {
      final body = <String, dynamic>{
        'jobId': job['id'],
        'ownerId': job['ownerId'],
        'inputType': job['inputType'],
        'sourcePrompt': job['sourcePrompt']
      };
      if (job['sourceImageFileId'] != null) {
        final file = await service.db.transaction((tx) => tx.one(
            'SELECT storage_key FROM stored_files WHERE id=@id AND deleted_at IS NULL',
            {'id': job['sourceImageFileId']}));
        if (file == null) {
          throw const ApiFailure(
              422, 'missingSource', 'Ulazna slika nije pronađena.');
        }
        body['sourceImageBase64'] = base64Encode(await File(
                '${service.storagePath}${Platform.pathSeparator}${file['storage_key']}')
            .readAsBytes());
      }
      final encoded = jsonEncode(body),
          timestamp = '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
          nonce = newId();
      final response = await http
          .post(Uri.parse('$workerUrl/internal/v1/generate'),
              headers: {
                'content-type': 'application/json',
                'authorization': 'Bearer $workerSecret',
                'x-hedrion-timestamp': timestamp,
                'x-hedrion-nonce': nonce,
                'x-hedrion-signature':
                    workerSignature(workerSecret, timestamp, nonce, encoded)
              },
              body: encoded)
          .timeout(const Duration(minutes: 20));
      if (response.statusCode != 200) {
        throw const ApiFailure(502, 'workerFailed', 'Obrada nije uspela.');
      }
      if (response.bodyBytes.length > 200000000) {
        throw const ApiFailure(
            502, 'workerOutputTooLarge', 'Rezultat je prevelik.');
      }
      await complete(job['id'] as String, jsonMap(jsonDecode(response.body)));
    } catch (error) {
      try {
        await markFailed(job['id'] as String,
            error is ApiFailure ? error.code : 'workerUnavailable');
      } catch (_) {
        // The durable running row and its lease are sufficient for recovery.
        // A transient DB outage must not become an unhandled Future that stops
        // the entire API process while other clients still have active work.
        stderr.writeln('Worker outcome awaits durable lease reconciliation.');
      }
    } finally {
      heartbeat.cancel();
    }
  }

  Future<void> complete(String id, Json result) =>
      service.db.transaction((tx) async {
        final row = await tx
            .one('SELECT * FROM generation_jobs WHERE id=@id', {'id': id});
        if (row == null ||
            row['status'] != 'running' ||
            row['lease_until'] == null ||
            !(row['lease_until'] as DateTime).isAfter(service.now)) {
          throw const ApiFailure(
              409, 'staleCallback', 'Zahtev više nije aktivan.');
        }
        if (result['jobId'] != id) {
          throw const ApiFailure(
              422, 'jobMismatch', 'Rezultat nije namenjen ovom zahtevu.');
        }
        final model = base64Decode(text(result, 'modelBase64')),
            preview = base64Decode(text(result, 'previewBase64'));
        if (!validGlb(model) ||
            !HedrionService.validImage(preview, 'image/png')) {
          throw const ApiFailure(502, 'invalidWorkerOutput',
              'Worker nije vratio ispravan GLB i PNG pregled.');
        }
        final assetRow = await tx.one(
            'SELECT data FROM assets WHERE id=@id AND deleted_at IS NULL',
            {'id': row['asset_id']});
        if (assetRow == null) {
          throw const ApiFailure(404, 'assetDeleted', 'Model je obrisan.');
        }
        final modelFile = await service.persistFile(
            tx,
            row['owner_id'] as String,
            row['asset_id'] as String,
            'model',
            model,
            'model/gltf-binary');
        final previewFile = await service.persistFile(
            tx,
            row['owner_id'] as String,
            row['asset_id'] as String,
            'preview',
            preview,
            'image/png');
        final json = jsonMap(assetRow['data'])
          ..['outputFileId'] = modelFile['id']
          ..['previewFileId'] = previewFile['id'];
        final asset = Asset.fromJson(json);
        service.validated(validateTransition(asset, AssetLifecycle.ready,
            const Actor(id: UserId('scheduler'), role: UserRole.admin)));
        json['lifecycle'] = 'ready';
        json['revision'] = asset.revision + 1;
        json['updatedAt'] = service.now.toIso8601String();
        await service.saveAsset(tx, json);
        final data = jsonMap(row['data'])
          ..['provider'] = result['provider']
          ..['outputFileId'] = modelFile['id']
          ..['metadata'] = result['metadata']
          ..['metrics'] = result['metrics'];
        await tx.query(
            "UPDATE generation_jobs SET status='succeeded',finished_at=@now,lease_until=NULL,data=@data::jsonb WHERE id=@id",
            {'now': service.now, 'id': id, 'data': jsonEncode(data)});
      });
  Future<void> markFailed(String id, String code) =>
      service.db.transaction((tx) async {
        final row = await tx.one(
            "SELECT * FROM generation_jobs WHERE id=@id AND status='running'",
            {'id': id});
        if (row == null) return;
        await tx.query(
            "UPDATE generation_jobs SET status='failed',failure_code=@code,finished_at=@now,lease_until=NULL WHERE id=@id",
            {'id': id, 'code': code, 'now': service.now});
        final asset = await tx.one(
            'SELECT data FROM assets WHERE id=@id AND deleted_at IS NULL',
            {'id': row['asset_id']});
        if (asset == null) return;
        final json = jsonMap(asset['data'])
          ..['lifecycle'] = 'failed'
          ..['revision'] = (jsonMap(asset['data'])['revision'] as int) + 1
          ..['updatedAt'] = service.now.toIso8601String();
        await service.saveAsset(tx, json);
      });
}

bool validGlb(Uint8List bytes) {
  if (bytes.length < 20) return false;
  final header = ByteData.sublistView(bytes);
  if (header.getUint32(0, Endian.little) != 0x46546c67 ||
      header.getUint32(4, Endian.little) != 2 ||
      header.getUint32(8, Endian.little) != bytes.length) {
    return false;
  }
  var offset = 12;
  var first = true;
  while (offset < bytes.length) {
    if (offset + 8 > bytes.length) return false;
    final length = header.getUint32(offset, Endian.little),
        type = header.getUint32(offset + 4, Endian.little);
    if (length % 4 != 0 || offset + 8 + length > bytes.length) return false;
    if (first) {
      if (type != 0x4e4f534a) return false;
      try {
        final gltf = jsonDecode(
            utf8.decode(bytes.sublist(offset + 8, offset + 8 + length))) as Map;
        if ((gltf['asset'] as Map?)?['version'] != '2.0') return false;
      } catch (_) {
        return false;
      }
      first = false;
    }
    offset += 8 + length;
  }
  return offset == bytes.length && !first;
}
