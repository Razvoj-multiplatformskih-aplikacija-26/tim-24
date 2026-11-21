import 'dart:typed_data';
import 'package:domain/domain.dart';

/// Application operations used by the creator screens. Implementations decide
/// storage, transport and job execution; widgets only consume these operations.
abstract interface class StudioWorkflows {
  bool get supportsSamples;
  bool get supportsFiles;
  bool get supportsHistory;
  bool get uploadsReference;
  bool get queuesImageOnSubmit;
  bool get online;
  bool get canModifyCollections;
  void demonstrate(String command);
  Future<Map<String, dynamic>> capabilities();
  Future<List<Map<String, dynamic>>> loadProjects();
  Future<Map<String, dynamic>> saveProject(
    String name, {
    String? id,
    int? baseRevision,
  });
  Future<Asset> assignProject(Asset asset, String? projectId);
  Future<Asset> updateAsset(Asset asset, int baseRevision);
  Future<Asset> uploadImage(
    AssetId id,
    Uint8List bytes, {
    required String mime,
  });
  Future<void> generate(
    Asset asset, {
    required String idempotencyKey,
    String inputType = 'image_to_3d',
    String? sourcePrompt,
    String? modelProvider,
    int seed = 42,
  });
  Future<Map<String, dynamic>> generationHistory(AssetId id);
  Future<void> cancelGeneration(String id);
  Future<Uint8List> download(Asset asset);
  Future<Uint8List> fetchPreview(Asset asset);
}
