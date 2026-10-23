import 'models.dart';

abstract interface class AssetRepository {
  Future<List<Asset>> loadAssets();
  Future<Asset> createAsset(AssetDraft draft);
  Future<Asset> updateAsset(Asset asset, int baseRevision);
  Future<Asset> transitionAsset(
    AssetId id,
    AssetLifecycle target, {
    required int baseRevision,
    String? reason,
    String? idempotencyKey,
  });
  Future<void> deleteAsset(AssetId id, int baseRevision);
}

abstract interface class PublicationRepository {
  Future<Asset> submitPublication(
    AssetId id, {
    required int baseRevision,
    required AssetLicense license,
    required bool allowDownload,
    required bool confirmRights,
    required String idempotencyKey,
  });
}
