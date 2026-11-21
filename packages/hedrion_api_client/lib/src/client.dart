import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:hedrion_contract/hedrion_contract.dart';
import 'package:hedrion_mapping/hedrion_mapping.dart';
import 'package:http/http.dart' as http;
import 'transport.dart' if (dart.library.js_interop) 'transport_web.dart';
import 'session.dart';

final class HedrionApiClient {
  HedrionApiClient(
    String baseUrl, {
    http.Client? client,
    bool? browserSession,
    this.browserScope = 'studio',
    this.sessionStorage,
    DateTime Function()? clock,
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? createTransport(),
       useCookieRefresh = browserSession ?? browserTransport,
       clock = clock ?? DateTime.now;
  final String baseUrl;
  final http.Client _client;
  final bool useCookieRefresh;
  final String browserScope;
  final SessionStorage? sessionStorage;
  final DateTime Function() clock;
  String? token;
  String? refreshToken;
  Map<String, dynamic>? user;
  DateTime? expiresAt, refreshExpiresAt;
  Timer? _expirationTimer;
  bool _expirationNotified = false;
  Future<void> Function()? onSessionChanged;
  Future<void> Function()? onSessionExpired;
  Future<void>? _refreshing;
  bool get _canRefresh => refreshToken != null || useCookieRefresh;
  Future<void> _renewSession() => _refreshing ??= (() async {
    try {
      await refresh();
    } on DomainException catch (e) {
      if (e.error.code == ErrorCode.unauthenticated ||
          e.error.code == ErrorCode.sessionExpired) {
        await _clearSession(expired: true);
        throw const DomainException(DomainError(ErrorCode.sessionExpired));
      }
      rethrow;
    }
  })().whenComplete(() => _refreshing = null);

  Future<void> _clearSession({bool expired = false}) async {
    if (expired && _expirationNotified) return;
    if (expired) _expirationNotified = true;
    _expirationTimer?.cancel();
    token = null;
    refreshToken = null;
    user = null;
    expiresAt = null;
    refreshExpiresAt = null;
    try {
      if (!useCookieRefresh) await sessionStorage?.clear();
    } finally {
      await onSessionChanged?.call();
      if (expired) await onSessionExpired?.call();
    }
  }

  void _scheduleExpiration() {
    _expirationTimer?.cancel();
    final deadline = refreshExpiresAt;
    if (deadline == null) return;
    final remaining = deadline.difference(clock().toUtc());
    // Chunk long waits to remain within browser timer limits. The deadline
    // always comes from the server, including after credential rotation.
    final wait = remaining > const Duration(days: 1)
        ? const Duration(days: 1)
        : remaining;
    _expirationTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (clock().toUtc().isBefore(deadline)) {
        _scheduleExpiration();
      } else {
        unawaited(_clearSession(expired: true).catchError((Object _) {}));
      }
    });
  }

  /// Restore credentials through the secure-storage port or a scoped HttpOnly
  /// browser cookie. Cached native identity also permits the offline workspace.
  Future<bool> restoreSession() async {
    if (!useCookieRefresh) {
      final saved = await sessionStorage?.read();
      if (saved == null) return false;
      token = saved.token;
      refreshToken = saved.refreshToken;
      user = Map<String, dynamic>.from(saved.user);
      expiresAt = saved.expiresAt;
      refreshExpiresAt = saved.refreshExpiresAt;
      if (refreshExpiresAt != null &&
          !clock().toUtc().isBefore(refreshExpiresAt!)) {
        await _clearSession(expired: true);
        throw const DomainException(DomainError(ErrorCode.sessionExpired));
      }
      _scheduleExpiration();
    }
    try {
      if (useCookieRefresh) {
        await refresh();
      } else {
        await me();
      }
      return true;
    } on DomainException catch (e) {
      if (_expirationNotified) {
        throw const DomainException(DomainError(ErrorCode.sessionExpired));
      }
      if (!useCookieRefresh && e.error.code == ErrorCode.unavailable) {
        return true;
      }
      if (e.error.code == ErrorCode.unauthenticated) {
        await _clearSession();
        return false;
      }
      if (e.error.code == ErrorCode.sessionExpired && user != null) {
        await _clearSession(expired: true);
      }
      rethrow;
    }
  }

