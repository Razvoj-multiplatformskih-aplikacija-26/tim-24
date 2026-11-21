import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'memory_asset_repository.dart';
import 'studio_workflows.dart';

/// This composition boundary is the only place choosing local or HTTP work.
StudioWorkflows createStudioWorkflows({
  required AssetRepository repository,
  HedrionApiClient? client,
  OfflineAssetRepository? offline,
}) => client == null
    ? MemoryStudioWorkflows(repository)
    : HttpStudioWorkflows(client, repository: repository, offline: offline);

class HttpStudioWorkflows implements StudioWorkflows {
  HttpStudioWorkflows(this.client, {AssetRepository? repository, this.offline})
    : repository = repository ?? ApiAssetRepository(client);
  final HedrionApiClient client;
  final AssetRepository repository;
  final OfflineAssetRepository? offline;
  @override
  bool get supportsSamples => false;
  @override
  bool get supportsFiles => true;
  @override
  bool get supportsHistory => true;
  @override
  bool get uploadsReference => true;
  @override
  bool get queuesImageOnSubmit => true;
  @override
  bool get online => offline?.online ?? true;
  @override
  bool get canModifyCollections => online && (offline?.pendingCount ?? 0) == 0;
  @override
  void demonstrate(String command) =>
      throw const DomainException(DomainError(ErrorCode.invalidInput));
  @override
  Future<Map<String, dynamic>> capabilities() =>
      client.request('GET', '/api/v1/capabilities');
  @override
  Future<List<Map<String, dynamic>>> loadProjects() async {
    return (await client.projects())
        .map((project) => project.toJson())
        .toList();
  }

  @override
  Future<Map<String, dynamic>> saveProject(
    String name, {
    String? id,
    int? baseRevision,
  }) async => (await client.saveProject(
    name,
    id: id,
    baseRevision: baseRevision,
  )).toJson();
  @override
  Future<Asset> assignProject(Asset asset, String? projectId) async {
    if (!canModifyCollections) {
      throw const DomainException(DomainError(ErrorCode.unavailable));
    }
    return updateAsset(
      asset.copyWith(projectId: projectId, clearProject: projectId == null),
      asset.revision,
    );
  }

  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) =>
      (offline?.remote ?? repository).updateAsset(asset, baseRevision);
  @override
  Future<Asset> uploadImage(
    AssetId id,
    Uint8List bytes, {
    required String mime,
  }) => client.uploadImage(id, bytes, mime: mime);
  @override
  Future<void> generate(
    Asset asset, {
    required String idempotencyKey,
    String inputType = 'image_to_3d',
    String? sourcePrompt,
    String? modelProvider,
    int seed = 42,
  }) async {
    final config = await capabilities();
    await client.generate(
      asset.id,
      baseRevision: asset.revision,
      idempotencyKey: idempotencyKey,
      inputType: inputType,
      sourcePrompt: sourcePrompt,
      modelProvider: config['demo'] == true ? null : modelProvider,
      seed: seed,
    );
  }

  @override
  Future<Map<String, dynamic>> generationHistory(AssetId id) =>
      client.request('GET', '/api/v1/assets/${id.value}/generations');
  @override
  Future<void> cancelGeneration(String id) async {
    await client.request('POST', '/api/v1/generations/$id/cancel');
  }

  @override
  Future<Uint8List> download(Asset asset) => client.download(asset);
  @override
  Future<Uint8List> fetchPreview(Asset asset) => client.fetchPreview(asset);
}

class MemoryStudioWorkflows implements StudioWorkflows {
  MemoryStudioWorkflows(this.repository);
  final AssetRepository repository;
  final List<Map<String, dynamic>> _projects = [];
  List<Map<String, dynamic>> get _records => repository is MemoryAssetRepository
      ? (repository as MemoryAssetRepository).projects
      : _projects;
  @override
  bool get supportsSamples => true;
  @override
  bool get supportsFiles => false;
  @override
  bool get supportsHistory => false;
  @override
  bool get uploadsReference => false;
  @override
  bool get queuesImageOnSubmit => false;
  @override
  bool get online => true;
  @override
  bool get canModifyCollections => true;
  @override
  void demonstrate(String command) {
    final store = repository;
    if (store is! MemoryAssetRepository) return;
    switch (command) {
      case 'fail':
        store.failNext = true;
      case 'quota':
        store.exhaustQuota();
      case 'reset':
        store.reset();
      case 'transfer':
        store.demonstrateTransferQuota();
      case 'storage':
        store.demonstrateStorageQuota();
    }
  }

  @override
  Future<Map<String, dynamic>> capabilities() async => {
    'demo': true,
    'textTo3d': true,
    'imageTo3d': true,
    'defaultModel': 'hedrion-3d',
    'generationModels': <Object?>[],
  };
  @override
  Future<List<Map<String, dynamic>>> loadProjects() async =>
      _records.map((value) => Map<String, dynamic>.from(value)).toList();
  @override
  Future<Map<String, dynamic>> saveProject(
    String name, {
    String? id,
    int? baseRevision,
  }) async {
    validateTitle(name).orThrow;
    if (repository is MemoryAssetRepository) {
      return (repository as MemoryAssetRepository).saveProject(
        name,
        id: id,
        baseRevision: baseRevision,
      );
    }
    final previous = _records.where((item) => item['id'] == id).firstOrNull;
    final result = <String, dynamic>{
      'id': id ?? 'project-${_records.length + 1}',
      'name': name.trim(),
      'revision': (previous?['revision'] as int? ?? 0) + 1,
    };
    if (previous != null) _records.remove(previous);
    _records.add(result);
    return result;
  }

  @override
  Future<Asset> assignProject(Asset asset, String? projectId) =>
      repository.updateAsset(
        asset.copyWith(projectId: projectId, clearProject: projectId == null),
        asset.revision,
      );
  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) =>
      repository.updateAsset(asset, baseRevision);
  @override
  Future<Asset> uploadImage(
    AssetId id,
    Uint8List bytes, {
    required String mime,
  }) async =>
      (await repository.loadAssets()).firstWhere((asset) => asset.id == id);
  @override
  Future<void> generate(
    Asset asset, {
    required String idempotencyKey,
    String inputType = 'image_to_3d',
    String? sourcePrompt,
    String? modelProvider,
    int seed = 42,
  }) async {
    await repository.transitionAsset(
      asset.id,
      AssetLifecycle.queued,
      baseRevision: asset.revision,
      idempotencyKey: idempotencyKey,
    );
  }

  @override
  Future<Map<String, dynamic>> generationHistory(AssetId id) async => {
    'jobs': <Object?>[],
  };
  @override
  Future<void> cancelGeneration(String id) async =>
      throw const DomainException(DomainError(ErrorCode.invalidInput));
  @override
  Future<Uint8List> download(Asset asset) async =>
      throw const DomainException(DomainError(ErrorCode.missingOutput));
  @override
  Future<Uint8List> fetchPreview(Asset asset) => download(asset);
}
