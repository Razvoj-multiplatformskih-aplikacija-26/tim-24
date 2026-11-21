import 'assets.dart';
import 'errors.dart';
import 'json.dart';

final class SyncAssetOperationDto {
  SyncAssetOperationDto({
    required this.entityId,
    required JsonObject payload,
    this.clientOperationId,
    this.idempotencyKey,
    this.baseRevision,
  }) : payload = Map.unmodifiable(payload);

  final String entityId;
  final String? clientOperationId, idempotencyKey;
  final int? baseRevision;

  /// Preserve patch key order and field presence for replay of old requests.
  final JsonObject payload;

  factory SyncAssetOperationDto.fromJson(JsonObject json) =>
      SyncAssetOperationDto(
        entityId: string(json, 'entityId'),
        clientOperationId:
            optionalString(json, 'clientOperationId') ??
            optionalString(json, 'id'),
        idempotencyKey: optionalString(json, 'idempotencyKey'),
        baseRevision: json['baseRevision'] is int
            ? json['baseRevision'] as int
            : null,
        payload: object(json['payload']),
      );

  JsonObject toJson() => {
    if (clientOperationId != null) 'clientOperationId': clientOperationId,
    'entityId': entityId,
    'operation': 'updateAsset',
    'baseRevision': baseRevision,
    'payload': payload,
    if (idempotencyKey != null) 'idempotencyKey': idempotencyKey,
  };

  JsonObject toAssetPatch() => {...payload, 'baseRevision': baseRevision};
}

final class SyncRequestDto {
  SyncRequestDto(Iterable<SyncAssetOperationDto> operations)
    : operations = List.unmodifiable(operations);

  final List<SyncAssetOperationDto> operations;

  JsonObject toJson() => {
    'operations': operations.map((operation) => operation.toJson()).toList(),
  };
}

final class SyncResultDto {
  const SyncResultDto.applied(this.clientOperationId, AssetDto value)
    : status = 'applied',
      asset = value,
      error = null;

  const SyncResultDto.rejected(
    this.clientOperationId,
    this.status,
    ApiErrorDto value,
  ) : asset = null,
      error = value;

  final String? clientOperationId;
  final String status;
  final AssetDto? asset;
  final ApiErrorDto? error;

  factory SyncResultDto.fromJson(JsonObject json) {
    final id =
        optionalString(json, 'clientOperationId') ?? optionalString(json, 'id');
    final status = string(json, 'status');
    return status == 'applied'
        ? SyncResultDto.applied(id, AssetResponseDto.fromJson(json).asset)
        : SyncResultDto.rejected(id, status, ApiErrorDto.fromJson(json));
  }

  JsonObject toJson() => {
    'id': clientOperationId,
    'clientOperationId': clientOperationId,
    'status': status,
    if (asset != null) 'asset': asset!.toJson(),
    ...?error?.toJson(),
  };
}

final class SyncResponseDto {
  SyncResponseDto(Iterable<SyncResultDto> results)
    : results = List.unmodifiable(results);

  final List<SyncResultDto> results;

  factory SyncResponseDto.fromJson(JsonObject json) =>
      SyncResponseDto(objects(json, 'results').map(SyncResultDto.fromJson));

  JsonObject toJson() => {
    'results': results.map((result) => result.toJson()).toList(),
  };
}
