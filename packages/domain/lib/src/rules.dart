import 'models.dart';

enum ErrorCode {
  invalidTitle,
  invalidDescription,
  invalidCategory,
  invalidInput,
  forbidden,
  invalidTransition,
  missingOutput,
  rejectionReasonRequired,
  dailyGenerationQuotaExceeded,
  dailyTransferQuotaExceeded,
  storageQuotaExceeded,
  revisionConflict,
  notFound,
  unavailable,
  unauthenticated,
  unsupportedInput,
}

final class DomainError {
  const DomainError(this.code, [this.details]);
  final ErrorCode code;
  final Object? details;
  String get message => errorMessage(this);
}

final class DomainException implements Exception {
  const DomainException(this.error);
  final DomainError error;
  @override
  String toString() => '${error.code.name}: ${error.message}';
}

sealed class Validation<T> {
  const Validation();
  bool get isValid => this is Valid<T>;
  T? get value => switch (this) {
    Valid<T>(:final data) => data,
    _ => null,
  };
  DomainError? get error => switch (this) {
    Invalid<T>(:final failure) => failure,
    _ => null,
  };
  T get orThrow => switch (this) {
    Valid<T>(:final data) => data,
    Invalid<T>(:final failure) => throw DomainException(failure),
  };
}

final class Valid<T> extends Validation<T> {
  const Valid(this.data);
  final T data;
}

final class Invalid<T> extends Validation<T> {
  const Invalid(this.failure);
  final DomainError failure;
}

String errorMessage(DomainError error) => switch (error.code) {
  ErrorCode.invalidTitle => 'Naziv mora imati od 3 do 60 znakova.',
  ErrorCode.invalidDescription => 'Opis može imati najviše 4000 znakova.',
  ErrorCode.invalidCategory => 'Izaberite podržanu kategoriju.',
  ErrorCode.invalidInput => 'Uneti podaci nisu ispravni.',
  ErrorCode.forbidden => 'Nemate ovlašćenje za ovu akciju.',
  ErrorCode.invalidTransition => 'Promena nije dozvoljena u trenutnom stanju.',
  ErrorCode.missingOutput => 'Model još nema sačuvan GLB rezultat.',
  ErrorCode.rejectionReasonRequired =>
    'Unesite razlog odbijanja (najmanje 3 znaka).',
  ErrorCode.dailyGenerationQuotaExceeded =>
    'Dnevna kvota za generisanje je popunjena.',
  ErrorCode.dailyTransferQuotaExceeded =>
    'Dnevna kvota prenosa fajlova je popunjena.',
  ErrorCode.storageQuotaExceeded =>
    'Nema dovoljno prostora u zajedničkom skladištu.',
  ErrorCode.revisionConflict =>
    'Model je u međuvremenu izmenjen. Osvežite podatke i ponovite izmenu.',
  ErrorCode.notFound => 'Traženi zapis ne postoji.',
  ErrorCode.unavailable => 'Veza nije dostupna. Pokušajte ponovo.',
  ErrorCode.unauthenticated => 'Prijavite se da biste nastavili.',
  ErrorCode.unsupportedInput =>
    'Ovaj način generisanja još nije povezan sa pravim providerom.',
};

Validation<String> validateTitle(String title) {
  final normalized = title.trim();
  return normalized.runes.length >= 3 && normalized.runes.length <= 60
      ? Valid(normalized)
      : const Invalid(DomainError(ErrorCode.invalidTitle));
}

const supportedCategories = [
  'props',
  'weapons',
  'furniture',
  'nature',
  'architecture',
];
Validation<AssetDraft> validateDraft(AssetDraft draft) {
  if (!validateTitle(draft.title).isValid) {
    return const Invalid(DomainError(ErrorCode.invalidTitle));
  }
  if (draft.description.length > 4000) {
    return const Invalid(DomainError(ErrorCode.invalidDescription));
  }
  if (!supportedCategories.contains(draft.category)) {
    return const Invalid(DomainError(ErrorCode.invalidCategory));
  }
  if (draft.tags.length > 20 || draft.tags.any((tag) => tag.length > 40)) {
    return const Invalid(DomainError(ErrorCode.invalidInput));
  }
  return Valid(draft);
}

const allowedAssetTransitions = <AssetLifecycle, Set<AssetLifecycle>>{
  AssetLifecycle.draft: {AssetLifecycle.queued},
  AssetLifecycle.queued: {AssetLifecycle.generating, AssetLifecycle.failed},
  AssetLifecycle.generating: {AssetLifecycle.ready, AssetLifecycle.failed},
  AssetLifecycle.ready: {AssetLifecycle.pendingReview},
  AssetLifecycle.pendingReview: {
    AssetLifecycle.published,
    AssetLifecycle.rejected,
    AssetLifecycle.ready,
  },
  AssetLifecycle.published: {AssetLifecycle.ready},
  AssetLifecycle.failed: {AssetLifecycle.queued},
  AssetLifecycle.rejected: {AssetLifecycle.ready},
};

