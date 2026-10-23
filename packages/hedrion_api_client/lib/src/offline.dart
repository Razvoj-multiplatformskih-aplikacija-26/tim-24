import 'dart:convert';
import 'package:domain/domain.dart';
import 'client.dart';

/// Implement with an atomic SQLite transaction on Android. Store is user-scoped.
abstract interface class OfflinePersistence {
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> snapshot);
}

final class SyncConflict {
  const SyncConflict(this.local, this.server);
  final Asset local;
  final Asset server;
}

final class OfflineAssetRepository
    implements AssetRepository, PublicationRepository {
  OfflineAssetRepository(
    this.remote,
    this.persistence, {
    required this.ownerId,
  });
  final AssetRepository remote;
  final OfflinePersistence persistence;
  final UserId ownerId;
  bool online = true;
  final Map<String, Asset> _cache = {};
  final Map<String, Map<String, dynamic>> _outbox = {};
  final Map<String, SyncConflict> _conflicts = {};
  Future<void> _tail = Future.value();
  int get pendingCount => _outbox.length;
  List<SyncConflict> get conflicts => List.unmodifiable(_conflicts.values);
  Future<T> _serial<T>(Future<T> Function() operation) {
    final next = _tail.then((_) => operation());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<void> initialize() async {
    final snapshot = await persistence.read();
    if (snapshot == null || snapshot['ownerId'] != ownerId.value) return;
    for (final row in snapshot['assets'] as List<dynamic>? ?? []) {
      final asset = Asset.fromJson(row as Map<String, dynamic>);
      if (asset.ownerId == ownerId) _cache[asset.id.value] = asset;
    }
    for (final row in snapshot['outbox'] as List<dynamic>? ?? []) {
      final op = Map<String, dynamic>.from(row as Map);
      _outbox[op['entityId'] as String] = op;
      if (op['server'] is Map) {
        final id = op['entityId'] as String;
        _conflicts[id] = SyncConflict(
          _cache[id]!,
          Asset.fromJson(Map<String, dynamic>.from(op['server'] as Map)),
        );
      }
    }
  }

  Future<void> _persist() => persistence.write({
    'version': 1,
    'ownerId': ownerId.value,
    'assets': _cache.values.map((a) => a.toJson()).toList(),
    'outbox': _outbox.values.toList(),
  });

  @override
  Future<List<Asset>> loadAssets() => _serial(() async {
    if (online) {
      try {
        final fresh = await remote.loadAssets();
        final keep = _outbox.keys.toSet();
        _cache.removeWhere((id, _) => !keep.contains(id));
        for (final a in fresh.where((a) => a.ownerId == ownerId)) {
          if (!keep.contains(a.id.value)) _cache[a.id.value] = a;
        }
        await _persist();
      } on DomainException catch (e) {
        if (e.error.code != ErrorCode.unavailable) rethrow;
        online = false;
      }
    }
    return List.unmodifiable(_cache.values);
  });
  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) => _serial(() async {
    if (asset.ownerId != ownerId || !_cache.containsKey(asset.id.value)) {
      throw const DomainException(DomainError(ErrorCode.forbidden));
    }
    final cached = _cache[asset.id.value]!;
    validateDraft(
      AssetDraft(
        title: asset.title,
        description: asset.description,
        category: asset.category,
        tags: asset.tags,
      ),
    ).orThrow;
    final onlineOnlyChanged =
        asset.category != cached.category ||
        asset.projectId != cached.projectId ||
        jsonEncode(asset.tags) != jsonEncode(cached.tags);
    // Only these three fields are queued offline; online metadata edits also
    // preserve category, project and tags rather than silently dropping them.
    final edited = cached.copyWith(
      title: asset.title.trim(),
      description: asset.description,
      favorite: asset.favorite,
    );
    if (online && !_outbox.containsKey(asset.id.value)) {
      try {
        final saved = await remote.updateAsset(
          edited.copyWith(
            category: asset.category,
            projectId: asset.projectId,
            clearProject: asset.projectId == null,
            tags: asset.tags,
          ),
          baseRevision,
        );
        _cache[saved.id.value] = saved;
        await _persist();
        return saved;
      } on DomainException catch (e) {
        if (e.error.code != ErrorCode.unavailable) rethrow;
        online = false;
      }
    }
    if (onlineOnlyChanged) {
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
    _cache[asset.id.value] = edited;
    _outbox.putIfAbsent(
      asset.id.value,
      () => {
        'entityId': asset.id.value,
        'baseRevision': cached.revision,
        'clientOperationId':
            '${ownerId.value}-${asset.id.value}-${DateTime.now().microsecondsSinceEpoch}',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      },
    );
    await _persist();
    return edited;
  });

  Future<int> sync() => _serial(() async {
    if (!online) return 0;
    var applied = 0;
    for (final id in _outbox.keys.toList()) {
      if (_conflicts.containsKey(id)) continue;
      try {
        final updated = remote is SyncAssetRepository
            ? await (remote as SyncAssetRepository).syncAsset(
                _cache[id]!,
                _outbox[id]!['baseRevision'] as int,
                operationId: _outbox[id]!['clientOperationId'] as String,
              )
            : await remote.updateAsset(
                _cache[id]!,
                _outbox[id]!['baseRevision'] as int,
              );
        _cache[id] = updated;
        _outbox.remove(id);
        applied++;
        await _persist();
      } on DomainException catch (e) {
        if (e.error.code == ErrorCode.revisionConflict) {
          final server = (await remote.loadAssets())
              .where((a) => a.id.value == id)
              .firstOrNull;
          if (server == null) rethrow;
          _conflicts[id] = SyncConflict(_cache[id]!, server);
          _outbox[id]!['server'] = server.toJson();
          await _persist();
        } else if (e.error.code == ErrorCode.unavailable) {
          online = false;
          break;
        } else {
          rethrow;
        }
      }
    }
    return applied;
  });
  Future<void> resolveConflict(AssetId id, {required bool keepLocal}) =>
      _serial(() async {
        final conflict = _conflicts.remove(id.value);
        if (conflict == null) return;
        if (keepLocal) {
          _outbox[id.value]!['baseRevision'] = conflict.server.revision;
          _outbox[id.value]!.remove('server');
          _cache[id.value] = conflict.server.copyWith(
            title: conflict.local.title,
            description: conflict.local.description,
            favorite: conflict.local.favorite,
          );
        } else {
          _cache[id.value] = conflict.server;
          _outbox.remove(id.value);
        }
        await _persist();
      });
  void _requireOnline() {
    if (!online) {
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
  }

  @override
  Future<Asset> submitPublication(
    AssetId id, {
    required int baseRevision,
    required AssetLicense license,
    required bool allowDownload,
    required bool confirmRights,
    required String idempotencyKey,
  }) async {
    _requireOnline();
    if (remote is! PublicationRepository) {
      throw const DomainException(DomainError(ErrorCode.unsupportedInput));
    }
    return (remote as PublicationRepository).submitPublication(
      id,
      baseRevision: baseRevision,
      license: license,
      allowDownload: allowDownload,
      confirmRights: confirmRights,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<Asset> createAsset(AssetDraft draft) async {
    _requireOnline();
    return remote.createAsset(draft);
  }

  @override
  Future<Asset> transitionAsset(
    AssetId id,
    AssetLifecycle target, {
    required int baseRevision,
    String? reason,
    String? idempotencyKey,
  }) async {
    _requireOnline();
    return remote.transitionAsset(
      id,
      target,
      baseRevision: baseRevision,
      reason: reason,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<void> deleteAsset(AssetId id, int baseRevision) async {
    _requireOnline();
    await remote.deleteAsset(id, baseRevision);
  }
}
