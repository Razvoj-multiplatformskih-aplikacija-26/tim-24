import 'dart:async';
import 'package:domain/domain.dart';

/// KT1 store. Its records never leave this creator-app instance.
final class MemoryAssetRepository
    implements AssetRepository, PublicationRepository {
  MemoryAssetRepository({
    this.latency = const Duration(milliseconds: 400),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    reset();
  }
  static const actor = Actor(
    id: UserId('creator-demo'),
    role: UserRole.creator,
  );
  final Duration latency;
  final DateTime Function() _clock;
  late List<Asset> _assets;
  late List<GenerationAdmission> _admissions;
  bool failNext = false;
  int _counter = 100;
  final Map<String, AssetId> _replays = {};
  final List<Map<String, dynamic>> projects = [];
  void demonstrateTransferQuota() => validateTransferQuota(
    transferredBytes: 950000000,
    reservedBytes: 0,
    requestedBytes: 100000000,
  ).orThrow;
  void demonstrateStorageQuota() => validateStorageQuota(
    storedBytes: 9900000000,
    reservedBytes: 0,
    requestedBytes: 200000000,
  ).orThrow;
  Map<String, dynamic> saveProject(String name, {String? id}) {
    final title = validateTitle(name).orThrow;
    if (id == null) {
      final value = <String, dynamic>{
        'id': 'project-${_counter++}',
        'name': title,
        'revision': 1,
      };
      projects.add(value);
      return value;
    }
    final i = projects.indexWhere((p) => p['id'] == id);
    final value = <String, dynamic>{
      'id': id,
      'name': title,
      'revision': (projects[i]['revision'] as int) + 1,
    };
    projects[i] = value;
    return value;
  }

  int get acceptedToday => _admissions
      .where(
        (a) =>
            a.acceptedAt.toUtc().year == _clock().toUtc().year &&
            a.acceptedAt.toUtc().month == _clock().toUtc().month &&
            a.acceptedAt.toUtc().day == _clock().toUtc().day,
      )
      .length;
  void reset() {
    _assets = seedAssets(ownerId: actor.id, now: _clock());
    _admissions = seedAdmissions(_clock(), count: 18);
    _replays.clear();
    projects.clear();
  }

  void exhaustQuota() {
    _admissions = seedAdmissions(_clock(), count: 20);
  }

  Future<void> _delay() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    if (failNext) {
      failNext = false;
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
  }

  Asset _get(AssetId id, int revision) {
    final asset = _assets.where((a) => a.id == id).firstOrNull;
    if (asset == null) {
      throw const DomainException(DomainError(ErrorCode.notFound));
    }
    if (asset.revision != revision) {
      throw const DomainException(DomainError(ErrorCode.revisionConflict));
    }
    return asset;
  }

  Asset _replace(Asset asset) {
    final i = _assets.indexWhere((a) => a.id == asset.id);
    _assets[i] = asset;
    return asset;
  }

  @override
  Future<List<Asset>> loadAssets() async {
    await _delay();
    return List.unmodifiable(_assets);
  }

  @override
  Future<Asset> createAsset(AssetDraft draft) async {
    await _delay();
    validateDraft(draft).orThrow;
    final title = validateTitle(draft.title);
    if (!title.isValid) {
      throw DomainException(title.error!);
    }
    final now = _clock().toUtc();
    final asset = Asset(
      id: AssetId('local-${_counter++}'),
      ownerId: actor.id,
      title: title.value!,
      description: draft.description,
      category: draft.category,
      projectId: draft.projectId,
      tags: draft.tags,
      lifecycle: AssetLifecycle.draft,
      createdAt: now,
      updatedAt: now,
    );
    _assets = [asset, ..._assets];
    return asset;
  }

  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) async {
    await _delay();
    final previous = _get(asset.id, baseRevision);
    if (previous.ownerId != actor.id) {
      throw const DomainException(DomainError(ErrorCode.forbidden));
    }
    validateDraft(
      AssetDraft(
        title: asset.title,
        description: asset.description,
        category: asset.category,
        tags: asset.tags,
      ),
    ).orThrow;
    final title = validateTitle(asset.title);
    if (!title.isValid) {
      throw DomainException(title.error!);
    }
    return _replace(
      previous.copyWith(
        title: title.value!,
        description: asset.description,
        favorite: asset.favorite,
        category: asset.category,
        projectId: asset.projectId,
        clearProject: asset.projectId == null,
        tags: asset.tags,
        revision: previous.revision + 1,
        updatedAt: _clock().toUtc(),
      ),
    );
  }

  @override
  Future<Asset> transitionAsset(
    AssetId id,
    AssetLifecycle target, {
    required int baseRevision,
    String? reason,
    String? idempotencyKey,
  }) async {
    await _delay();
    if (idempotencyKey != null && _replays.containsKey(idempotencyKey)) {
      return _assets.firstWhere((a) => a.id == _replays[idempotencyKey]);
    }
    final previous = _get(id, baseRevision);
    final transition = validateTransition(
      previous,
      target,
      actor,
      reason: reason,
    );
    if (!transition.isValid) {
      throw DomainException(transition.error!);
    }
    if (target == AssetLifecycle.queued) {
      final quota = validateDailyGenerationQuota(_admissions, _clock());
      if (!quota.isValid) {
        throw DomainException(quota.error!);
      }
      _admissions.add(
        GenerationAdmission(
          jobId: JobId('local-job-${_counter++}'),
          ownerId: actor.id,
          acceptedAt: _clock().toUtc(),
        ),
      );
    }
    final result = _replace(
      previous.copyWith(
        lifecycle: target,
        revision: previous.revision + 1,
        updatedAt: _clock().toUtc(),
      ),
    );
    if (idempotencyKey != null) {
      _replays[idempotencyKey] = id;
    }
    return result;
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
    await _delay();
    validatePublicationLicense(
      license,
      allowDownload: allowDownload,
      confirmRights: confirmRights,
    ).orThrow;
    if (_replays.containsKey(idempotencyKey)) {
      return _assets.firstWhere((a) => a.id == _replays[idempotencyKey]);
    }
    final previous = _get(id, baseRevision);
    validateTransition(previous, AssetLifecycle.pendingReview, actor).orThrow;
    final submitted = _replace(
      previous.copyWith(
        lifecycle: AssetLifecycle.pendingReview,
        license: license,
        allowDownload: allowDownload,
        revision: previous.revision + 1,
        updatedAt: _clock().toUtc(),
      ),
    );
    _replays[idempotencyKey] = id;
    return submitted;
  }

  @override
  Future<void> deleteAsset(AssetId id, int baseRevision) async {
    await _delay();
    final asset = _get(id, baseRevision);
    if (asset.ownerId != actor.id) {
      throw const DomainException(DomainError(ErrorCode.forbidden));
    }
    _assets.removeWhere((a) => a.id == id);
  }
}
