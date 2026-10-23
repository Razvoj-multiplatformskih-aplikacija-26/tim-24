import 'dart:convert';
import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;
import 'transport.dart' if (dart.library.js_interop) 'transport_web.dart';

final class HedrionApiClient {
  HedrionApiClient(
    String baseUrl, {
    http.Client? client,
    bool? browserSession,
    this.browserScope = 'studio',
  }) : baseUrl = baseUrl.replaceAll(RegExp(r'/+$'), ''),
       _client = client ?? createTransport(),
       useCookieRefresh = browserSession ?? browserTransport;
  final String baseUrl;
  final http.Client _client;
  final bool useCookieRefresh;
  final String browserScope;
  String? token;
  String? refreshToken;
  Map<String, dynamic>? user;
  Future<void> Function()? onSessionChanged;
  Future<void>? _refreshing;
  bool get _canRefresh => refreshToken != null || useCookieRefresh;
  Future<void> _renewSession() => _refreshing ??= refresh().whenComplete(() {
    _refreshing = null;
  });
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
      body: {
        'email': email,
        'password': password,
        if (useCookieRefresh) 'browserSession': true,
        if (useCookieRefresh) 'browserSessionScope': browserScope,
      },
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
      body: {
        'email': email,
        'password': password,
        'displayName': displayName,
        if (useCookieRefresh) 'browserSession': true,
        if (useCookieRefresh) 'browserSessionScope': browserScope,
      },
    ),
  );
  Future<void> _session(Map<String, dynamic> response) async {
    token = response['token'] as String;
    refreshToken = response['refreshToken'] as String?;
    user = response['user'] as Map<String, dynamic>;
    await onSessionChanged?.call();
  }

  Future<void> refresh() async => _session(
    await request(
      'POST',
      '/api/v1/auth/refresh',
      body: {
        if (!useCookieRefresh) 'refreshToken': refreshToken,
        if (useCookieRefresh) 'browserSession': true,
        if (useCookieRefresh) 'browserSessionScope': browserScope,
      },
    ),
  );
  Future<Map<String, dynamic>> me() async =>
      user = await request('GET', '/api/v1/me');
  Future<void> logout() async {
    try {
      await request(
        'POST',
        '/api/v1/auth/logout',
        body: {
          'refreshToken': refreshToken,
          if (useCookieRefresh) 'browserSession': true,
          if (useCookieRefresh) 'browserSessionScope': browserScope,
        },
      );
    } finally {
      token = null;
      refreshToken = null;
      user = null;
      await onSessionChanged?.call();
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
        throw DomainException(_error(response.statusCode, json));
      }
      return Asset.fromJson((json['asset'] ?? json) as Map<String, dynamic>);
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
  }) => request(
    'POST',
    '/api/v1/assets/${id.value}/generations',
    body: {
      'inputType': inputType,
      'sourcePrompt': sourcePrompt,
      'baseRevision': baseRevision,
    },
    revision: baseRevision,
    key: idempotencyKey,
  );
  Future<Uint8List> download(Asset asset) async {
    final info = await request(
      'GET',
      '/api/v1/assets/${asset.id.value}/download-url',
    );
    return fileBytes(info['url'] as String);
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

  void close() => _client.close();
}

DomainError _error(int status, Map<String, dynamic> json) {
  final code =
      (json['code'] ??
              (json['error'] is Map ? (json['error'] as Map)['code'] : null))
          ?.toString() ??
      '';
  final normalized = code.replaceAll('_', '').toLowerCase();
  final matched = ErrorCode.values
      .where((v) => v.name.toLowerCase() == normalized)
      .firstOrNull;
  return DomainError(
    matched ??
        switch (status) {
          401 => ErrorCode.unauthenticated,
          403 => ErrorCode.forbidden,
          404 => ErrorCode.notFound,
          409 => ErrorCode.revisionConflict,
          429 => ErrorCode.dailyGenerationQuotaExceeded,
          400 || 422 => ErrorCode.invalidInput,
          _ => ErrorCode.unavailable,
        },
    json['details'],
  );
}

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
      body: {
        'baseRevision': baseRevision,
        'license': license.name,
        'allowDownload': allowDownload,
        'confirmRights': confirmRights,
      },
    );
    return Asset.fromJson(json['asset'] as Map<String, dynamic>);
  }

  @override
  Future<Asset> syncAsset(
    Asset asset,
    int baseRevision, {
    required String operationId,
  }) async {
    final json = await client.request(
      'POST',
      '/api/v1/sync/operations',
      key: operationId,
      body: {
        'operations': [
          {
            'clientOperationId': operationId,
            'entityId': asset.id.value,
            'operation': 'updateAsset',
            'baseRevision': baseRevision,
            'payload': {
              'title': asset.title,
              'description': asset.description,
              'favorite': asset.favorite,
            },
          },
        ],
      },
    );
    final result =
        (json['results'] as List<dynamic>).single as Map<String, dynamic>;
    if (result['status'] != 'applied') {
      throw DomainException(
        _error(result['status'] == 'conflict' ? 409 : 422, result),
      );
    }
    return Asset.fromJson(result['asset'] as Map<String, dynamic>);
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
      for (final value in json['assets'] as List<dynamic>) {
        final asset = Asset.fromJson(Map<String, dynamic>.from(value as Map));
        assets.putIfAbsent(asset.id.value, () => asset);
      }
      if (moderator) {
        if (json['stats'] is Map) {
          stats = Map<String, dynamic>.from(json['stats'] as Map);
        }
        for (final value in json['submissions'] as List<dynamic>? ?? const []) {
          final submission = Map<String, dynamic>.from(value as Map);
          submissions.putIfAbsent(
            submission['assetId'] as String,
            () => Map.unmodifiable(submission),
          );
        }
      }
      cursor = json['nextCursor'] as String?;
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
      body: draft.toJson(),
    );
    return Asset.fromJson((json['asset'] ?? json) as Map<String, dynamic>);
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
      body: {
        'title': asset.title.trim(),
        'description': asset.description,
        'favorite': asset.favorite,
        'category': asset.category,
        'projectId': asset.projectId,
        'tags': asset.tags,
        'baseRevision': baseRevision,
      },
    );
    return Asset.fromJson((json['asset'] ?? json) as Map<String, dynamic>);
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
        body: {
          'baseRevision': baseRevision,
          'license': 'ccBy',
          'allowDownload': true,
          'confirmRights': true,
        },
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
        body: {
          'baseRevision': _submissionRevisions[id.value],
          'reason': reason,
        },
      );
    } else {
      json = await client.request(
        'POST',
        '/api/v1/assets/${id.value}/transition',
        revision: baseRevision,
        key: key,
        body: {'target': target.name, 'baseRevision': baseRevision},
      );
    }
    if (json['asset'] is Map<String, dynamic>) {
      return Asset.fromJson(json['asset'] as Map<String, dynamic>);
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
      body: {'baseRevision': baseRevision},
    );
  }
}
