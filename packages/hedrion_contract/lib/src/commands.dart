import 'json.dart';

final class RevisionRequestDto {
  const RevisionRequestDto({required this.baseRevision});
  final int baseRevision;
  factory RevisionRequestDto.fromJson(JsonObject json) => RevisionRequestDto(
    baseRevision: integer(json, 'baseRevision', fallback: 0),
  );
  JsonObject toJson() => {'baseRevision': baseRevision};
}

final class AssetTransitionDto {
  const AssetTransitionDto({
    required this.target,
    required this.baseRevision,
    this.reason,
  });
  final String target;
  final int baseRevision;
  final String? reason;
  factory AssetTransitionDto.fromJson(JsonObject json) => AssetTransitionDto(
    target: string(json, 'target'),
    baseRevision: integer(json, 'baseRevision', fallback: 0),
    reason: optionalString(json, 'reason'),
  );
  JsonObject toJson() => {
    'target': target,
    'baseRevision': baseRevision,
    if (reason != null) 'reason': reason,
  };
}

final class GenerationRequestDto {
  const GenerationRequestDto({
    required this.baseRevision,
    this.inputType = 'image_to_3d',
    this.sourcePrompt,
    this.modelProvider,
    this.seed = 42,
  });
  final int baseRevision, seed;
  final String inputType;
  final String? sourcePrompt, modelProvider;
  factory GenerationRequestDto.fromJson(JsonObject json) =>
      GenerationRequestDto(
        baseRevision: integer(json, 'baseRevision', fallback: 0),
        inputType: string(json, 'inputType', fallback: 'image_to_3d'),
        sourcePrompt: optionalString(json, 'sourcePrompt'),
        modelProvider: optionalString(json, 'modelProvider'),
        seed: integer(json, 'seed', fallback: 42),
      );
  JsonObject toJson() => {
    'baseRevision': baseRevision,
    'inputType': inputType,
    'sourcePrompt': sourcePrompt,
    if (modelProvider != null) 'modelProvider': modelProvider,
    'seed': seed,
  };
}

final class PublicationRequestDto {
  const PublicationRequestDto({
    required this.baseRevision,
    required this.license,
    required this.allowDownload,
    required this.confirmRights,
  });
  final int baseRevision;
  final String license;
  final bool allowDownload, confirmRights;
  factory PublicationRequestDto.fromJson(JsonObject json) =>
      PublicationRequestDto(
        baseRevision: integer(json, 'baseRevision', fallback: 0),
        license: string(json, 'license', fallback: 'ccBy'),
        allowDownload: boolean(json, 'allowDownload'),
        confirmRights: boolean(json, 'confirmRights'),
      );
  JsonObject toJson() => {
    'baseRevision': baseRevision,
    'license': license,
    'allowDownload': allowDownload,
    'confirmRights': confirmRights,
  };
}

final class ModerationRequestDto {
  const ModerationRequestDto({this.baseRevision, this.reason});
  final int? baseRevision;
  final String? reason;
  factory ModerationRequestDto.fromJson(JsonObject json) =>
      ModerationRequestDto(
        baseRevision: json['baseRevision'] == null
            ? null
            : integer(json, 'baseRevision'),
        reason: optionalString(json, 'reason'),
      );
  JsonObject toJson() => {
    if (baseRevision != null) 'baseRevision': baseRevision,
    if (reason != null) 'reason': reason,
  };
}

final class PageRequestDto {
  const PageRequestDto({this.cursor, this.limit = 100});
  final String? cursor;
  final int limit;
  factory PageRequestDto.fromQuery(Map<String, String> query) => PageRequestDto(
    cursor: query['cursor'],
    limit: int.tryParse(query['limit'] ?? '') ?? 100,
  );
  Map<String, String> toQuery() => {'cursor': ?cursor, 'limit': '$limit'};
}
