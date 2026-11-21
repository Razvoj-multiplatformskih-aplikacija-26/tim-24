import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'memory_moderation_repository.dart';
import 'moderation_workflows.dart';

/// The composition boundary selects local or HTTP implementations once.
ModerationWorkflows createModerationWorkflows({
  required AssetRepository repository,
  HedrionApiClient? client,
}) => client == null
    ? MemoryModerationWorkflows(repository)
    : HttpModerationWorkflows(client, repository: repository);

final class HttpModerationWorkflows implements ModerationWorkflows {
  HttpModerationWorkflows(this.client, {required this.repository});
  final HedrionApiClient client;
  final AssetRepository repository;

  @override
  Actor get actor {
    final user = client.user;
    return Actor(
      id: UserId(user?['id'] as String? ?? ''),
      role:
          UserRole.values
              .where((role) => role.name == user?['role'])
              .firstOrNull ??
          UserRole.creator,
    );
  }

  @override
  bool get supportsSamples => false;
  @override
  bool get supportsFiles => true;
  @override
  Map<String, dynamic> get statistics => repository is ApiAssetRepository
      ? (repository as ApiAssetRepository).moderationStats
      : const {};
  @override
  Map<String, dynamic>? submissionFor(AssetId id) =>
      repository is ApiAssetRepository
      ? (repository as ApiAssetRepository).submissionsByAssetId[id.value]
      : null;
  @override
  void demonstrate(String command) =>
      throw const DomainException(DomainError(ErrorCode.unsupportedInput));
  @override
  Future<Uint8List> fetchPreview(Asset asset) => client.fetchPreview(asset);
}

final class MemoryModerationWorkflows implements ModerationWorkflows {
  MemoryModerationWorkflows(this.repository);
  final AssetRepository repository;
  @override
  Actor get actor => MemoryModerationRepository.actor;
  @override
  bool get supportsSamples => repository is MemoryModerationRepository;
  @override
  bool get supportsFiles => false;
  @override
  Map<String, dynamic> get statistics => const {};
  @override
  Map<String, dynamic>? submissionFor(AssetId id) => null;
  @override
  void demonstrate(String command) {
    final store = repository;
    if (store is! MemoryModerationRepository) {
      throw const DomainException(DomainError(ErrorCode.unsupportedInput));
    }
    switch (command) {
      case 'fail':
        store.failNext = true;
      case 'reset':
        store.reset();
      default:
        throw const DomainException(DomainError(ErrorCode.invalidInput));
    }
  }

  @override
  Future<Uint8List> fetchPreview(Asset asset) async =>
      throw const DomainException(DomainError(ErrorCode.missingOutput));
}
