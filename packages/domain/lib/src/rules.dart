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
  sessionExpired,
  backofficeRoleRequired,
  activeJobLimit,
  serverRuleRejected,
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
  ErrorCode.invalidTitle =>
    'Naziv mora imati od ${_integerDetail(error, 'minLength', 3)} do ${_integerDetail(error, 'maxLength', 60)} znakova.',
  ErrorCode.invalidDescription =>
    'Opis može imati najviše ${_integerDetail(error, 'maxLength', 4000)} znakova.',
  ErrorCode.invalidCategory => 'Izaberite podržanu kategoriju.',
  ErrorCode.invalidInput => _inputMessage(error),
  ErrorCode.forbidden => 'Nemate ovlašćenje za ovu akciju.',
  ErrorCode.invalidTransition => 'Promena nije dozvoljena u trenutnom stanju.',
  ErrorCode.missingOutput => 'Model još nema sačuvan GLB rezultat.',
  ErrorCode.rejectionReasonRequired =>
    'Razlog odbijanja mora imati od ${_integerDetail(error, 'minLength', 3)} do ${_integerDetail(error, 'maxLength', 1000)} znakova.',
  ErrorCode.dailyGenerationQuotaExceeded =>
    'Dnevna kvota za generisanje je popunjena (najviše ${_integerDetail(error, 'limit', 20)} zahteva).',
  ErrorCode.dailyTransferQuotaExceeded =>
    'Dnevna kvota prenosa fajlova je popunjena (najviše ${_byteLimit(error, 1000000000)}).',
  ErrorCode.storageQuotaExceeded =>
    'Nema dovoljno prostora u zajedničkom skladištu (najviše ${_byteLimit(error, 10000000000)}).',
  ErrorCode.revisionConflict =>
    'Model je u međuvremenu izmenjen. Osvežite podatke i ponovite izmenu.',
  ErrorCode.notFound => 'Traženi zapis ne postoji.',
  ErrorCode.unavailable => 'Veza nije dostupna. Pokušajte ponovo.',
  ErrorCode.unauthenticated => 'Prijavite se da biste nastavili.',
  ErrorCode.sessionExpired => 'Sesija je istekla. Prijavite se ponovo.',
  ErrorCode.backofficeRoleRequired =>
    'Backoffice je namenjen moderatorima i administratorima.',
  ErrorCode.activeJobLimit =>
    'Već imate aktivan zahtev. Sačekajte njegov završetak.',
  ErrorCode.serverRuleRejected =>
    'Akcija trenutno nije dozvoljena. Osvežite podatke i pokušajte ponovo.',
  ErrorCode.unsupportedInput =>
    'Ovaj način generisanja još nije povezan sa pravim providerom.',
};

int _integerDetail(DomainError error, String key, int fallback) {
  final details = error.details;
  final value = details is Map ? details[key] : null;
  return value is int && value >= 0 ? value : fallback;
}

String _inputMessage(DomainError error) {
  final details = error.details;
  if (details is Map && details['rule'] == 'publicationLicense') {
    if (details['confirmRights'] == false) {
      return 'Potvrdite prava na ulaznu sliku i model.';
    }
    if (details['allowDownload'] == true &&
        details['license'] == AssetLicense.allRightsReserved.name) {
      return 'Za preuzimanje izaberite CC BY ili CC0 licencu.';
    }
    return 'Izaberite podržanu licencu.';
  }
  if (details is Map && details['rule'] == 'tags') {
    return 'Dozvoljeno je najviše ${_integerDetail(error, 'maxTags', 20)} oznaka, do ${_integerDetail(error, 'maxTagLength', 40)} znakova po oznaci.';
  }
  return 'Uneti podaci nisu ispravni.';
}

String _byteLimit(DomainError error, int fallback) {
  final limit = _integerDetail(error, 'limit', fallback);
  return limit >= 1000000000 && limit % 1000000000 == 0
      ? '${limit ~/ 1000000000} GB'
      : limit >= 1000000 && limit % 1000000 == 0
      ? '${limit ~/ 1000000} MB'
      : '$limit bajtova';
}

/// These are application permissions, shared by server and every client.
bool canAccessBackoffice(UserRole role) => canModerate(role);
bool canModerate(UserRole role) =>
    role == UserRole.moderator || role == UserRole.admin;
bool canManageAsset(Asset asset, Actor actor) => asset.ownerId == actor.id;

Validation<Actor> validateBackofficeAccess(Actor actor) =>
    canAccessBackoffice(actor.role)
    ? Valid(actor)
    : const Invalid(DomainError(ErrorCode.backofficeRoleRequired));

