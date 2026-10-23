import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:domain/domain.dart';
import 'package:image/image.dart' as image;
import 'database.dart';
import 'security.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.status, this.code, this.message, [this.details]);
  final int status;
  final String code;
  final String message;
  final Object? details;
}

class Identity {
  Identity(this.id, this.role, this.displayName, this.email);
  final String id, role, displayName, email;
  Actor get actor => Actor(id: UserId(id), role: UserRole.values.byName(role));
  Json toJson() =>
      {'id': id, 'role': role, 'displayName': displayName, 'email': email};
}

class HedrionService {
  HedrionService(this.db, this.storagePath,
      {DateTime Function()? clock,
      this.generationProvider = 'fake',
      this.fileRemover})
      : clock = clock ?? DateTime.now;
  final Database db;
  final String storagePath;
  final String generationProvider;
  final Future<void> Function(File file)? fileRemover;
  final DateTime Function() clock;
  DateTime get now => clock().toUtc();
  String get day => now.toIso8601String().substring(0, 10);
  static const maxUploadBytes = 10000000;
  static final Future<String> _dummyPasswordHash =
      Passwords.hash('invalid-login-password');

  Never fail(int status, String code, String message, [Object? details]) =>
      throw ApiFailure(status, code, message, details);
  void validated<T>(Validation<T> result) {
    if (!result.isValid) {
      final error = result.error!;
      fail(error.code.name.contains('Quota') ? 429 : 422, error.code.name,
          error.message);
    }
  }

  Future<Identity> authenticate(String? token) async {
    if (token == null || token.isEmpty) {
      fail(401, 'unauthorized', 'Prijavite se da biste nastavili.');
    }
    return db.transaction((tx) async {
      final user = await tx.one(
          'SELECT u.* FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.token_hash=@token AND s.revoked_at IS NULL AND s.expires_at>@now AND u.disabled_at IS NULL',
          {'token': digest(token), 'now': now});
      if (user == null) {
        fail(401, 'sessionExpired', 'Sesija je istekla. Prijavite se ponovo.');
      }
      return Identity(user['id'] as String, user['role'] as String,
          user['display_name'] as String, user['email'] as String);
    });
  }

