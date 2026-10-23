import 'package:domain/domain.dart';

/// Independent local data for KT1, never the creator app's store.
final class MemoryModerationRepository implements AssetRepository {
  MemoryModerationRepository({
    this.latency = const Duration(milliseconds: 400),
  }) {
    reset();
  }
  static const actor = Actor(
    id: UserId('moderator-demo'),
    role: UserRole.moderator,
  );
  final Duration latency;
  late List<Asset> _assets;
  bool failNext = false;
  final Map<String, Asset> _replays = {};
  void reset() {
    _assets = seedAssets(ownerId: const UserId('submitted-creator'), count: 32);
    _replays.clear();
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

  @override
  Future<List<Asset>> loadAssets() async {
    await _delay();
    return List.unmodifiable(_assets);
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
      return _replays[idempotencyKey]!;
    }
    final index = _assets.indexWhere((a) => a.id == id);
    if (index < 0) {
      throw const DomainException(DomainError(ErrorCode.notFound));
    }
    final previous = _assets[index];
    if (previous.revision != baseRevision) {
      throw const DomainException(DomainError(ErrorCode.revisionConflict));
    }
    validateTransition(previous, target, actor, reason: reason).orThrow;
    final result = previous.copyWith(
      lifecycle: target,
      rejectionReason: reason,
      revision: previous.revision + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    _assets[index] = result;
    if (idempotencyKey != null) {
      _replays[idempotencyKey] = result;
    }
    return result;
  }

  @override
  Future<Asset> createAsset(AssetDraft draft) async =>
      throw const DomainException(DomainError(ErrorCode.forbidden));
  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) async =>
      throw const DomainException(DomainError(ErrorCode.forbidden));
  @override
  Future<void> deleteAsset(AssetId id, int baseRevision) async =>
      throw const DomainException(DomainError(ErrorCode.forbidden));
}
