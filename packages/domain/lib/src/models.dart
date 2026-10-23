extension type const AssetId(String value) {}
extension type const UserId(String value) {}
extension type const JobId(String value) {}
extension type const SubmissionId(String value) {}

enum UserRole { creator, moderator, admin }

enum AssetLifecycle {
  draft,
  queued,
  generating,
  ready,
  pendingReview,
  published,
  failed,
  rejected;

  String get label => switch (this) {
    draft => 'Nacrt',
    queued => 'U redu',
    generating => 'Generisanje',
    ready => 'Spreman',
    pendingReview => 'Na proveri',
    published => 'Objavljen',
    failed => 'Neuspešno',
    rejected => 'Odbijen',
  };
}

enum AssetLicense { ccBy, cc0, allRightsReserved }

enum GenerationJobStatus {
  draft,
  queued,
  running,
  succeeded,
  failed,
  cancelled,
}

enum PublicationStatus {
  draft,
  pendingReview,
  approved,
  rejected,
  withdrawn,
  unpublished,
}

final class Actor {
  const Actor({required this.id, required this.role});
  final UserId id;
  final UserRole role;
}

final class Asset {
  Asset({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.lifecycle,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.category = 'props',
    this.projectId,
    List<String> tags = const [],
    this.favorite = false,
    this.revision = 1,
    this.outputFileId,
    this.previewFileId,
    this.rejectionReason,
    this.allowDownload = false,
    this.license = AssetLicense.ccBy,
  }) : tags = List.unmodifiable(tags);

  final AssetId id;
  final UserId ownerId;
  final String title;
  final String description;
  final String category;
  final String? projectId;
  final List<String> tags;
  final bool favorite;
  final AssetLifecycle lifecycle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int revision;
  final String? outputFileId;
  final String? previewFileId;
  final String? rejectionReason;
  final bool allowDownload;
  final AssetLicense license;
  bool get hasOutput => outputFileId != null && outputFileId!.isNotEmpty;

  Asset copyWith({
    String? title,
    String? description,
    String? category,
    String? projectId,
    bool clearProject = false,
    List<String>? tags,
    bool? favorite,
    AssetLifecycle? lifecycle,
    DateTime? updatedAt,
    int? revision,
    String? outputFileId,
    String? previewFileId,
    String? rejectionReason,
    bool? allowDownload,
    AssetLicense? license,
  }) => Asset(
    id: id,
    ownerId: ownerId,
    title: title ?? this.title,
    description: description ?? this.description,
    category: category ?? this.category,
    projectId: clearProject ? null : projectId ?? this.projectId,
    tags: tags ?? this.tags,
    favorite: favorite ?? this.favorite,
    lifecycle: lifecycle ?? this.lifecycle,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    revision: revision ?? this.revision,
    outputFileId: outputFileId ?? this.outputFileId,
    previewFileId: previewFileId ?? this.previewFileId,
    rejectionReason: rejectionReason ?? this.rejectionReason,
    allowDownload: allowDownload ?? this.allowDownload,
    license: license ?? this.license,
  );

  Map<String, Object?> toJson() => {
    'id': id.value,
    'ownerId': ownerId.value,
    'title': title,
    'description': description,
    'category': category,
    'projectId': projectId,
    'tags': tags,
    'favorite': favorite,
    'lifecycle': lifecycle.name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'revision': revision,
    'outputFileId': outputFileId,
    'previewFileId': previewFileId,
    'rejectionReason': rejectionReason,
    'allowDownload': allowDownload,
    'license': license.name,
  };

  factory Asset.fromJson(Map<String, dynamic> json) => Asset(
    id: AssetId(json['id'] as String),
    ownerId: UserId(json['ownerId'] as String),
    title: json['title'] as String,
    description: json['description'] as String? ?? '',
    category: json['category'] as String? ?? 'props',
    projectId: json['projectId'] as String?,
    tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
    favorite: json['favorite'] as bool? ?? false,
    lifecycle: AssetLifecycle.values.byName(json['lifecycle'] as String),
    createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    revision: json['revision'] as int? ?? 1,
    outputFileId: json['outputFileId'] as String?,
    previewFileId: json['previewFileId'] as String?,
    rejectionReason: json['rejectionReason'] as String?,
    allowDownload: json['allowDownload'] as bool? ?? false,
    license: AssetLicense.values.byName(json['license'] as String? ?? 'ccBy'),
  );
}

final class AssetDraft {
  AssetDraft({
    required this.title,
    this.description = '',
    this.category = 'props',
    this.projectId,
    List<String> tags = const [],
  }) : tags = List.unmodifiable(tags);
  final String title;
  final String description;
  final String category;
  final String? projectId;
  final List<String> tags;
  Map<String, Object?> toJson() => {
    'title': title.trim(),
    'description': description,
    'category': category,
    'projectId': projectId,
    'tags': tags,
  };
}

final class GenerationAdmission {
  const GenerationAdmission({
    required this.jobId,
    required this.ownerId,
    required this.acceptedAt,
  });
  final JobId jobId;
  final UserId ownerId;
  final DateTime acceptedAt;
}

final class GenerationJob {
  const GenerationJob({
    required this.id,
    required this.assetId,
    required this.ownerId,
    required this.status,
    required this.inputType,
    this.acceptedAt,
    this.outputFileId,
    this.failureCode,
  });
  final JobId id;
  final AssetId assetId;
  final UserId ownerId;
  final GenerationJobStatus status;
  final String inputType;
  final DateTime? acceptedAt;
  final String? outputFileId;
  final String? failureCode;
}

final class PublicationSubmission {
  const PublicationSubmission({
    required this.id,
    required this.assetId,
    required this.submitterId,
    required this.status,
    required this.titleSnapshot,
    required this.descriptionSnapshot,
    required this.outputFileId,
    required this.license,
    required this.allowDownload,
    required this.revision,
    this.rejectionReason,
  });
  final SubmissionId id;
  final AssetId assetId;
  final UserId submitterId;
  final PublicationStatus status;
  final String titleSnapshot;
  final String descriptionSnapshot;
  final String outputFileId;
  final AssetLicense license;
  final bool allowDownload;
  final int revision;
  final String? rejectionReason;
}