Validation<Actor> validateModerationAccess(Actor actor) =>
    canModerate(actor.role)
    ? Valid(actor)
    : const Invalid(
        DomainError(ErrorCode.forbidden, {
          'requiredRoles': ['moderator', 'admin'],
        }),
      );

/// Private records deliberately do not disclose their existence to other users.
Validation<Asset> validateAssetOwnership(Asset asset, Actor actor) =>
    canManageAsset(asset, actor)
    ? Valid(asset)
    : const Invalid(DomainError(ErrorCode.notFound));

const titleMinLength = 3;
const titleMaxLength = 60;
const descriptionMaxLength = 4000;
const rejectionReasonMinLength = 3;
const rejectionReasonMaxLength = 1000;

Validation<String> validateTitle(
  String title, {
  int minLength = titleMinLength,
  int maxLength = titleMaxLength,
}) {
  final normalized = title.trim();
  final length = normalized.runes.length;
  return length >= minLength && length <= maxLength
      ? Valid(normalized)
      : Invalid(
          DomainError(ErrorCode.invalidTitle, {
            'minLength': minLength,
            'maxLength': maxLength,
            'actualLength': length,
          }),
        );
}

const supportedCategories = [
  'props',
  'weapons',
  'furniture',
  'nature',
  'architecture',
];
Validation<AssetDraft> validateDraft(AssetDraft draft) {
  final title = validateTitle(draft.title);
  if (!title.isValid) {
    return Invalid(title.error!);
  }
  if (draft.description.length > descriptionMaxLength) {
    return Invalid(
      DomainError(ErrorCode.invalidDescription, {
        'maxLength': descriptionMaxLength,
        'actualLength': draft.description.length,
      }),
    );
  }
  if (!supportedCategories.contains(draft.category)) {
    return const Invalid(
      DomainError(ErrorCode.invalidCategory, {
        'supportedCategories': supportedCategories,
      }),
    );
  }
  if (draft.tags.length > 20 || draft.tags.any((tag) => tag.length > 40)) {
    return const Invalid(
      DomainError(ErrorCode.invalidInput, {
        'rule': 'tags',
        'maxTags': 20,
        'maxTagLength': 40,
      }),
    );
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
    return Invalid(
      DomainError(ErrorCode.invalidTransition, {
        'from': asset.lifecycle.name,
        'to': target.name,
        'allowed':
            allowedAssetTransitions[asset.lifecycle]
                ?.map((value) => value.name)
                .toList() ??
            const <String>[],
      }),
    );
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
  if (moderation) {
    final access = validateModerationAccess(actor);
    if (!access.isValid) return Invalid(access.error!);
  }
  if (!moderation && !processing) {
    final access = validateAssetOwnership(asset, actor);
    if (!access.isValid) return Invalid(access.error!);
  }
  if ((target == AssetLifecycle.pendingReview ||
          target == AssetLifecycle.published ||
          (asset.lifecycle == AssetLifecycle.generating &&
              target == AssetLifecycle.ready)) &&
      !asset.hasOutput) {
    return const Invalid(DomainError(ErrorCode.missingOutput));
  }
  final reasonLength = reason?.trim().runes.length ?? 0;
  if (target == AssetLifecycle.rejected &&
      (reasonLength < rejectionReasonMinLength ||
          reasonLength > rejectionReasonMaxLength)) {
    return Invalid(
      DomainError(ErrorCode.rejectionReasonRequired, {
        'minLength': rejectionReasonMinLength,
        'maxLength': rejectionReasonMaxLength,
        'actualLength': reasonLength,
      }),
    );
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
    return Invalid(
      DomainError(ErrorCode.invalidInput, {
        'rule': 'publicationLicense',
        'confirmRights': confirmRights,
        'allowDownload': allowDownload,
        'license': license.name,
      }),
    );
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
  if (limit < 0) return const Invalid(DomainError(ErrorCode.invalidInput));
  final count = admissions.where((r) => utcDay(r.acceptedAt) == day).length;
  return count < limit
      ? Valid(count + 1)
      : Invalid(
          DomainError(ErrorCode.dailyGenerationQuotaExceeded, {
            'limit': limit,
            'current': count,
            'requested': 1,
          }),
        );
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
  return total <= limit
      ? Valid(total)
      : Invalid(
          DomainError(code, {
            'limit': limit,
            'used': used,
            'reserved': reserved,
            'requested': requested,
          }),
        );
}