Validation<AssetLifecycle> validateTransition(
  Asset asset,
  AssetLifecycle target,
  Actor actor, {
  String? reason,
}) {
  if (!(allowedAssetTransitions[asset.lifecycle]?.contains(target) ?? false)) {
    return const Invalid(DomainError(ErrorCode.invalidTransition));
  }
  final moderation =
      target == AssetLifecycle.published || target == AssetLifecycle.rejected;
  final processing =
      target == AssetLifecycle.generating ||
      (asset.lifecycle == AssetLifecycle.generating &&
          (target == AssetLifecycle.ready ||
              target == AssetLifecycle.failed)) ||
      (asset.lifecycle == AssetLifecycle.queued &&
          target == AssetLifecycle.failed);
  if (processing && actor.role != UserRole.admin) {
    return const Invalid(DomainError(ErrorCode.forbidden));
  }
  if (moderation &&
      actor.role != UserRole.moderator &&
      actor.role != UserRole.admin) {
    return const Invalid(DomainError(ErrorCode.forbidden));
  }
  if (!moderation &&
      !processing &&
      asset.ownerId != actor.id &&
      actor.role != UserRole.admin) {
    return const Invalid(DomainError(ErrorCode.forbidden));
  }
  if ((target == AssetLifecycle.pendingReview ||
          target == AssetLifecycle.published ||
          (asset.lifecycle == AssetLifecycle.generating &&
              target == AssetLifecycle.ready)) &&
      !asset.hasOutput) {
    return const Invalid(DomainError(ErrorCode.missingOutput));
  }
  if (target == AssetLifecycle.rejected &&
      (reason?.trim().runes.length ?? 0) < 3) {
    return const Invalid(DomainError(ErrorCode.rejectionReasonRequired));
  }
  return Valid(target);
}

bool canTransition(AssetLifecycle from, AssetLifecycle to) =>
    allowedAssetTransitions[from]?.contains(to) ?? false;

Validation<AssetLicense> validatePublicationLicense(
  AssetLicense license, {
  required bool allowDownload,
  required bool confirmRights,
}) {
  if (!confirmRights ||
      (allowDownload && license == AssetLicense.allRightsReserved)) {
    return const Invalid(DomainError(ErrorCode.invalidInput));
  }
  return Valid(license);
}

bool canTransitionJob(GenerationJobStatus from, GenerationJobStatus to) =>
    switch (from) {
      GenerationJobStatus.draft => {
        GenerationJobStatus.queued,
        GenerationJobStatus.cancelled,
      }.contains(to),
      GenerationJobStatus.queued => {
        GenerationJobStatus.running,
        GenerationJobStatus.cancelled,
      }.contains(to),
      GenerationJobStatus.running => {
        GenerationJobStatus.succeeded,
        GenerationJobStatus.failed,
        GenerationJobStatus.cancelled,
      }.contains(to),
      _ => false,
    };

DateTime utcDay(DateTime now) {
  final utc = now.toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day);
}

Validation<int> validateDailyGenerationQuota(
  Iterable<GenerationAdmission> admissions,
  DateTime now, {
  int limit = 20,
}) {
  final day = utcDay(now);
  final count = admissions.where((r) => utcDay(r.acceptedAt) == day).length;
  return count < limit
      ? Valid(count + 1)
      : const Invalid(DomainError(ErrorCode.dailyGenerationQuotaExceeded));
}

Validation<int> validateTransferQuota({
  required int transferredBytes,
  required int reservedBytes,
  required int requestedBytes,
  int limit = 1000000000,
}) => _bytes(
  transferredBytes,
  reservedBytes,
  requestedBytes,
  limit,
  ErrorCode.dailyTransferQuotaExceeded,
);
Validation<int> validateStorageQuota({
  required int storedBytes,
  required int reservedBytes,
  required int requestedBytes,
  int limit = 10000000000,
}) => _bytes(
  storedBytes,
  reservedBytes,
  requestedBytes,
  limit,
  ErrorCode.storageQuotaExceeded,
);
Validation<int> _bytes(
  int used,
  int reserved,
  int requested,
  int limit,
  ErrorCode code,
) {
  if (used < 0 || reserved < 0 || requested < 0 || limit < 0) {
    return const Invalid(DomainError(ErrorCode.invalidInput));
  }
  final total = used + reserved + requested;
  return total <= limit ? Valid(total) : Invalid(DomainError(code));
}
