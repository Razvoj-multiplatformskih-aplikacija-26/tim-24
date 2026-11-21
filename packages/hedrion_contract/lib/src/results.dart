import 'assets.dart';
import 'json.dart';

/// Provider-specific timings, GPU names and output metadata remain extensible;
/// the shared job identity, lifecycle, input and output fields are typed.
final class GenerationJobDto {
  GenerationJobDto({
    required this.id,
    required this.status,
    this.assetId = '',
    this.ownerId = '',
    this.inputType = 'image_to_3d',
    this.acceptedAt,
    this.outputFileId,
    this.failureCode,
    Map<String, dynamic> metadata = const {},
  }) : metadata = Map.unmodifiable(metadata);
  final String id, status, assetId, ownerId, inputType;
  final DateTime? acceptedAt;
  final String? outputFileId, failureCode;
  final Map<String, dynamic> metadata;
  factory GenerationJobDto.fromJson(JsonObject json) => GenerationJobDto(
    id: string(json, 'id'),
    status: string(json, 'status'),
    assetId: string(json, 'assetId', fallback: ''),
    ownerId: string(json, 'ownerId', fallback: ''),
    inputType: string(json, 'inputType', fallback: 'image_to_3d'),
    acceptedAt: optionalDate(json, 'acceptedAt'),
    outputFileId: optionalString(json, 'outputFileId'),
    failureCode: optionalString(json, 'failureCode'),
    metadata: json,
  );
  JsonObject toJson() => {
    ...metadata,
    'id': id,
    'status': status,
    'assetId': assetId,
    'ownerId': ownerId,
    'inputType': inputType,
    if (acceptedAt != null) 'acceptedAt': acceptedAt!.toUtc().toIso8601String(),
    if (outputFileId != null) 'outputFileId': outputFileId,
    if (failureCode != null) 'failureCode': failureCode,
  };
}

final class GenerationResponseDto {
  const GenerationResponseDto({this.job, this.asset});
  final GenerationJobDto? job;
  final AssetDto? asset;
  factory GenerationResponseDto.fromJson(JsonObject json) =>
      GenerationResponseDto(
        job: json['job'] == null
            ? null
            : GenerationJobDto.fromJson(object(json['job'])),
        asset: json['asset'] == null
            ? null
            : AssetDto.fromJson(object(json['asset'])),
      );
  JsonObject toJson() => {
    if (job != null) 'job': job!.toJson(),
    if (asset != null) 'asset': asset!.toJson(),
  };
}

final class PublicationSnapshotDto {
  PublicationSnapshotDto({
    required this.title,
    required this.description,
    required this.outputFileId,
    required this.license,
    required this.allowDownload,
    Map<String, dynamic> fields = const {},
  }) : fields = Map.unmodifiable(fields);
  final String title, description, outputFileId, license;
  final bool allowDownload;
  final Map<String, dynamic> fields;
  factory PublicationSnapshotDto.fromJson(JsonObject json) =>
      PublicationSnapshotDto(
        title: string(json, 'title'),
        description: string(json, 'description', fallback: ''),
        outputFileId: string(json, 'outputFileId', fallback: ''),
        license: string(json, 'license', fallback: 'ccBy'),
        allowDownload: boolean(json, 'allowDownload'),
        fields: json,
      );
  JsonObject toJson() => {
    ...fields,
    'title': title,
    'description': description,
    'outputFileId': outputFileId,
    'license': license,
    'allowDownload': allowDownload,
  };
}

final class ModerationAuditDto {
  const ModerationAuditDto({
    required this.actorName,
    required this.action,
    required this.createdAt,
    this.reason,
  });
  final String actorName, action;
  final DateTime createdAt;
  final String? reason;
  factory ModerationAuditDto.fromJson(JsonObject json) => ModerationAuditDto(
    actorName: string(json, 'actorName'),
    action: string(json, 'action'),
    createdAt: date(json, 'createdAt'),
    reason: optionalString(json, 'reason'),
  );
  JsonObject toJson() => {
    'actorName': actorName,
    'action': action,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'reason': reason,
  };
}

final class PublicationSubmissionDto {
  PublicationSubmissionDto({
    required this.id,
    required this.status,
    required this.revision,
    this.assetId = '',
    this.submitterId,
    this.snapshot,
    this.slug,
    this.submittedAt,
    this.submitterName,
    this.reviewedAt,
    this.reviewedBy,
    this.rejectionReason,
    List<ModerationAuditDto> audit = const [],
  }) : audit = List.unmodifiable(audit);
  final String id, status, assetId;
  final int revision;
  final String? submitterId, slug, submitterName, reviewedBy, rejectionReason;
  final DateTime? submittedAt, reviewedAt;
  final PublicationSnapshotDto? snapshot;
  final List<ModerationAuditDto> audit;
  factory PublicationSubmissionDto.fromJson(JsonObject json) =>
      PublicationSubmissionDto(
        id: string(json, 'id'),
        status: string(json, 'status'),
        revision: integer(json, 'revision', fallback: 1),
        assetId: string(json, 'assetId', fallback: ''),
        submitterId: optionalString(json, 'submitterId'),
        slug: optionalString(json, 'slug'),
        submittedAt: optionalDate(json, 'submittedAt'),
        submitterName: optionalString(json, 'submitterName'),
        reviewedAt: optionalDate(json, 'reviewedAt'),
        reviewedBy: optionalString(json, 'reviewedBy'),
        rejectionReason: optionalString(json, 'rejectionReason'),
        snapshot: json['snapshot'] == null
            ? null
            : PublicationSnapshotDto.fromJson(object(json['snapshot'])),
        audit: (json['audit'] as List? ?? const [])
            .map((e) => ModerationAuditDto.fromJson(object(e)))
            .toList(),
      );
  JsonObject toJson() => {
    'id': id,
    'assetId': assetId,
    'status': status,
    'revision': revision,
    if (submitterId != null) 'submitterId': submitterId,
    'slug': slug,
    'submittedAt': submittedAt?.toUtc().toIso8601String(),
    'submitterName': submitterName,
    'reviewedAt': reviewedAt?.toUtc().toIso8601String(),
    'reviewedBy': reviewedBy,
    'rejectionReason': rejectionReason,
    'audit': audit.map((e) => e.toJson()).toList(),
    if (snapshot != null) 'snapshot': snapshot!.toJson(),
  };
}