  Uri uri(String path) =>
      Uri.parse('$baseUrl${path.startsWith('/') ? path : '/$path'}');

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    int? revision,
    String? key,
    bool retrySession = true,
  }) async {
    final request = http.Request(method, uri(path));
    request.headers['Content-Type'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (revision != null) request.headers['If-Match'] = '$revision';
    if (key != null) request.headers['Idempotency-Key'] = key;
    if (body != null) request.body = jsonEncode(body);
    try {
      final response = await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 30)),
      );
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 401 &&
          retrySession &&
          !path.startsWith('/api/v1/auth/') &&
          _canRefresh) {
        await _renewSession();
        return await this.request(
          method,
          path,
          body: body,
          revision: revision,
          key: key,
          retrySession: false,
        );
      }
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 &&
            !path.startsWith('/api/v1/auth/') &&
            token != null) {
          await _clearSession(expired: true);
          throw const DomainException(DomainError(ErrorCode.sessionExpired));
        }
        throw DomainException(_error(response.statusCode, decoded));
      }
      return decoded;
    } on DomainException {
      rethrow;
    } catch (_) {
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
  }

  Future<void> login(String email, String password) async => _session(
    await request(
      'POST',
      '/api/v1/auth/login',
      body: LoginRequestDto(
        email: email,
        password: password,
        browserSession: useCookieRefresh,
        browserSessionScope: browserScope,
      ).toJson(),
    ),
  );
  Future<void> register(
    String email,
    String password,
    String displayName,
  ) async => _session(
    await request(
      'POST',
      '/api/v1/auth/register',
      body: RegisterRequestDto(
        email: email,
        password: password,
        displayName: displayName,
        browserSession: useCookieRefresh,
        browserSessionScope: browserScope,
      ).toJson(),
    ),
  );
  Future<void> _session(Map<String, dynamic> response) async {
    final session = SessionDto.fromJson(response);
    if (session.refreshExpiresAt != null &&
        !clock().toUtc().isBefore(session.refreshExpiresAt!)) {
      await _clearSession(expired: true);
      throw const DomainException(DomainError(ErrorCode.sessionExpired));
    }
    _expirationNotified = false;
    token = session.token;
    refreshToken = session.refreshToken;
    user = session.user.toJson();
    expiresAt = session.expiresAt;
    refreshExpiresAt = session.refreshExpiresAt;
    _scheduleExpiration();
    if (!useCookieRefresh) {
      await sessionStorage?.write(
        StoredSession(
          token: token!,
          refreshToken: refreshToken,
          user: user!,
          expiresAt: expiresAt,
          refreshExpiresAt: refreshExpiresAt,
        ),
      );
    }
    await onSessionChanged?.call();
  }

  Future<void> refresh() async => _session(
    await request(
      'POST',
      '/api/v1/auth/refresh',
      body: RefreshRequestDto(
        refreshToken: useCookieRefresh ? null : refreshToken,
        browserSession: useCookieRefresh,
        browserSessionScope: browserScope,
      ).toJson(),
    ),
  );
  Future<Map<String, dynamic>> me() async {
    final identity = await request('GET', '/api/v1/me');
    if (token == null) {
      throw const DomainException(DomainError(ErrorCode.sessionExpired));
    }
    return user = identity;
  }

  Future<void> logout() async {
    try {
      await request(
        'POST',
        '/api/v1/auth/logout',
        body: RefreshRequestDto(
          refreshToken: useCookieRefresh ? null : refreshToken,
          browserSession: useCookieRefresh,
          browserSessionScope: browserScope,
        ).toJson(),
      );
    } finally {
      await _clearSession();
    }
  }

  Future<Asset> uploadImage(
    AssetId id,
    Uint8List bytes, {
    required String mime,
  }) => _uploadImage(id, bytes, mime: mime, retrySession: true);
  Future<Asset> _uploadImage(
    AssetId id,
    Uint8List bytes, {
    required String mime,
    required bool retrySession,
  }) async {
    try {
      final response = await _client
          .put(
            uri('/api/v1/assets/${id.value}/source'),
            headers: {
              'Content-Type': mime,
              'X-File-Length': '${bytes.length}',
              if (token != null) 'Authorization': 'Bearer $token',
            },
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Authorization is rejected by the server before accepting file data.
      // Retry only this response, once; a partial transfer or network error is
      // never retried automatically because actual bytes count toward quota.
      if (response.statusCode == 401 && retrySession && _canRefresh) {
        await _renewSession();
        return await _uploadImage(id, bytes, mime: mime, retrySession: false);
      }
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 && token != null) {
          await _clearSession(expired: true);
          throw const DomainException(DomainError(ErrorCode.sessionExpired));
        }
        throw DomainException(_error(response.statusCode, json));
      }
      return assetFromDto(UploadResultDto.fromJson(json).asset);
    } on DomainException {
      rethrow;
    } catch (_) {
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
  }

  Future<Map<String, dynamic>> generate(
    AssetId id, {
    required int baseRevision,
    required String idempotencyKey,
    String inputType = 'image_to_3d',
    String? sourcePrompt,
    String? modelProvider,
    int seed = 42,
  }) => request(
    'POST',
    '/api/v1/assets/${id.value}/generations',
    body: GenerationRequestDto(
      inputType: inputType,
      sourcePrompt: sourcePrompt,
      modelProvider: modelProvider,
      seed: seed,
      baseRevision: baseRevision,
    ).toJson(),
    revision: baseRevision,
    key: idempotencyKey,
  ).then((json) => GenerationResponseDto.fromJson(json).toJson());

  Future<GenerationCapabilitiesDto> generationCapabilities() async =>
      GenerationCapabilitiesDto.fromJson(
        await request('GET', '/api/v1/capabilities'),
      );

  Future<GenerationHistoryDto> generationHistory(AssetId id) async =>
      GenerationHistoryDto.fromJson(
        await request('GET', '/api/v1/assets/${id.value}/generations'),
      );

  Future<GenerationCancellationDto> cancelGeneration(String id) async =>
      GenerationCancellationDto.fromJson(
        await request('POST', '/api/v1/generations/$id/cancel'),
      );

  Future<List<ProjectDto>> projects() async => ProjectListDto.fromJson(
    await request('GET', '/api/v1/projects'),
  ).projects;

  Future<ProjectDto> saveProject(
    String name, {
    String? id,
    int? baseRevision,
  }) async => ProjectDto.fromJson(
    await request(
      id == null ? 'POST' : 'PATCH',
      id == null ? '/api/v1/projects' : '/api/v1/projects/$id',
      revision: baseRevision,
      body: ProjectWriteDto(
        name: name.trim(),
        baseRevision: baseRevision,
      ).toJson(),
    ),
  );

  Future<Uint8List> download(Asset asset) async {
    final info = DownloadLinkDto.fromJson(
      await request('GET', '/api/v1/assets/${asset.id.value}/download-url'),
    );
    return fileBytes(info.url);
  }

  Future<Uint8List> fetchPreview(Asset asset) async {
    if (asset.previewFileId == null) {
      throw const DomainException(DomainError(ErrorCode.missingOutput));
    }
    return fileBytes('/api/v1/files/${asset.previewFileId}');
  }

  Future<Uint8List> fileBytes(String path) =>
      _fileBytes(path, retrySession: true);
  Future<Uint8List> _fileBytes(
    String path, {
    required bool retrySession,
  }) async {
    final target = uri(path);
    if (target.origin != Uri.parse(baseUrl).origin) {
      throw const DomainException(DomainError(ErrorCode.forbidden));
    }
    try {
      final response = await _client
          .get(
            target,
            headers: {if (token != null) 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 60));
      if (response.statusCode == 401 && retrySession && _canRefresh) {
        await _renewSession();
        return await _fileBytes(path, retrySession: false);
      }
      if (response.statusCode >= 400) {
        if (response.statusCode == 401 && token != null) {
          await _clearSession(expired: true);
          throw const DomainException(DomainError(ErrorCode.sessionExpired));
        }
        throw DomainException(
          _error(
            response.statusCode,
            jsonDecode(response.body) as Map<String, dynamic>,
          ),
        );
      }
      return response.bodyBytes;
    } on DomainException {
      rethrow;
    } catch (_) {
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
  }

  void close() {
    _expirationTimer?.cancel();
    _client.close();
  }
}