  Future<Json> register(Json input) async {
    final email = text(input, 'email').trim().toLowerCase();
    final password = text(input, 'password');
    final name = text(input, 'displayName').trim();
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email) ||
        email.length > 254 ||
        name.length < 2 ||
        name.length > 80 ||
        password.length < 12 ||
        password.length > 256) {
      fail(422, 'invalidRegistration',
          'Unesite ispravan imejl, ime i lozinku od najmanje 12 znakova.');
    }
    final hash = await Passwords.hash(password);
    return db.transaction((tx) async {
      if (await tx.one(
              'SELECT id FROM users WHERE email=@email', {'email': email}) !=
          null) {
        fail(409, 'emailExists', 'Nalog sa ovim imejlom već postoji.');
      }
      final id = newId();
      await tx.query(
          'INSERT INTO users(id,email,password_hash,display_name,role) VALUES(@id,@email,@hash,@name,\'creator\')',
          {'id': id, 'email': email, 'hash': hash, 'name': name});
      return _session(tx, Identity(id, 'creator', name, email));
    });
  }

  Future<Json> login(Json input) async {
    final email = text(input, 'email').trim().toLowerCase();
    final row = await db.transaction((tx) => tx.one(
        'SELECT * FROM users WHERE email=@email AND disabled_at IS NULL',
        {'email': email}));
    // Equal-cost derivation avoids an obvious unknown-email timing oracle.
    final valid = row == null
        ? await Passwords.verify(
            text(input, 'password'), await _dummyPasswordHash)
        : await Passwords.verify(
            text(input, 'password'), row['password_hash'] as String);
    if (row == null || !valid) {
      fail(401, 'invalidCredentials', 'Imejl ili lozinka nisu ispravni.');
    }
    final user = Identity(row['id'] as String, row['role'] as String,
        row['display_name'] as String, row['email'] as String);
    return db.transaction((tx) => _session(tx, user));
  }

  Future<Json> _session(Tx tx, Identity user) async {
    final token = randomToken(), refresh = randomToken();
    await tx.query(
        'INSERT INTO sessions(token_hash,refresh_hash,user_id,expires_at,refresh_expires_at) VALUES(@token,@refresh,@user,@expires,@refreshExpires)',
        {
          'token': digest(token),
          'refresh': digest(refresh),
          'user': user.id,
          'expires': now.add(const Duration(hours: 1)),
          'refreshExpires': now.add(const Duration(days: 30))
        });
    return {
      'token': token,
      'refreshToken': refresh,
      'expiresAt': now.add(const Duration(hours: 1)).toIso8601String(),
      'user': user.toJson()
    };
  }

  Future<Json> refresh(Json input) => db.transaction((tx) async {
        final row = await tx.one(
            'SELECT u.*,s.token_hash FROM sessions s JOIN users u ON u.id=s.user_id WHERE s.refresh_hash=@hash AND s.revoked_at IS NULL AND s.refresh_expires_at>@now AND u.disabled_at IS NULL',
            {'hash': digest(text(input, 'refreshToken')), 'now': now});
        if (row == null) fail(401, 'invalidRefresh', 'Sesija je istekla.');
        await tx.query(
            'UPDATE sessions SET revoked_at=@now WHERE token_hash=@hash',
            {'now': now, 'hash': row['token_hash']});
        return _session(
            tx,
            Identity(row['id'] as String, row['role'] as String,
                row['display_name'] as String, row['email'] as String));
      });
  Future<void> logout(String token) => db.transaction((tx) async {
        await tx.query(
            'UPDATE sessions SET revoked_at=@now WHERE token_hash=@hash',
            {'now': now, 'hash': digest(token)});
      });
  Future<Asset> owned(Tx tx, Identity user, String id) async {
    final row = await tx.one(
        'SELECT data FROM assets WHERE id=@id AND deleted_at IS NULL',
        {'id': id});
    if (row == null) fail(404, 'assetNotFound', 'Model nije pronađen.');
    final asset = Asset.fromJson(jsonMap(row['data']));
    if (asset.ownerId.value != user.id) {
      fail(404, 'assetNotFound', 'Model nije pronađen.');
    }
    return asset;
  }

  Future<List<Json>> listAssets(Identity user,
          {String? cursor, int limit = 100}) =>
      db.transaction((tx) async {
        final rows = await tx.query(
            'SELECT data FROM assets WHERE owner_id=@owner AND deleted_at IS NULL AND (@cursor::text IS NULL OR id>@cursor) ORDER BY id LIMIT @limit',
            // The HTTP adapter requests one extra row to construct nextCursor.
            {'owner': user.id, 'cursor': cursor, 'limit': limit.clamp(1, 101)});
        return rows.map((row) => jsonMap(row['data'])).toList();
      });
  Future<Json> getAsset(Identity user, String id) =>
      db.transaction((tx) async => (await owned(tx, user, id)).toJson());
  Future<void> saveAsset(Tx tx, Json asset) async {
    await tx.query(
        'UPDATE assets SET data=@data::jsonb,revision=@revision,updated_at=@updated WHERE id=@id',
        {
          'data': jsonEncode(asset),
          'revision': asset['revision'],
          'updated': DateTime.parse(asset['updatedAt'] as String),
          'id': asset['id']
        });
  }

  Future<Json> createAsset(Identity user, Json input) =>
      db.transaction((tx) async {
        validated(validateTitle(text(input, 'title')));
        final id = newId(), date = now.toIso8601String();
        final json = <String, dynamic>{
          'id': id,
          'ownerId': user.id,
          'title': text(input, 'title').trim(),
          'description': text(input, 'description', fallback: ''),
          'category': text(input, 'category', fallback: 'props'),
          'projectId': null,
          'tags': <String>[],
          'favorite': false,
          'lifecycle': 'draft',
          'createdAt': date,
          'updatedAt': date,
          'revision': 1,
          'outputFileId': null,
          'previewFileId': null,
          'rejectionReason': null,
          'allowDownload': false,
          'license': 'allRightsReserved'
        };
        _metadata(json, input);
        if (input['projectId'] != null &&
            await tx.one(
                    'SELECT id FROM projects WHERE id=@id AND owner_id=@owner',
                    {'id': input['projectId'], 'owner': user.id}) ==
                null) {
          fail(422, 'invalidProject', 'Projekat nije pronađen.');
        }
        await tx.query(
            'INSERT INTO assets(id,owner_id,data) VALUES(@id,@owner,@data::jsonb)',
            {'id': id, 'owner': user.id, 'data': jsonEncode(json)});
        return json;
      });
  void _metadata(Json asset, Json input) {
    if (input.containsKey('title')) {
      validated(validateTitle(text(input, 'title')));
      asset['title'] = text(input, 'title').trim();
    }
    if (input.containsKey('description')) {
      asset['description'] = text(input, 'description');
    }
    if (input.containsKey('favorite')) {
      if (input['favorite'] is! bool) {
        fail(422, 'invalidFavorite', 'Neispravna vrednost favorita.');
      }
      asset['favorite'] = input['favorite'];
    }
    if (input.containsKey('category')) {
      asset['category'] = text(input, 'category');
    }
    if (input.containsKey('tags')) {
      final tags = input['tags'];
      if (tags is! List || tags.any((tag) => tag is! String)) {
        fail(422, 'invalidTags', 'Oznake moraju biti lista tekstova.');
      }
      asset['tags'] = tags;
    }
    if (input.containsKey('projectId')) asset['projectId'] = input['projectId'];
    validated(validateDraft(AssetDraft(
        title: asset['title'] as String,
        description: asset['description'] as String,
        category: asset['category'] as String,
        tags: (asset['tags'] as List).cast<String>())));
  }

  Future<Json> updateAsset(Identity user, String id, Json input,
          {String? key}) =>
      db.transaction((tx) async {
        final command = {'assetId': id, ...input};
        if (key != null) {
          if (key.length < 8 || key.length > 200) {
            fail(422, 'invalidIdempotencyKey',
                'Idempotency-Key mora imati od 8 do 200 znakova.');
          }
          final replay = await replayCommand(tx, user, 'update:$key', command);
          if (replay != null) return replay;
        }
        final asset = await owned(tx, user, id);
        _revision(asset.revision, input);
        final json = asset.toJson();
        _metadata(json, input);
        if (input['projectId'] != null &&
            await tx.one(
                    'SELECT id FROM projects WHERE id=@id AND owner_id=@owner',
                    {'id': input['projectId'], 'owner': user.id}) ==
                null) {
          fail(422, 'invalidProject', 'Projekat nije pronađen.');
        }
        json['revision'] = asset.revision + 1;
        json['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, json);
        if (key != null) await remember(tx, user, 'update:$key', command, json);
        return json;
      });
  void _revision(int revision, Json input) {
    if (input['baseRevision'] != revision) {
      fail(
          409,
          'revisionConflict',
          'Model je izmenjen na drugom uređaju. Osvežite podatke i ponovite izmenu.',
          {'currentRevision': revision});
    }
  }

  Future<Json?> replayCommand(
      Tx tx, Identity user, String key, Json input) async {
    if (key.length < 8 || key.length > 240) {
      fail(422, 'invalidIdempotencyKey',
          'Idempotency-Key mora imati od 8 do 200 znakova.');
    }
    final row = await tx.one(
        'SELECT * FROM idempotent_commands WHERE actor_id=@actor AND command_key=@key',
        {'actor': user.id, 'key': key});
    if (row == null) return null;
    if (row['request_hash'] != digest(jsonEncode(input))) {
      fail(409, 'idempotencyConflict',
          'Isti ključ je upotrebljen za drugi zahtev.');
    }
    return jsonMap(row['response']);
  }

  Future<void> remember(
      Tx tx, Identity user, String key, Json input, Json response) async {
    await tx.query(
        'INSERT INTO idempotent_commands(actor_id,command_key,request_hash,response) VALUES(@actor,@key,@hash,@response::jsonb)',
        {
          'actor': user.id,
          'key': key,
          'hash': digest(jsonEncode(input)),
          'response': jsonEncode(response)
        });
  }

  Future<Json> generate(Identity user, String id, Json input, String key) =>
      db.transaction((tx) async {
        final command = {'assetId': id, ...input};
        final replay = await replayCommand(tx, user, 'generate:$key', command);
        if (replay != null) return replay;
        final asset = await owned(tx, user, id);
        _revision(asset.revision, input);
        validated(validateTransition(asset, AssetLifecycle.queued, user.actor));
        if (await tx.one(
                "SELECT id FROM generation_jobs WHERE owner_id=@owner AND status IN ('queued','running')",
                {'owner': user.id}) !=
            null) {
          fail(429, 'activeJobLimit',
              'Već imate aktivan zahtev. Sačekajte njegov završetak.');
        }
        final inputType = text(input, 'inputType', fallback: 'image_to_3d');
        if (inputType == 'text_to_3d' && generationProvider != 'fake') {
          fail(422, 'unsupportedInput',
              'Tekstualni tok zahteva zaseban potvrđen text-to-image provider. Izaberite referentnu sliku.');
        }
        if (inputType != 'image_to_3d' && inputType != 'text_to_3d') {
          fail(422, 'unsupportedInput', 'Nepodržan tip unosa.');
        }
        final source = await tx.one(
            "SELECT id FROM stored_files WHERE asset_id=@id AND kind='source' AND deleted_at IS NULL ORDER BY created_at DESC LIMIT 1",
            {'id': id});
        if (inputType == 'image_to_3d' && source == null) {
          fail(
              422, 'sourceImageRequired', 'Najpre otpremite referentnu sliku.');
        }
        if (inputType == 'text_to_3d' &&
            text(input, 'sourcePrompt', fallback: '').trim().length < 3) {
          fail(422, 'promptRequired', 'Unesite opis modela.');
        }
        await _daily(tx);
        final admissions = await tx.query(
            'SELECT id,owner_id,accepted_at FROM generation_jobs WHERE accepted_at>=@start AND accepted_at<@end',
            {
              'start': DateTime.parse('${day}T00:00:00Z'),
              'end': DateTime.parse('${day}T00:00:00Z')
                  .add(const Duration(days: 1))
            });
        validated(validateDailyGenerationQuota(
            admissions
                .map((r) => GenerationAdmission(
                    jobId: JobId(r['id'] as String),
                    ownerId: UserId(r['owner_id'] as String),
                    acceptedAt: r['accepted_at'] as DateTime))
                .toList(),
            now));
        await tx.query(
            'UPDATE daily_usage SET accepted_generations=accepted_generations+1 WHERE day=@day::date',
            {'day': day});
        final job = {
          'id': newId(),
          'assetId': id,
          'ownerId': user.id,
          'inputType': inputType,
          'sourceImageFileId': source?['id'],
          'sourcePrompt': input['sourcePrompt'],
          'status': 'queued',
          'acceptedAt': now.toIso8601String(),
          'provider': 'fake',
          'retryCount': 0
        };
        await tx.query(
            "INSERT INTO generation_jobs(id,asset_id,owner_id,status,accepted_at,data,idempotency_key) VALUES(@id,@asset,@owner,'queued',@accepted,@data::jsonb,@key)",
            {
              'id': job['id'],
              'asset': id,
              'owner': user.id,
              'accepted': now,
              'data': jsonEncode(job),
              'key': key
            });
        final json = asset.toJson()
          ..['lifecycle'] = 'queued'
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, json);
        final result = {'job': job, 'asset': json};
        await remember(tx, user, 'generate:$key', command, result);
        return result;
      });
  Future<Json> job(Identity user, String id) => db.transaction((tx) async {
        final row = await tx.one(
            'SELECT * FROM generation_jobs WHERE id=@id AND owner_id=@owner',
            {'id': id, 'owner': user.id});
        if (row == null) fail(404, 'jobNotFound', 'Zahtev nije pronađen.');
        return _jobJson(row);
      });
  Future<List<Json>> jobs(Identity user, String assetId) =>
      db.transaction((tx) async {
        await owned(tx, user, assetId);
        final rows = await tx.query(
            'SELECT * FROM generation_jobs WHERE asset_id=@asset AND owner_id=@owner ORDER BY accepted_at DESC,id DESC',
            {'asset': assetId, 'owner': user.id});
        return rows.map(_jobJson).toList();
      });
  Json _jobJson(Json row) => jsonMap(row['data'])
    ..['status'] = row['status']
    ..['failureCode'] = row['failure_code']
    ..['startedAt'] =
        (row['started_at'] as DateTime?)?.toUtc().toIso8601String()
    ..['finishedAt'] =
        (row['finished_at'] as DateTime?)?.toUtc().toIso8601String()
    ..['failureMessage'] = row['failure_code'] == null
        ? null
        : switch (row['failure_code']) {
            'storageQuotaExceeded' =>
              'Rezultat nije sačuvan jer je zajedničko skladište popunjeno.',
            'workerLeaseExpired' =>
              'Worker nije potvrdio da je obrada i dalje aktivna.',
            'workerUnavailable' => 'Worker trenutno nije dostupan.',
            'invalidWorkerOutput' =>
              'Worker nije vratio ispravan GLB rezultat.',
            _ => 'Obrada nije uspela. Možete pokrenuti novi pokušaj.'
          };
  Future<Json> cancel(Identity user, String id) => db.transaction((tx) async {
        final row = await tx.one(
            'SELECT * FROM generation_jobs WHERE id=@id AND owner_id=@owner',
            {'id': id, 'owner': user.id});
        if (row == null) fail(404, 'jobNotFound', 'Zahtev nije pronađen.');
        if (row['status'] != 'queued') {
          fail(409, 'cannotCancel',
              'Otkazivanje je dostupno samo pre početka obrade.');
        }
        await tx.query(
            "UPDATE generation_jobs SET status='cancelled',finished_at=@now WHERE id=@id",
            {'id': id, 'now': now});
        final asset = await owned(tx, user, row['asset_id'] as String);
        final json = asset.toJson()
          ..['lifecycle'] = 'failed'
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, json);
        return {'id': id, 'status': 'cancelled', 'asset': json};
      });
  Future<Json> submit(Identity user, String id, Json input, String key) =>
      db.transaction((tx) async {
        final command = {'assetId': id, ...input};
        final replay = await replayCommand(tx, user, 'submit:$key', command);
        if (replay != null) return replay;
        final asset = await owned(tx, user, id);
        _revision(asset.revision, input);
        validated(validateTransition(
            asset, AssetLifecycle.pendingReview, user.actor));
        if (input['confirmRights'] != true) {
          fail(422, 'rightsRequired',
              'Potvrdite prava na ulaznu sliku i model.');
        }
        final license = text(input, 'license', fallback: 'ccBy');
        if (!['ccBy', 'cc0', 'allRightsReserved'].contains(license)) {
          fail(422, 'invalidLicense', 'Izaberite podržanu licencu.');
        }
        final allowDownload = input['allowDownload'] == true;
        if (allowDownload && license == 'allRightsReserved') {
          fail(422, 'licenseDownloadDenied',
              'Za preuzimanje izaberite CC BY ili CC0 licencu.');
        }
        final snapshot = asset.toJson()
          ..['license'] = license
          ..['allowDownload'] = allowDownload;
        final submissionId = newId();
        final slug =
            '${asset.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-')}-${submissionId.substring(0, 8)}';
        await tx.query(
            "INSERT INTO publication_submissions(id,asset_id,submitter_id,status,snapshot,slug) VALUES(@id,@asset,@owner,'pending_review',@snapshot::jsonb,@slug)",
            {
              'id': submissionId,
              'asset': id,
              'owner': user.id,
              'snapshot': jsonEncode(snapshot),
              'slug': slug
            });
        final json = asset.toJson()
          ..['lifecycle'] = 'pendingReview'
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, json);
        final result = {
          'asset': json,
          'submission': {
            'id': submissionId,
            'assetId': id,
            'status': 'pending_review',
            'slug': slug,
            'revision': 1
          }
        };
        await remember(tx, user, 'submit:$key', command, result);
        return result;
      });
  void requireModerator(Identity user) {
    if (!['moderator', 'admin'].contains(user.role)) {
      fail(403, 'moderatorRequired', 'Ovu radnju može da izvrši moderator.');
    }
  }

  static const _submissionSelect = '''SELECT s.*,a.data AS asset_data,
    u.display_name AS submitter_name,
    (SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'actorName',actor.display_name,'action',e.action,
      'createdAt',e.created_at,'reason',e.reason)
      ORDER BY e.created_at,e.id),'[]'::jsonb)
      FROM moderation_events e JOIN users actor ON actor.id=e.moderator_id
      WHERE e.submission_id=s.id) AS audit
    FROM publication_submissions s JOIN assets a ON a.id=s.asset_id
    JOIN users u ON u.id=s.submitter_id''';

  Future<Json> moderation(Identity user,
          {bool mine = false, String? cursor, int limit = 100}) =>
      db.transaction((tx) async {
        if (!mine) requireModerator(user);
        final pageSize = limit.clamp(1, 100);
        final rows = await tx.query(
            '''SELECT DISTINCT ON (page.asset_id) page.* FROM ($_submissionSelect
              WHERE a.deleted_at IS NULL AND (@mine=false OR s.submitter_id=@owner)
              AND (@cursor::text IS NULL OR s.asset_id>@cursor)) page
              ORDER BY page.asset_id,page.submitted_at DESC,page.id DESC LIMIT @limit''',
            {
              'mine': mine,
              'owner': user.id,
              'cursor': cursor,
              'limit': pageSize + 1
            });
        final page = rows.take(pageSize).toList();
        final today = DateTime.utc(now.year, now.month, now.day);
        final counts = (await tx.one(
            '''SELECT
          count(*) FILTER (WHERE s.reviewed_at>=@today AND s.reviewed_at<@tomorrow) AS reviewed_today,
          count(*) FILTER (WHERE s.reviewed_by IS NOT NULL) AS reviewed_total,
          count(*) FILTER (WHERE s.reviewed_by IS NOT NULL AND EXISTS
            (SELECT 1 FROM moderation_events e WHERE e.submission_id=s.id AND e.action='approved')) AS approved_total
          FROM publication_submissions s JOIN assets a ON a.id=s.asset_id
          WHERE a.deleted_at IS NULL AND (@mine=false OR s.submitter_id=@owner)''',
            {
              'today': today,
              'tomorrow': today.add(const Duration(days: 1)),
              'mine': mine,
              'owner': user.id
            }))!;
        final activeJobs = (await tx.one(
            "SELECT count(*) AS count FROM generation_jobs WHERE status='running' AND (@mine=false OR owner_id=@owner)",
            {'mine': mine, 'owner': user.id}))!['count'] as int;
        final reviewed = counts['reviewed_total'] as int;
        return {
          'assets': page.map((row) {
            final data = jsonMap(row['snapshot']);
            final current = jsonMap(row['asset_data']);
            data['lifecycle'] = current['lifecycle'];
            data['revision'] = current['revision'];
            data['rejectionReason'] = row['rejection_reason'];
            data['submissionId'] = row['id'];
            return data;
          }).toList(),
          'submissions': page.map(_submissionJson).toList(),
          'nextCursor': rows.length > pageSize ? page.last['asset_id'] : null,
          'stats': {
            'reviewedToday': counts['reviewed_today'],
            'approvalRate': reviewed == 0
                ? 0.0
                : (counts['approved_total'] as int) / reviewed,
            'activeJobs': activeJobs,
          }
        };
      });
  Future<Json> moderationSubmission(Identity user, String id) =>
      db.transaction((tx) async {
        requireModerator(user);
        final row = await tx.one(
            '$_submissionSelect WHERE s.id=@id AND a.deleted_at IS NULL',
            {'id': id});
        if (row == null) fail(404, 'notFound', 'Prijava nije pronađena.');
        return _submissionJson(row);
      });
  Json _submissionJson(Json row) => {
        'id': row['id'],
        'assetId': row['asset_id'],
        'status': row['status'],
        'revision': row['revision'],
        'slug': row['slug'],
        'submittedAt':
            (row['submitted_at'] as DateTime).toUtc().toIso8601String(),
        'submitterName': row['submitter_name'],
        'reviewedAt':
            (row['reviewed_at'] as DateTime?)?.toUtc().toIso8601String(),
        'reviewedBy': row['reviewed_by'],
        'audit': row['audit'] ?? [],
        'rejectionReason': row['rejection_reason'],
        'snapshot': jsonMap(row['snapshot'])
      };
  Future<Json> moderate(
          Identity user, String id, bool approve, Json input, String key) =>
      db.transaction((tx) async {
        requireModerator(user);
        final command = {'id': id, 'approve': approve, ...input};
        final replay = await replayCommand(tx, user, 'moderate:$key', command);
        if (replay != null) return replay;
        final row = await tx.one(
            'SELECT * FROM publication_submissions WHERE id=@id', {'id': id});
        if (row == null) {
          fail(404, 'submissionNotFound', 'Prijava nije pronađena.');
        }
        if (row['status'] != 'pending_review') {
          fail(409, 'alreadyReviewed',
              'Drugi moderator je već obradio prijavu.');
        }
        if (input['baseRevision'] != null &&
            input['baseRevision'] != row['revision']) {
          fail(409, 'revisionConflict', 'Prijava je promenjena.');
        }
        final assetRow = await tx.one(
            'SELECT data FROM assets WHERE id=@id AND deleted_at IS NULL',
            {'id': row['asset_id']});
        if (assetRow == null) fail(404, 'assetNotFound', 'Model je obrisan.');
        final asset = Asset.fromJson(jsonMap(assetRow['data']));
        final reason = text(input, 'reason', fallback: '').trim();
        validated(validateTransition(
            asset,
            approve ? AssetLifecycle.published : AssetLifecycle.rejected,
            user.actor,
            reason: reason));
        if (!approve && (reason.length < 3 || reason.length > 1000)) {
          fail(
              422, 'reasonRequired', 'Razlog mora imati od 3 do 1000 znakova.');
        }
        final status = approve ? 'approved' : 'rejected';
        await tx.query(
            'UPDATE publication_submissions SET status=@status,revision=revision+1,reviewed_at=@now,reviewed_by=@reviewer,rejection_reason=@reason WHERE id=@id',
            {
              'status': status,
              'now': now,
              'reviewer': user.id,
              'reason': approve ? null : reason,
              'id': id
            });
        await tx.query(
            'INSERT INTO moderation_events(id,submission_id,moderator_id,action,reason) VALUES(@id,@submission,@moderator,@action,@reason)',
            {
              'id': newId(),
              'submission': id,
              'moderator': user.id,
              'action': status,
              'reason': approve ? null : reason
            });
        final json = asset.toJson()
          ..['lifecycle'] = approve ? 'published' : 'rejected'
          ..['rejectionReason'] = approve ? null : reason
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, json);
        final result = {
          'asset': json,
          'submission': {
            'id': id,
            'status': status,
            'revision': (row['revision'] as int) + 1
          }
        };
        await remember(tx, user, 'moderate:$key', command, result);
        return result;
      });
  Future<Json> withdraw(Identity user, String id) => db.transaction((tx) async {
        final row = await tx.one(
            'SELECT * FROM publication_submissions WHERE id=@id AND submitter_id=@owner',
            {'id': id, 'owner': user.id});
        if (row == null) {
          fail(404, 'submissionNotFound', 'Prijava nije pronađena.');
        }
        if (!['pending_review', 'approved'].contains(row['status'])) {
          fail(409, 'invalidTransition', 'Prijava je već zatvorena.');
        }
        await tx.query(
            'UPDATE publication_submissions SET status=@status,revision=revision+1 WHERE id=@id',
            {
              'status':
                  row['status'] == 'approved' ? 'unpublished' : 'withdrawn',
              'id': id
            });
        final asset = await owned(tx, user, row['asset_id'] as String);
        final json = asset.toJson()
          ..['lifecycle'] = 'ready'
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, json);
        return json;
      });
  Future<Json> transition(Identity user, String id, Json input) =>
      db.transaction((tx) async {
        final asset = await owned(tx, user, id);
        _revision(asset.revision, input);
        if (input['target'] != 'ready') {
          fail(422, 'invalidTransition',
              'Ova putanja dozvoljava samo povratak u privatno spremno stanje.');
        }
        validated(validateTransition(asset, AssetLifecycle.ready, user.actor));
        if (['published', 'pendingReview'].contains(asset.lifecycle.name)) {
          await tx.query(
              "UPDATE publication_submissions SET status=CASE WHEN status='approved' THEN 'unpublished' ELSE 'withdrawn' END,revision=revision+1 WHERE asset_id=@asset AND status IN ('approved','pending_review')",
              {'asset': id});
        }
        final data = asset.toJson()
          ..['lifecycle'] = 'ready'
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, data);
        return data;
      });

  /// Reconcile retained bytes before serving. Unknown files left by a killed
  /// process still consume storage; they are never silently made free space.
  Future<void> reconcileStorage() async {
    try {
      await cleanupDeletedFiles();
    } catch (_) {
      stderr.writeln(
          'Some tombstoned files await cleanup; capacity remains reserved.');
    }
    await db.transaction((tx) async {
      final directory = Directory(storagePath);
      await directory.create(recursive: true);
      var bytes = 0;
      final present = <String>{};
      await for (final entry in directory.list(followLinks: false)) {
        if (entry is File) {
          bytes += await entry.length();
          present.add(entry.uri.pathSegments.last);
        }
      }
      final retained = await tx.query(
          'SELECT storage_key,byte_length FROM stored_files WHERE deleted_at IS NULL');
      for (final record in retained) {
        if (!present.contains(record['storage_key'])) {
          bytes += record['byte_length'] as int;
        }
      }
      if (bytes > 10000000000) {
        fail(507, 'storageOverCapacity',
            'Skladište prelazi dozvoljenih 10 GB. Potrebno je kontrolisano čišćenje.');
      }
      await tx.query(
          'UPDATE storage_usage SET stored_bytes=@bytes,reserved_bytes=0 WHERE singleton=1',
          {'bytes': bytes});
      // Persisted transfer reservations remain charged after an interrupted
      // process: exact delivered byte counts cannot be recovered safely. A normal
      // transfer always finalizes actual bytes and releases its unused capacity.
      final stale = await tx.query(
          'SELECT id,requested_bytes FROM transfer_reservations WHERE finalized_at IS NULL AND created_at<@cutoff',
          {'cutoff': now.subtract(const Duration(hours: 1))});
      for (final row in stale) {
        await tx.query(
            'UPDATE daily_usage SET reserved_transfer_bytes=reserved_transfer_bytes-@bytes,transferred_bytes=transferred_bytes+@bytes WHERE day=(SELECT day FROM transfer_reservations WHERE id=@id)',
            {'bytes': row['requested_bytes'], 'id': row['id']});
        await tx.query(
            'UPDATE transfer_reservations SET actual_bytes=requested_bytes,finalized_at=@now WHERE id=@id',
            {'now': now, 'id': row['id']});
      }
    });
  }

  Future<List<Json>> publicAssets(
          {String query = '',
          String? category,
          String? cursor,
          int limit = 24}) =>
      db.transaction((tx) async {
        final rows = await tx.query(
            "SELECT s.*,u.display_name FROM publication_submissions s JOIN assets a ON a.id=s.asset_id JOIN users u ON u.id=s.submitter_id WHERE s.status='approved' AND a.deleted_at IS NULL AND (@query='' OR s.snapshot->>'title' ILIKE @search) AND (@category::text IS NULL OR s.snapshot->>'category'=@category) AND (@cursor::text IS NULL OR s.slug>@cursor) ORDER BY s.slug LIMIT @limit",
            {
              'query': query,
              'search': '%$query%',
              'category': category,
              'cursor': cursor,
              'limit': limit.clamp(1, 100)
            });
        return rows.map(_publicJson).toList();
      });
  Json _publicJson(Json row) {
    final snap = jsonMap(row['snapshot']);
    return {
      'slug': row['slug'],
      'title': snap['title'],
      'description': snap['description'],
      'category': snap['category'],
      'tags': snap['tags'],
      'license': snap['license'],
      'allowDownload': snap['allowDownload'],
      'author': row['display_name'],
      'format': 'GLB',
      'lifecycle': 'published',
      'status': 'approved',
      'previewUrl': '/api/v1/public/assets/${row['slug']}/files/preview',
      'downloadUrl': snap['allowDownload'] == true
          ? '/api/v1/public/assets/${row['slug']}/files/model'
          : null
    };
  }

  Future<Json> publicAsset(String slug) => db.transaction((tx) async {
        final row = await tx.one(
            "SELECT s.*,u.display_name FROM publication_submissions s JOIN assets a ON a.id=s.asset_id JOIN users u ON u.id=s.submitter_id WHERE s.slug=@slug AND s.status='approved' AND a.deleted_at IS NULL",
            {'slug': slug});
        if (row == null) fail(404, 'notFound', 'Model nije pronađen.');
        return _publicJson(row);
      });
  Future<List<Json>> projects(Identity user) =>
      db.transaction((tx) async => (await tx.query(
              'SELECT * FROM projects WHERE owner_id=@owner ORDER BY name',
              {'owner': user.id}))
          .map((row) => {
                'id': row['id'],
                'ownerId': row['owner_id'],
                'name': row['name'],
                'revision': row['revision']
              })
          .toList());
  Future<Json> project(Identity user, Json input, {String? id}) =>
      db.transaction((tx) async {
        validated(validateTitle(text(input, 'name')));
        if (id == null) {
          final created = newId();
          await tx.query(
              'INSERT INTO projects(id,owner_id,name) VALUES(@id,@owner,@name)',
              {
                'id': created,
                'owner': user.id,
                'name': text(input, 'name').trim()
              });
          return {
            'id': created,
            'ownerId': user.id,
            'name': text(input, 'name').trim(),
            'revision': 1
          };
        }
        final row = await tx.one(
            'SELECT * FROM projects WHERE id=@id AND owner_id=@owner',
            {'id': id, 'owner': user.id});
        if (row == null) {
          fail(404, 'projectNotFound', 'Projekat nije pronađen.');
        }
        _revision(row['revision'] as int, input);
        await tx.query(
            'UPDATE projects SET name=@name,revision=revision+1 WHERE id=@id',
            {'name': text(input, 'name').trim(), 'id': id});
        return {
          'id': id,
          'ownerId': user.id,
          'name': text(input, 'name').trim(),
          'revision': (row['revision'] as int) + 1
        };
      });
  Future<void> _daily(Tx tx) async {
    await tx.query(
        'INSERT INTO daily_usage(day) VALUES(@day::date) ON CONFLICT DO NOTHING',
        {'day': day});
  }

  Future<String> reserveTransfer(Tx tx, int length) async {
    await _daily(tx);
    final row = (await tx
        .one('SELECT * FROM daily_usage WHERE day=@day::date', {'day': day}))!;
    validated(validateTransferQuota(
        transferredBytes: row['transferred_bytes'] as int,
        reservedBytes: row['reserved_transfer_bytes'] as int,
        requestedBytes: length));
    final id = newId();
    await tx.query(
        'UPDATE daily_usage SET reserved_transfer_bytes=reserved_transfer_bytes+@bytes WHERE day=@day::date',
        {'bytes': length, 'day': day});
    await tx.query(
        'INSERT INTO transfer_reservations(id,day,requested_bytes) VALUES(@id,@day::date,@bytes)',
        {'id': id, 'day': day, 'bytes': length});
    return id;
  }

  Future<void> finishTransfer(String id, int actual) =>
      db.transaction((tx) async {
        final row = await tx.one(
            'SELECT * FROM transfer_reservations WHERE id=@id', {'id': id});
        if (row == null || row['finalized_at'] != null) return;
        final requested = row['requested_bytes'] as int;
        if (actual < 0 || actual > requested) {
          fail(500, 'meterError', 'Neispravno merenje prenosa.');
        }
        await tx.query(
            'UPDATE daily_usage SET reserved_transfer_bytes=reserved_transfer_bytes-@requested,transferred_bytes=transferred_bytes+@actual WHERE day=@day',
            {'requested': requested, 'actual': actual, 'day': row['day']});
        await tx.query(
            'UPDATE transfer_reservations SET actual_bytes=@actual,finalized_at=@now WHERE id=@id',
            {'actual': actual, 'now': now, 'id': id});
      });
  Future<void> reserveStorage(Tx tx, int length) async {
    final row =
        (await tx.one('SELECT * FROM storage_usage WHERE singleton=1'))!;
    validated(validateStorageQuota(
        storedBytes: row['stored_bytes'] as int,
        reservedBytes: row['reserved_bytes'] as int,
        requestedBytes: length));
    await tx.query(
        'UPDATE storage_usage SET reserved_bytes=reserved_bytes+@bytes WHERE singleton=1',
        {'bytes': length});
  }

  Future<Json> persistFile(Tx tx, String owner, String asset, String kind,
      Uint8List bytes, String mime) async {
    await reserveStorage(tx, bytes.length);
    final id = newId(), key = newId();
    final directory = Directory(storagePath);
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$key');
    // Register before writing: a failed write can leave a partial file too.
    tx.onRollback.add((rollbackTx) async {
      var retainedBytes = bytes.length;
      try {
        if (fileRemover != null) {
          await fileRemover!(file);
        } else {
          await file.delete();
        }
        if (!await file.exists()) return;
      } on FileSystemException catch (error) {
        // A missing file/path is confirmed absence, not a cleanup failure.
        if (error.osError?.errorCode == 2 || error.osError?.errorCode == 3) {
          return;
        }
      } catch (_) {
        // An unexpected filesystem adapter failure is still retained capacity.
      }
      try {
        retainedBytes = await file.length();
      } catch (_) {
        // If even measurement fails, conservatively retain the reserved size.
      }
      // Business SQL has rolled back, while the outer transaction still owns
      // the global lock. Keep orphan bytes charged until confirmed removal.
      await rollbackTx.query(
          'UPDATE storage_usage SET stored_bytes=stored_bytes+@bytes WHERE singleton=1',
          {'bytes': retainedBytes});
    });
    await file.writeAsBytes(bytes, flush: true);
    if (await file.length() != bytes.length) {
      throw const FileSystemException('Stored file length mismatch');
    }
    await tx.query(
        'INSERT INTO stored_files(id,owner_id,asset_id,storage_key,kind,byte_length,mime,checksum) VALUES(@id,@owner,@asset,@key,@kind,@bytes,@mime,@checksum)',
        {
          'id': id,
          'owner': owner,
          'asset': asset,
          'key': key,
          'kind': kind,
          'bytes': bytes.length,
          'mime': mime,
          'checksum': sha256.convert(bytes).toString()
        });
    await tx.query(
        'UPDATE storage_usage SET reserved_bytes=reserved_bytes-@bytes,stored_bytes=stored_bytes+@bytes WHERE singleton=1',
        {'bytes': bytes.length});
    return {'id': id, 'byteLength': bytes.length, 'mime': mime};
  }

  Future<Json> upload(
      Identity user, String id, Uint8List bytes, String mime) async {
    if (bytes.isEmpty || bytes.length > maxUploadBytes) {
      fail(422, 'imageSize', 'Slika može imati najviše 10 MB.');
    }
    if (!validImage(bytes, mime)) {
      fail(422, 'invalidImage', 'Podržane su ispravne PNG i JPEG slike.');
    }
    final reservation = await db.transaction((tx) async {
      await owned(tx, user, id);
      return reserveTransfer(tx, bytes.length);
    });
    try {
      return await db.transaction((tx) async {
        final asset = await owned(tx, user, id);
        if (!['draft', 'failed'].contains(asset.lifecycle.name)) {
          fail(409, 'cannotUpload', 'Ulaz menjajte pre generisanja.');
        }
        final stored =
            await persistFile(tx, user.id, id, 'source', bytes, mime);
        final json = asset.toJson()
          ..['sourceImageFileId'] = stored['id']
          ..['revision'] = asset.revision + 1
          ..['updatedAt'] = now.toIso8601String();
        await saveAsset(tx, json);
        return {'asset': json, 'file': stored};
      });
    } finally {
      await finishTransfer(reservation, bytes.length);
    }
  }

  static bool validImage(List<int> bytes, String mime) {
    if (bytes.length > maxUploadBytes) return false;
    final input = Uint8List.fromList(bytes);
    try {
      if (mime == 'image/png') {
        if (bytes.length < 24 ||
            bytes.take(8).join(',') != '137,80,78,71,13,10,26,10') {
          return false;
        }
        final width = _read32(bytes, 16), height = _read32(bytes, 20);
        if (width < 1 ||
            height < 1 ||
            width > 8192 ||
            height > 8192 ||
            width * height > 16000000) {
          return false;
        }
        return image.decodePng(input) != null;
      }
      if (mime == 'image/jpeg') {
        final decoder = image.JpegDecoder();
        final info = decoder.startDecode(input);
        if (info == null ||
            info.width < 1 ||
            info.height < 1 ||
            info.width > 8192 ||
            info.height > 8192 ||
            info.width * info.height > 16000000) {
          return false;
        }
        return decoder.decodeFrame(0) != null;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static int _read32(List<int> b, int offset) =>
      (b[offset] << 24) |
      (b[offset + 1] << 16) |
      (b[offset + 2] << 8) |
      b[offset + 3];
  Future<Json> fileInfo(Identity? user, String id,
          {String? slug, String? kind}) =>
      db.transaction((tx) async {
        Json? row;
        if (slug != null) {
          final publication = await tx.one(
              "SELECT s.* FROM publication_submissions s JOIN assets a ON a.id=s.asset_id WHERE s.slug=@slug AND s.status='approved' AND a.deleted_at IS NULL",
              {'slug': slug});
          if (publication == null) {
            fail(404, 'notFound', 'Model nije pronađen.');
          }
          final snap = jsonMap(publication['snapshot']);
          if (kind == 'model' &&
              (snap['allowDownload'] != true ||
                  snap['license'] == 'allRightsReserved')) {
            fail(403, 'downloadDisabled', 'Autor nije omogućio preuzimanje.');
          }
          final fileId =
              kind == 'model' ? snap['outputFileId'] : snap['previewFileId'];
          row = await tx.one(
              'SELECT f.* FROM stored_files f WHERE id=@id AND deleted_at IS NULL',
              {'id': fileId});
        } else {
          row = await tx.one(
              'SELECT f.* FROM stored_files f JOIN assets a ON a.id=f.asset_id WHERE f.id=@id AND f.deleted_at IS NULL AND a.deleted_at IS NULL',
              {'id': id});
          if (row != null && row['owner_id'] != user?.id) {
            if (user == null ||
                !['moderator', 'admin'].contains(user.role) ||
                await tx.one(
                        "SELECT id FROM publication_submissions WHERE asset_id=@asset AND (snapshot->>'outputFileId'=@file OR snapshot->>'previewFileId'=@file)",
                        {'asset': row['asset_id'], 'file': row['id']}) ==
                    null) {
              row = null;
            }
          }
        }
        if (row == null) fail(404, 'fileNotFound', 'Fajl nije pronađen.');
        return row;
      });
  Future<Json> deleteAsset(Identity user, String id, Json input) async {
    await db.transaction((tx) async {
      final row = await tx.one(
          'SELECT data,deleted_at FROM assets WHERE id=@id AND owner_id=@owner',
          {'id': id, 'owner': user.id});
      if (row == null) fail(404, 'assetNotFound', 'Model nije pronađen.');
      if (row['deleted_at'] != null) return;
      final asset = Asset.fromJson(jsonMap(row['data']));
      _revision(asset.revision, input);
      if (await tx.one(
              "SELECT id FROM generation_jobs WHERE asset_id=@id AND status IN ('queued','running')",
              {'id': id}) !=
          null) {
        fail(409, 'activeJob', 'Sačekajte završetak aktivnog zahteva.');
      }
      await tx.query('UPDATE assets SET deleted_at=@now WHERE id=@id',
          {'now': now, 'id': id});
      await tx.query(
          "UPDATE publication_submissions SET status='unpublished' WHERE asset_id=@id AND status IN ('approved','pending_review')",
          {'id': id});
    });
    // The tombstone and unpublication commit BEFORE any external I/O. A file
    // cleanup failure cannot resurrect an asset whose first file is gone.
    try {
      await cleanupDeletedFiles(assetId: id);
      return {'deleted': true, 'cleanupPending': false};
    } catch (_) {
      return {'deleted': true, 'cleanupPending': true};
    }
  }

  Future<void> cleanupDeletedFiles({String? assetId}) async {
    final files = await db.transaction((tx) => tx.query(
        'SELECT f.id FROM stored_files f JOIN assets a ON a.id=f.asset_id WHERE a.deleted_at IS NOT NULL AND f.deleted_at IS NULL AND (@asset::text IS NULL OR a.id=@asset)',
        {'asset': assetId}));
    for (final selected in files) {
      await db.transaction((tx) async {
        final stored = await tx.one(
            'SELECT * FROM stored_files WHERE id=@id AND deleted_at IS NULL',
            {'id': selected['id']});
        if (stored == null) return;
        final file = File(
            '$storagePath${Platform.pathSeparator}${stored['storage_key']}');
        if (await file.exists()) {
          if (fileRemover != null) {
            await fileRemover!(file);
          } else {
            await file.delete();
          }
        }
        if (await file.exists()) {
          fail(500, 'cleanupFailed', 'Brisanje fajla nije potvrđeno.');
        }
        await tx.query('UPDATE stored_files SET deleted_at=@now WHERE id=@id',
            {'now': now, 'id': stored['id']});
        await tx.query(
            'UPDATE storage_usage SET stored_bytes=stored_bytes-@bytes WHERE singleton=1',
            {'bytes': stored['byte_length']});
      });
    }
  }
}

String text(Json input, String key, {String? fallback}) {
  final value = input[key];
  if (value == null && fallback != null) return fallback;
  if (value is! String) {
    throw ApiFailure(422, 'invalidField', 'Polje $key mora biti tekst.');
  }
  return value;
}
