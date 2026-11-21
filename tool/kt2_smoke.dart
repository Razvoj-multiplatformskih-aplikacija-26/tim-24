import 'dart:convert';
import 'dart:io';

import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:http/http.dart' as http;

/// KT2 acceptance against an isolated Compose instance. Never runs paid models.
///
/// dart run tool/kt2_smoke.dart http://127.0.0.1:19180
/// dart run tool/kt2_smoke.dart http://127.0.0.1:19181 \
///   --expiry-only --expiry-wait-seconds=4
///
/// The second command requires a separate server with access/refresh TTLs below
/// four seconds. Normal runs preserve seeded records and delete only records
/// created by this run. Credentials may be overridden with SMOKE_* environment
/// variables; credentials and tokens are never included in the output.
Future<void> main(List<String> args) async {
  final env = Platform.environment;
  final positional = args.where((arg) => !arg.startsWith('--')).toList();
  final base =
      (positional.firstOrNull ??
              env['SMOKE_API_URL'] ??
              'http://127.0.0.1:8080')
          .replaceAll(RegExp(r'/+$'), '');
  final waitOption = args
      .where((arg) => arg.startsWith('--expiry-wait-seconds='))
      .firstOrNull;
  final expiryWait = int.tryParse(waitOption?.split('=').last ?? '0') ?? 0;
  final expiryOnly = args.contains('--expiry-only');
  final run = _Acceptance(base, env);
  try {
    await run.execute(
      expiryOnly: expiryOnly,
      expiryWait: Duration(seconds: expiryWait),
    );
  } on _CheckFailure catch (error) {
    run.failure = error.label;
    exitCode = 1;
  } catch (error) {
    // A thrown HTTP response/session must never expose credentials in logs.
    run.failure = 'Unexpected ${error.runtimeType}; inspect server logs.';
    exitCode = 1;
  } finally {
    await run.close();
    stdout.writeln(const JsonEncoder.withIndent('  ').convert(run.report));
  }
}

class _Acceptance {
  _Acceptance(this.base, this.env)
    : creator = HedrionApiClient(base),
      creatorSecondSession = HedrionApiClient(base),
      otherCreator = HedrionApiClient(base),
      moderator = HedrionApiClient(base, browserScope: 'backoffice'),
      raw = _RawApi(base);

  final String base;
  final Map<String, String> env;
  final HedrionApiClient creator, creatorSecondSession, otherCreator, moderator;
  final _RawApi raw;
  final _clock = Stopwatch()..start();
  final List<Map<String, Object?>> checks = [];
  final List<String> createdIds = [], deletedIds = [], cleanupFailedIds = [];
  final String stamp = DateTime.now().microsecondsSinceEpoch.toString();
  String? failure;
  String? observedProvider;

  String get creatorEmail =>
      env['SMOKE_CREATOR_EMAIL'] ?? 'creator1@hedrion.test';
  String get creatorPassword =>
      env['SMOKE_CREATOR_PASSWORD'] ?? 'HedrionCreator123!';
  String get origin => env['SMOKE_ORIGIN'] ?? 'http://localhost:8082';
  Map<String, Object?> get report => {
    'status': failure == null ? 'passed' : 'failed',
    'apiUrl': base,
    'elapsedMs': _clock.elapsedMilliseconds,
    'provider': observedProvider,
    'paidGenerations': 0,
    'checks': checks,
    if (failure != null) 'failure': failure,
    'createdAssetIds': createdIds,
    'deletedAssetIds': deletedIds,
    'cleanupFailedAssetIds': cleanupFailedIds,
  };

  void check(String label, bool condition, [Map<String, Object?>? details]) {
    checks.add({
      'check': label,
      'status': condition ? 'passed' : 'failed',
      'details': ?details,
    });
    if (!condition) throw _CheckFailure(label);
  }