DomainError _error(int status, Map<String, dynamic> json) =>
    errorFromDto(ApiErrorDto.fromJson(json), status: status);

abstract interface class SyncAssetRepository {
  Future<Asset> syncAsset(
    Asset asset,
    int baseRevision, {
    required String operationId,
  });
}

final class ApiAssetRepository
    implements AssetRepository, SyncAssetRepository, PublicationRepository {
  ApiAssetRepository(this.client, {this.moderator = false});
  final HedrionApiClient client;
  final bool moderator;
  final Map<String, String> _submissionIds = {};
  final Map<String, int> _submissionRevisions = {};
  Map<String, dynamic> moderationStats = const {};
  Map<String, Map<String, dynamic>> submissionsByAssetId = const {};
  @override
  Future<Asset> submitPublication(
    AssetId id, {
    required int baseRevision,
    required AssetLicense license,
    required bool allowDownload,
    required bool confirmRights,
    required String idempotencyKey,
  }) async {
    validatePublicationLicense(
      license,
      allowDownload: allowDownload,
      confirmRights: confirmRights,
    ).orThrow;
    final json = await client.request(
      'POST',
      '/api/v1/assets/${id.value}/submissions',
      revision: baseRevision,
      key: idempotencyKey,
      body: PublicationRequestDto(
        baseRevision: baseRevision,
        license: license.name,
        allowDownload: allowDownload,
        confirmRights: confirmRights,
      ).toJson(),
    );
    return assetFromResponse(json);
  }

  @override
  Future<Asset> syncAsset(
    Asset asset,
    int baseRevision, {
    required String operationId,
  }) async {
    final request = SyncRequestDto([
      SyncAssetOperationDto(
        clientOperationId: operationId,
        entityId: asset.id.value,
        baseRevision: baseRevision,
        payload: {
          'title': asset.title,
          'description': asset.description,
          'favorite': asset.favorite,
        },
      ),
    ]);
    final response = SyncResponseDto.fromJson(
      await client.request(
        'POST',
        '/api/v1/sync/operations',
        key: operationId,
        body: request.toJson(),
      ),
    );
    final result = response.results.singleOrNull;
    if (result == null ||
        (result.clientOperationId != null &&
            result.clientOperationId != operationId)) {
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
    final error = result.error;
    if (error != null) {
      throw DomainException(
        errorFromDto(error, status: result.status == 'conflict' ? 409 : 422),
      );
    }
    return assetFromDto(result.asset!);
  }

  @override
  Future<List<Asset>> loadAssets() async {
    final assets = <String, Asset>{},
        submissions = <String, Map<String, dynamic>>{};
    final seen = <String>{};
    Map<String, dynamic> stats = const {};
    String? cursor;
    do {
      final path = moderator
          ? '/api/v1/moderation/submissions'
          : '/api/v1/assets';
      final json = await client.request(
        'GET',
        cursor == null
            ? path
            : '$path?cursor=${Uri.encodeQueryComponent(cursor)}',
      );
      final moderationPage = moderator
          ? ModerationPageDto.fromJson(json)
          : null;
      final page = moderationPage?.page ?? AssetPageDto.fromJson(json);
      for (final value in page.assets) {
        final asset = assetFromDto(value);
        assets.putIfAbsent(asset.id.value, () => asset);
      }
      if (moderationPage != null) {
        stats = moderationPage.stats?.toJson() ?? stats;
        for (final submission in moderationPage.submissions) {
          submissions.putIfAbsent(
            submission.assetId,
            () => Map.unmodifiable(submission.toJson()),
          );
        }
      }
      cursor = page.nextCursor;
      if (cursor != null && (cursor.isEmpty || !seen.add(cursor))) {
        throw const DomainException(DomainError(ErrorCode.unavailable));
      }
    } while (cursor != null);
    // Publish metadata together with the completed asset collection; a failed
    // later page leaves the last successful view intact.
    if (moderator) {
      _submissionIds.clear();
      _submissionRevisions.clear();
      for (final entry in submissions.entries) {
        _submissionIds[entry.key] = entry.value['id'] as String;
        _submissionRevisions[entry.key] = entry.value['revision'] as int;
      }
      submissionsByAssetId = Map.unmodifiable(submissions);
      moderationStats = Map.unmodifiable(stats);
    }
    return List.unmodifiable(assets.values);
  }

  @override
  Future<Asset> createAsset(AssetDraft draft) async {
    validateDraft(draft).orThrow;
    final json = await client.request(
      'POST',
      '/api/v1/assets',
      body: draftToDto(draft).toJson(),
    );
    return assetFromResponse(json);
  }

  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) async {
    validateDraft(
      AssetDraft(
        title: asset.title,
        description: asset.description,
        category: asset.category,
        tags: asset.tags,
      ),
    ).orThrow;
    final json = await client.request(
      'PATCH',
      '/api/v1/assets/${asset.id.value}',
      revision: baseRevision,
      body: AssetUpdateDto(
        baseRevision: baseRevision,
        title: asset.title.trim(),
        description: asset.description,
        favorite: asset.favorite,
        category: asset.category,
        projectId: asset.projectId,
        hasProjectId: true,
        tags: asset.tags,
      ).toJson(),
    );
    return assetFromResponse(json);
  }

  @override
  Future<Asset> transitionAsset(
    AssetId id,
    AssetLifecycle target, {
    required int baseRevision,
    String? reason,
    String? idempotencyKey,
  }) async {
    final key = idempotencyKey ?? '${id.value}-$baseRevision-${target.name}';
    late final Map<String, dynamic> json;
    if (target == AssetLifecycle.queued) {
      json = await client.generate(
        id,
        baseRevision: baseRevision,
        idempotencyKey: key,
      );
    } else if (target == AssetLifecycle.pendingReview) {
      json = await client.request(
        'POST',
        '/api/v1/assets/${id.value}/submissions',
        revision: baseRevision,
        key: key,
        body: PublicationRequestDto(
          baseRevision: baseRevision,
          license: 'ccBy',
          allowDownload: true,
          confirmRights: true,
        ).toJson(),
      );
    } else if (target == AssetLifecycle.published ||
        target == AssetLifecycle.rejected) {
      if (!_submissionIds.containsKey(id.value)) await loadAssets();
      final submissionId = _submissionIds[id.value];
      if (submissionId == null) {
        throw const DomainException(DomainError(ErrorCode.notFound));
      }
      json = await client.request(
        'POST',
        '/api/v1/moderation/submissions/$submissionId/${target == AssetLifecycle.published ? 'approve' : 'reject'}',
        revision: _submissionRevisions[id.value],
        key: key,
        body: ModerationRequestDto(
          baseRevision: _submissionRevisions[id.value],
          reason: reason,
        ).toJson(),
      );
    } else {
      json = await client.request(
        'POST',
        '/api/v1/assets/${id.value}/transition',
        revision: baseRevision,
        key: key,
        body: AssetTransitionDto(
          target: target.name,
          baseRevision: baseRevision,
          reason: reason,
        ).toJson(),
      );
    }
    if (json['asset'] is Map<String, dynamic>) {
      return assetFromResponse(json);
    }
    final fresh = await loadAssets();
    return fresh.firstWhere((a) => a.id == id);
  }

  @override
  Future<void> deleteAsset(AssetId id, int baseRevision) async {
    await client.request(
      'DELETE',
      '/api/v1/assets/${id.value}',
      revision: baseRevision,
      body: RevisionRequestDto(baseRevision: baseRevision).toJson(),
    );
  }
}
