import 'assets.dart';
import 'json.dart';

final class GenerationModelDto {
  const GenerationModelDto({required this.id, this.label, this.available});

  final String id;
  final String? label;
  final bool? available;

  factory GenerationModelDto.fromJson(JsonObject json) => GenerationModelDto(
    id: string(json, 'id'),
    label: optionalString(json, 'label'),
    available: json['available'] == null ? null : boolean(json, 'available'),
  );

  JsonObject toJson() => {
    'id': id,
    if (label != null) 'label': label,
    if (available != null) 'available': available,
  };
}

final class GenerationCapabilitiesDto {
  GenerationCapabilitiesDto({
    required this.imageTo3d,
    required this.textTo3d,
    required this.demo,
    this.provider,
    this.defaultModel,
    this.referenceImageProvider,
    Iterable<GenerationModelDto> generationModels = const [],
  }) : generationModels = List.unmodifiable(generationModels);

  final bool imageTo3d, textTo3d, demo;
  final String? provider, defaultModel, referenceImageProvider;
  final List<GenerationModelDto> generationModels;

  factory GenerationCapabilitiesDto.fromJson(JsonObject json) =>
      GenerationCapabilitiesDto(
        provider: optionalString(json, 'provider'),
        defaultModel: optionalString(json, 'defaultModel'),
        referenceImageProvider: optionalString(json, 'referenceImageProvider'),
        imageTo3d: boolean(json, 'imageTo3d'),
        textTo3d: boolean(json, 'textTo3d'),
        demo: boolean(json, 'demo'),
        generationModels: json['generationModels'] == null
            ? const []
            : objects(
                json,
                'generationModels',
              ).map(GenerationModelDto.fromJson),
      );

  JsonObject toJson() => {
    if (provider != null) 'provider': provider,
    'imageTo3d': imageTo3d,
    'textTo3d': textTo3d,
    'demo': demo,
    if (defaultModel != null) 'defaultModel': defaultModel,
    if (referenceImageProvider != null)
      'referenceImageProvider': referenceImageProvider,
    'generationModels': generationModels
        .map((model) => model.toJson())
        .toList(),
  };
}

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

final class GenerationHistoryDto {
  GenerationHistoryDto(Iterable<GenerationJobDto> jobs)
    : jobs = List.unmodifiable(jobs);

  final List<GenerationJobDto> jobs;

  factory GenerationHistoryDto.fromJson(JsonObject json) =>
      GenerationHistoryDto(
        objects(json, 'jobs').map(GenerationJobDto.fromJson),
      );

  JsonObject toJson() => {'jobs': jobs.map((job) => job.toJson()).toList()};
}

final class GenerationCancellationDto {
  const GenerationCancellationDto({
    required this.id,
    required this.status,
    required this.asset,
  });

  final String id, status;
  final AssetDto asset;

  factory GenerationCancellationDto.fromJson(JsonObject json) =>
      GenerationCancellationDto(
        id: string(json, 'id'),
        status: string(json, 'status'),
        asset: AssetDto.fromJson(object(json['asset'])),
      );

  JsonObject toJson() => {'id': id, 'status': status, 'asset': asset.toJson()};
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

final class ModerationStatsDto {
  const ModerationStatsDto({
    this.reviewedToday,
    this.approvalRate,
    this.activeJobs,
  });

  final int? reviewedToday, activeJobs;
  final num? approvalRate;

  factory ModerationStatsDto.fromJson(JsonObject json) {
    final rate = json['approvalRate'];
    if (rate != null && rate is! num) {
      throw const FormatException('Expected number: approvalRate');
    }
    return ModerationStatsDto(
      reviewedToday: json['reviewedToday'] == null
          ? null
          : integer(json, 'reviewedToday'),
      approvalRate: rate as num?,
      activeJobs: json['activeJobs'] == null
          ? null
          : integer(json, 'activeJobs'),
    );
  }

  JsonObject toJson() => {
    if (reviewedToday != null) 'reviewedToday': reviewedToday,
    if (approvalRate != null) 'approvalRate': approvalRate,
    if (activeJobs != null) 'activeJobs': activeJobs,
  };
}

final class ModerationPageDto {
  ModerationPageDto({
    required this.page,
    Iterable<PublicationSubmissionDto> submissions = const [],
    this.stats,
  }) : submissions = List.unmodifiable(submissions);

  final AssetPageDto page;
  final List<PublicationSubmissionDto> submissions;
  final ModerationStatsDto? stats;

  factory ModerationPageDto.fromJson(JsonObject json) => ModerationPageDto(
    page: AssetPageDto.fromJson(json),
    submissions: json['submissions'] == null
        ? const []
        : objects(json, 'submissions').map(PublicationSubmissionDto.fromJson),
    stats: json['stats'] == null
        ? null
        : ModerationStatsDto.fromJson(object(json['stats'])),
  );

  JsonObject toJson() => {
    ...page.toJson(),
    'submissions': submissions
        .map((submission) => submission.toJson())
        .toList(),
    if (stats != null) 'stats': stats!.toJson(),
  };
}