  Future<void> execute({
    required bool expiryOnly,
    required Duration expiryWait,
  }) async {
    final health = await raw.send('GET', '/health');
    check('HTTP health', health.status == 200 && health.json['status'] == 'ok');
    final framework = health.json['framework'];
    if (framework != null) {
      check(
        'Relic 1.2.0 HTTP boundary',
        framework.toString().toLowerCase() == 'relic' &&
            (health.json['frameworkVersion'] ?? health.json['relicVersion']) ==
                '1.2.0',
      );
    }
    final capabilities = await raw.send('GET', '/api/v1/capabilities');
    observedProvider = capabilities.json['provider'] as String?;
    check(
      'Safety gate: deterministic fake provider; no paid generation',
      capabilities.status == 200 && capabilities.json['provider'] == 'fake',
    );
    if (expiryOnly) {
      check(
        'Short-session expiry wait configured (1–60 seconds)',
        expiryWait.inSeconds >= 1 && expiryWait.inSeconds <= 60,
      );
      await _expiry(expiryWait);
      return;
    }

    await creator.login(creatorEmail, creatorPassword);
    await creatorSecondSession.login(creatorEmail, creatorPassword);
    await otherCreator.login(
      env['SMOKE_SECOND_CREATOR_EMAIL'] ?? 'creator2@hedrion.test',
      env['SMOKE_SECOND_CREATOR_PASSWORD'] ?? 'HedrionCreator123!',
    );
    await moderator.login(
      env['SMOKE_MODERATOR_EMAIL'] ?? 'moderator@hedrion.test',
      env['SMOKE_MODERATOR_PASSWORD'] ?? 'HedrionModerator123!',
    );
    raw.token = creator.token;
    check(
      'Seeded creator and moderator identities are server-issued',
      creator.user?['role'] == 'creator' &&
          otherCreator.user?['role'] == 'creator' &&
          creator.user?['id'] != otherCreator.user?['id'] &&
          moderator.user?['role'] == 'moderator',
    );

    final firstAssets = await ApiAssetRepository(creator).loadAssets();
    final secondAssets = await ApiAssetRepository(otherCreator).loadAssets();
    final allAssets = [...firstAssets, ...secondAssets];
    check(
      'Startup seed: at least ten assets and all lifecycle states',
      allAssets.length >= 10 &&
          AssetLifecycle.values.every(
            (state) => allAssets.any((asset) => asset.lifecycle == state),
          ),
      {
        'assetCount': allAssets.length,
        'creatorCount': 2,
        'states':
            allAssets.map((asset) => asset.lifecycle.name).toSet().toList()
              ..sort(),
      },
    );
    check(
      'Private assets are scoped to authenticated owner',
      firstAssets.every(
            (asset) => asset.ownerId.value == creator.user?['id'],
          ) &&
          secondAssets.every(
            (asset) => asset.ownerId.value == otherCreator.user?['id'],
          ),
    );
    await _pagination(firstAssets.length);
    await _wrongRole();
    await _invalidTitle();

    final approval = await _generatedDraft('Owl robot');
    await _foreignWrites(approval);
    await _publicationRuleParity(approval);
    await _publishAndModerate(approval, approve: true);
    final rejection = await _generatedDraft('Tiny coffee machine');
    await _publishAndModerate(rejection, approve: false);
    await _cookieLogout();
    await _unavailable();
    if (expiryWait > Duration.zero) await _expiry(expiryWait);
    checks.add({
      'check': 'Native restart and expiry UI',
      'status': 'manual',
      'details': 'Use the platform acceptance checklist; HTTP smoke has no UI.',
    });
  }

  Future<void> _pagination(int expectedCount) async {
    final ids = <String>{};
    final cursors = <String>{};
    String? cursor;
    var pages = 0;
    do {
      final page = await creator.request(
        'GET',
        '/api/v1/assets?limit=2${cursor == null ? '' : '&cursor=${Uri.encodeQueryComponent(cursor)}'}',
      );
      final values = page['assets'] as List;
      check(
        'Cursor page ${++pages} has at most two assets',
        values.length <= 2,
      );
      for (final item in values.cast<Map>()) {
        check('Cursor never repeats an asset', ids.add(item['id'] as String));
      }
      cursor = page['nextCursor'] as String?;
      if (cursor != null) {
        check('Pagination cursor advances', cursors.add(cursor));
      }
    } while (cursor != null);
    check(
      'Pagination visits the complete private library',
      ids.length == expectedCount && pages > 1,
      {'pages': pages, 'assetCount': ids.length},
    );
  }

  Future<void> _wrongRole() async {
    final response = await raw.send(
      'POST',
      '/api/v1/auth/login',
      body: {
        'email': creatorEmail,
        'password': creatorPassword,
        'browserSessionScope': 'backoffice',
      },
    );
    check(
      'Backoffice login rejects creator with a meaningful role error',
      response.status == 403 &&
          response.json['code'] == ErrorCode.backofficeRoleRequired.name,
    );
  }

