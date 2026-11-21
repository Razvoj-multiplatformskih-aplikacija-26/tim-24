import 'package:domain/domain.dart';
import 'package:hedrion_contract/hedrion_contract.dart';

AssetDto assetToDto(Asset value) => AssetDto(
  id: value.id.value,
  ownerId: value.ownerId.value,
  title: value.title,
  description: value.description,
  category: value.category,
  projectId: value.projectId,
  tags: value.tags,
  favorite: value.favorite,
  lifecycle: value.lifecycle.name,
  createdAt: value.createdAt,
  updatedAt: value.updatedAt,
  revision: value.revision,
  outputFileId: value.outputFileId,
  previewFileId: value.previewFileId,
  rejectionReason: value.rejectionReason,
  allowDownload: value.allowDownload,
  license: value.license.name,
);

Asset assetFromDto(AssetDto value) => Asset(
  id: AssetId(value.id),
  ownerId: UserId(value.ownerId),
  title: value.title,
  description: value.description,
  category: value.category,
  projectId: value.projectId,
  tags: value.tags,
  favorite: value.favorite,
  lifecycle:
      AssetLifecycle.values
          .where((v) => v.name == value.lifecycle)
          .firstOrNull ??
      AssetLifecycle.draft,
  createdAt: value.createdAt.toUtc(),
  updatedAt: value.updatedAt.toUtc(),
  revision: value.revision,
  outputFileId: value.outputFileId,
  previewFileId: value.previewFileId,
  rejectionReason: value.rejectionReason,
  allowDownload: value.allowDownload,
  license:
      AssetLicense.values.where((v) => v.name == value.license).firstOrNull ??
      AssetLicense.allRightsReserved,
);

AssetDraftDto draftToDto(AssetDraft value) => AssetDraftDto(
  title: value.title.trim(),
  description: value.description,
  category: value.category,
  projectId: value.projectId,
  tags: value.tags,
);

AssetDraft draftFromDto(AssetDraftDto value) => AssetDraft(
  title: value.title,
  description: value.description,
  category: value.category,
  projectId: value.projectId,
  tags: value.tags,
);

Actor actorFromDto(IdentityDto value) => Actor(
  id: UserId(value.id),
  role:
      UserRole.values.where((v) => v.name == value.role).firstOrNull ??
      UserRole.creator,
);

IdentityDto actorToDto(
  Actor value, {
  String displayName = '',
  String email = '',
}) => IdentityDto(
  id: value.id.value,
  role: value.role.name,
  displayName: displayName,
  email: email,
);

ApiErrorDto errorToDto(DomainError value, {String? requestId}) => ApiErrorDto(
  code: value.code.name,
  details: value.details,
  requestId: requestId,
);

/// Older clients accept unknown codes and never show server diagnostics.
/// Known legacy aliases preserve the domain meaning of previous API releases.
DomainError errorFromDto(ApiErrorDto value, {int? status}) {
  final normalized = value.code.replaceAll('_', '').toLowerCase();
  final alias = switch (normalized) {
    'invalidrefresh' || 'sessionexpired' => 'sessionExpired',
    'unauthorized' => 'unauthenticated',
    'moderatorrequired' => 'forbidden',
    'assetnotfound' || 'submissionnotfound' => 'notFound',
    'alreadyreviewed' || 'idempotencyconflict' => 'revisionConflict',
    'reasonrequired' => 'rejectionReasonRequired',
    _ => value.code,
  };
  final code = ErrorCode.values
      .where(
        (e) => e.name.toLowerCase() == alias.replaceAll('_', '').toLowerCase(),
      )
      .firstOrNull;
  return DomainError(
    code ??
        switch (status ?? 0) {
          401 => ErrorCode.unauthenticated,
          403 => ErrorCode.forbidden,
          404 => ErrorCode.notFound,
          409 => ErrorCode.revisionConflict,
          >= 500 => ErrorCode.unavailable,
          _ => ErrorCode.serverRuleRejected,
        },
    value.details,
  );
}

Asset assetFromJson(Map<String, dynamic> json) =>
    assetFromDto(AssetDto.fromJson(json));
Map<String, dynamic> assetToJson(Asset value) => assetToDto(value).toJson();
Asset assetFromResponse(Map<String, dynamic> json) =>
    assetFromDto(AssetResponseDto.fromJson(json).asset);

GenerationJobDto jobToDto(GenerationJob value) => GenerationJobDto(
  id: value.id.value,
  assetId: value.assetId.value,
  ownerId: value.ownerId.value,
  status: value.status.name,
  inputType: value.inputType,
  acceptedAt: value.acceptedAt,
  outputFileId: value.outputFileId,
  failureCode: value.failureCode,
);

GenerationJob jobFromDto(GenerationJobDto value) => GenerationJob(
  id: JobId(value.id),
  assetId: AssetId(value.assetId),
  ownerId: UserId(value.ownerId),
  status:
      GenerationJobStatus.values
          .where((v) => v.name == value.status)
          .firstOrNull ??
      GenerationJobStatus.failed,
  inputType: value.inputType,
  acceptedAt: value.acceptedAt,
  outputFileId: value.outputFileId,
  failureCode: value.failureCode,
);

PublicationSubmissionDto publicationToDto(PublicationSubmission value) =>
    PublicationSubmissionDto(
      id: value.id.value,
      assetId: value.assetId.value,
      submitterId: value.submitterId.value,
      status: value.status == PublicationStatus.pendingReview
          ? 'pending_review'
          : value.status.name,
      revision: value.revision,
      rejectionReason: value.rejectionReason,
      snapshot: PublicationSnapshotDto(
        title: value.titleSnapshot,
        description: value.descriptionSnapshot,
        outputFileId: value.outputFileId,
        license: value.license.name,
        allowDownload: value.allowDownload,
      ),
    );

PublicationSubmission publicationFromDto(PublicationSubmissionDto value) {
  final snapshot = value.snapshot;
  if (snapshot == null) {
    throw const FormatException('Submission snapshot required');
  }
  final status = value.status == 'pending_review'
      ? 'pendingReview'
      : value.status;
  return PublicationSubmission(
    id: SubmissionId(value.id),
    assetId: AssetId(value.assetId),
    submitterId: UserId(
      value.submitterId ?? snapshot.fields['ownerId'] as String? ?? '',
    ),
    status:
        PublicationStatus.values.where((v) => v.name == status).firstOrNull ??
        PublicationStatus.withdrawn,
    titleSnapshot: snapshot.title,
    descriptionSnapshot: snapshot.description,
    outputFileId: snapshot.outputFileId,
    license:
        AssetLicense.values
            .where((v) => v.name == snapshot.license)
            .firstOrNull ??
        AssetLicense.allRightsReserved,
    allowDownload: snapshot.allowDownload,
    revision: value.revision,
    rejectionReason: value.rejectionReason,
  );
}