  Future<void> _invalidTitle() async {
    final invalidTitle = List.filled(100, 'x').join();
    final local = validateTitle(invalidTitle).error!;
    final response = await raw.send(
      'POST',
      '/api/v1/assets',
      body: {'title': invalidTitle},
    );
    check(
      'Raw HTTP title violation uses shared domain code and rule data',
      response.status == 422 &&
          response.json['code'] == local.code.name &&
          response.json['details'] is Map &&
          (response.json['details'] as Map)['minLength'] is int &&
          (response.json['details'] as Map)['maxLength'] is int,
    );
    DomainError? received;
    try {
      await creator.request(
        'POST',
        '/api/v1/assets',
        body: {'title': invalidTitle},
      );
    } on DomainException catch (error) {
      received = error.error;
    }
    check(
      'Common client renders server rule parameters as a local message',
      received?.code == local.code &&
          received?.message ==
              DomainError(local.code, response.json['details']).message &&
          received?.details is Map,
    );
  }

  Future<Asset> _generatedDraft(String subject) async {
    final repo = ApiAssetRepository(creator);
    final draft = await repo.createAsset(
      AssetDraft(
        title: 'KT2 smoke $subject $stamp',
        description: 'Isolated deterministic KT2 acceptance artifact.',
      ),
    );
    createdIds.add(draft.id.value);
    check(
      'A second session sees newly created $subject after refresh',
      (await ApiAssetRepository(
        creatorSecondSession,
      ).loadAssets()).any((asset) => asset.id == draft.id),
    );
    final key = 'kt2-$stamp-${draft.id.value}';
    final accepted = await creator.generate(
      draft.id,
      baseRevision: draft.revision,
      idempotencyKey: key,
      inputType: 'text_to_3d',
      sourcePrompt: 'A low-poly $subject, isolated, game prop.',
      modelProvider: 'fake',
    );
    final replay = await creator.generate(
      draft.id,
      baseRevision: draft.revision,
      idempotencyKey: key,
      inputType: 'text_to_3d',
      sourcePrompt: 'A low-poly $subject, isolated, game prop.',
      modelProvider: 'fake',
    );
    check(
      'Idempotent generation retry returns the same $subject job',
      (accepted['job'] as Map)['id'] == (replay['job'] as Map)['id'],
    );
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    Asset current = draft;
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      current = (await ApiAssetRepository(
        creatorSecondSession,
      ).loadAssets()).firstWhere((asset) => asset.id == draft.id);
      if (current.lifecycle == AssetLifecycle.ready ||
          current.lifecycle == AssetLifecycle.failed) {
        break;
      }
    }
    check(
      'Fake worker persists $subject output and reaches ready',
      current.lifecycle == AssetLifecycle.ready && current.hasOutput,
    );
    final glb = await creatorSecondSession.download(current);
    check(
      'Authenticated $subject download is a complete GLB',
      glb.length > 20 && String.fromCharCodes(glb.take(4)) == 'glTF',
      {'bytes': glb.length},
    );
    final preview = await creatorSecondSession.fetchPreview(current);
    check(
      'Authenticated $subject preview contains actual image bytes',
      preview.length > 8 && preview[0] == 0x89 && preview[1] == 0x50,
    );
    return current;
  }

  Future<void> _foreignWrites(Asset asset) async {
    final stranger = _RawApi(base)..token = otherCreator.token;
    try {
      final update = await stranger.send(
        'PATCH',
        '/api/v1/assets/${asset.id.value}',
        body: {'baseRevision': asset.revision, 'title': 'Foreign write'},
      );
      final deletion = await stranger.send(
        'DELETE',
        '/api/v1/assets/${asset.id.value}',
        body: {'baseRevision': asset.revision},
      );
      check(
        'Raw foreign-owner update and delete are rejected',
        update.status == 404 && deletion.status == 404,
      );
      final own = await creator.request(
        'GET',
        '/api/v1/assets/${asset.id.value}',
      );
      check(
        'Rejected foreign writes leave the owner asset unchanged',
        own['revision'] == asset.revision && own['title'] == asset.title,
      );
    } finally {
      stranger.close();
    }
  }

  Future<void> _publicationRuleParity(Asset asset) async {
    final local = validatePublicationLicense(
      AssetLicense.allRightsReserved,
      allowDownload: true,
      confirmRights: false,
    ).error!;
    final denied = await raw.send(
      'POST',
      '/api/v1/assets/${asset.id.value}/submissions',
      headers: {'Idempotency-Key': 'kt2-invalid-publication-$stamp'},
      body: {
        'baseRevision': asset.revision,
        'license': 'allRightsReserved',
        'allowDownload': true,
        'confirmRights': false,
      },
    );
    check(
      'Publication validation uses the same local and raw HTTP rule code',
      denied.status == 422 && denied.json['code'] == local.code.name,
    );
  }

  Future<void> _publishAndModerate(Asset asset, {required bool approve}) async {
    final action = approve ? 'approve' : 'reject';
    final submitted = await creator.request(
      'POST',
      '/api/v1/assets/${asset.id.value}/submissions',
      key: 'kt2-submit-${asset.id.value}-$stamp',
      body: {
        'baseRevision': asset.revision,
        'license': 'ccBy',
        'allowDownload': true,
        'confirmRights': true,
      },
    );
    final submission = submitted['submission'] as Map;
    final id = submission['id'] as String;
    final localForbidden = validateModerationAccess(
      Actor(id: UserId(creator.user!['id'] as String), role: UserRole.creator),
    ).error!;
    for (final illegalAction in ['approve', 'reject']) {
      final denied = await raw.send(
        'POST',
        '/api/v1/moderation/submissions/$id/$illegalAction',
        headers: {
          'Idempotency-Key': 'kt2-denied-$illegalAction-${asset.id.value}',
        },
        body: {'baseRevision': 1, 'reason': 'Raw creator attack'},
      );
      check(
        'Creator raw $illegalAction is denied by the shared role rule',
        denied.status == 403 && denied.json['code'] == localForbidden.code.name,
      );
    }
    final moderatorRepo = ApiAssetRepository(moderator, moderator: true);
    final pending = (await moderatorRepo.loadAssets()).firstWhere(
      (candidate) => candidate.id == asset.id,
    );
    check(
      'Creator submission appears on moderator refresh',
      pending.lifecycle == AssetLifecycle.pendingReview,
    );
    await moderatorRepo.transitionAsset(
      asset.id,
      approve ? AssetLifecycle.published : AssetLifecycle.rejected,
      baseRevision: pending.revision,
      reason: approve ? null : 'KT2 test: improve model topology.',
      idempotencyKey: 'kt2-$action-${asset.id.value}-$stamp',
    );
    final fresh = (await ApiAssetRepository(
      creatorSecondSession,
    ).loadAssets()).firstWhere((candidate) => candidate.id == asset.id);
    check(
      'Moderator $action becomes visible in creator after refresh',
      fresh.lifecycle ==
          (approve ? AssetLifecycle.published : AssetLifecycle.rejected),
    );
    if (!approve) {
      check(
        'Rejected publication retains private output and reviewer reason',
        fresh.hasOutput && fresh.rejectionReason?.isNotEmpty == true,
      );
    }
    final stale = await _asModerator(
      '/api/v1/moderation/submissions/$id/$action',
      {'baseRevision': 1, 'reason': 'Stale reviewer'},
      'kt2-stale-${asset.id.value}-$stamp',
    );
    check(
      'Stale moderator cannot overwrite reviewed submission',
      stale.status == 409,
    );
    final slug = submission['slug'] as String;
    final publicDetail = await raw.send('GET', '/api/v1/public/assets/$slug');
    check(
      approve
          ? 'Approved snapshot becomes public'
          : 'Rejected snapshot stays private',
      publicDetail.status == (approve ? 200 : 404),
    );
  }

  Future<_RawResponse> _asModerator(
    String path,
    Map<String, Object?> body,
    String key,
  ) async {
    final reviewer = _RawApi(base)..token = moderator.token;
    try {
      return await reviewer.send(
        'POST',
        path,
        body: body,
        headers: {'Idempotency-Key': key},
      );
    } finally {
      reviewer.close();
    }
  }

  Future<void> _cookieLogout() async {
    final browser = _RawApi(base);
    try {
      final login = await browser.send(
        'POST',
        '/api/v1/auth/login',
        body: {
          'email': creatorEmail,
          'password': creatorPassword,
          'browserSession': true,
          'browserSessionScope': 'studio',
        },
        headers: {'Origin': origin},
      );
      final cookie = login.headers['set-cookie']?.split(';').first;
      check(
        'Browser session uses an HttpOnly refresh cookie without JSON refresh token',
        login.status == 200 &&
            cookie != null &&
            login.headers['set-cookie']!.toLowerCase().contains('httponly') &&
            login.json['refreshToken'] == null,
      );
      final logout = await browser.send(
        'POST',
        '/api/v1/auth/logout',
        body: {'browserSession': true, 'browserSessionScope': 'studio'},
        headers: {
          'Origin': origin,
          'Cookie': cookie!,
          'Authorization': 'Bearer expired-or-invalid-access-for-kt2-smoke',
        },
      );
      check(
        'Logout clears refresh cookie even with expired or invalid access token',
        logout.status == 200 &&
            logout.headers['set-cookie']!.toLowerCase().contains('max-age=0'),
      );
      final revoked = await browser.send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'browserSession': true, 'browserSessionScope': 'studio'},
        headers: {'Origin': origin, 'Cookie': cookie},
      );
      check(
        'Logged-out browser refresh cannot log back in',
        revoked.status == 401,
      );
    } finally {
      browser.close();
    }
  }

  Future<void> _expiry(Duration wait) async {
    final session = _RawApi(base);
    try {
      final login = await session.send(
        'POST',
        '/api/v1/auth/login',
        body: {'email': creatorEmail, 'password': creatorPassword},
      );
      check('Short-TTL session login', login.status == 200);
      session.token = login.json['token'] as String;
      final refresh = login.json['refreshToken'] as String;
      await Future<void>.delayed(wait);
      final expired = await session.send('GET', '/api/v1/me');
      check(
        'Access session expires according to server configuration',
        expired.status == 401 && expired.json['code'] == 'sessionExpired',
      );
      final expiredRefresh = await session.send(
        'POST',
        '/api/v1/auth/refresh',
        body: {'refreshToken': refresh},
      );
      check(
        'Refresh session also expires according to server configuration',
        expiredRefresh.status == 401,
      );
      final oldClient = HedrionApiClient(base)
        ..token = session.token
        ..refreshToken = refresh;
      try {
        DomainError? error;
        try {
          await oldClient.me();
        } on DomainException catch (caught) {
          error = caught.error;
        }
        check(
          'Expired session becomes a user-facing shared client error',
          error?.code == ErrorCode.sessionExpired &&
              error?.message ==
                  const DomainError(ErrorCode.sessionExpired).message,
        );
      } finally {
        oldClient.close();
      }
    } finally {
      session.close();
    }
  }

  Future<void> _unavailable() async {
    final unused = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = unused.port;
    await unused.close();
    final unavailable = HedrionApiClient('http://127.0.0.1:$port');
    final elapsed = Stopwatch()..start();
    DomainError? error;
    try {
      await unavailable.me();
    } on DomainException catch (caught) {
      error = caught.error;
    } finally {
      unavailable.close();
    }
    check(
      'Unavailable server returns a bounded friendly client error',
      error?.code == ErrorCode.unavailable && elapsed.elapsed.inSeconds < 10,
      {'elapsedMs': elapsed.elapsedMilliseconds},
    );
  }

  Future<void> close() async {
    for (final id in createdIds.reversed) {
      try {
        final current = (await ApiAssetRepository(
          creator,
        ).loadAssets()).firstWhere((asset) => asset.id.value == id);
        await ApiAssetRepository(
          creator,
        ).deleteAsset(current.id, current.revision);
        deletedIds.add(id);
      } catch (_) {
        cleanupFailedIds.add(id);
      }
    }
    if (cleanupFailedIds.isNotEmpty) {
      failure ??= 'Smoke asset cleanup incomplete; see cleanupFailedAssetIds.';
      exitCode = 1;
    }
    creator.close();
    creatorSecondSession.close();
    otherCreator.close();
    moderator.close();
    raw.close();
  }
}

class _RawApi {
  _RawApi(this.base);
  final String base;
  final http.Client _client = http.Client();
  String? token;

  Future<_RawResponse> send(
    String method,
    String path, {
    Map<String, Object?>? body,
    Map<String, String> headers = const {},
  }) async {
    final request = http.Request(method, Uri.parse('$base$path'));
    request.headers.addAll({
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      ...headers,
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Response.fromStream(
      await _client.send(request).timeout(const Duration(seconds: 30)),
    );
    return _RawResponse(
      response.statusCode,
      response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>,
      response.headers,
    );
  }

  void close() => _client.close();
}

class _RawResponse {
  const _RawResponse(this.status, this.json, this.headers);
  final int status;
  final Map<String, dynamic> json;
  final Map<String, String> headers;
}

class _CheckFailure implements Exception {
  const _CheckFailure(this.label);
  final String label;
}
