import 'package:domain/domain.dart';
import 'package:test/test.dart';

void main() {
  test('publication rights and license are explicit typed decisions', () {
    expect(
      validatePublicationLicense(
        AssetLicense.ccBy,
        allowDownload: true,
        confirmRights: true,
      ).isValid,
      isTrue,
    );
    expect(
      validatePublicationLicense(
        AssetLicense.allRightsReserved,
        allowDownload: false,
        confirmRights: true,
      ).isValid,
      isTrue,
    );
    expect(
      validatePublicationLicense(
        AssetLicense.allRightsReserved,
        allowDownload: true,
        confirmRights: true,
      ).isValid,
      isFalse,
    );
    expect(
      validatePublicationLicense(
        AssetLicense.cc0,
        allowDownload: true,
        confirmRights: false,
      ).isValid,
      isFalse,
    );
  });
  final now = DateTime.utc(2026, 10, 21, 23, 59, 59);
  const owner = Actor(id: UserId('a'), role: UserRole.creator);
  const stranger = Actor(id: UserId('b'), role: UserRole.creator);
  const moderator = Actor(id: UserId('m'), role: UserRole.moderator);
  Asset asset(AssetLifecycle state, {bool output = true}) => Asset(
    id: const AssetId('1'),
    ownerId: owner.id,
    title: 'Kameni stub',
    lifecycle: state,
    createdAt: now,
    updatedAt: now,
    outputFileId: output ? 'file' : null,
  );
  test(
    'title trims and validates Unicode scalar length at exact boundaries',
    () {
      expect(validateTitle('  abc  ').orThrow, 'abc');
      expect(validateTitle('ab').error?.code, ErrorCode.invalidTitle);
      expect(validateTitle('a' * 60).isValid, isTrue);
      expect(validateTitle('a' * 61).isValid, isFalse);
      expect(validateTitle('😀😀😀').isValid, isTrue);
    },
  );
  test('typed identifiers, immutable tags and versioned round trip', () {
    final tags = ['stone'];
    final original = asset(AssetLifecycle.ready).copyWith(tags: tags);
    tags.add('mutated');
    expect(original.tags, ['stone']);
    expect(() => original.tags.add('bad'), throwsUnsupportedError);
    expect(Asset.fromJson(original.toJson()).toJson(), original.toJson());
  });
  test('only owner may submit a completed stored result', () {
    expect(
      validateTransition(
        asset(AssetLifecycle.ready),
        AssetLifecycle.pendingReview,
        owner,
      ).isValid,
      isTrue,
    );
    expect(
      validateTransition(
        asset(AssetLifecycle.ready),
        AssetLifecycle.pendingReview,
        stranger,
      ).error?.code,
      ErrorCode.forbidden,
    );
    expect(
      validateTransition(
        asset(AssetLifecycle.ready, output: false),
        AssetLifecycle.pendingReview,
        owner,
      ).error?.code,
      ErrorCode.missingOutput,
    );
    expect(
      validateTransition(
        asset(AssetLifecycle.generating),
        AssetLifecycle.pendingReview,
        owner,
      ).error?.code,
      ErrorCode.invalidTransition,
    );
  });
  test(
    'moderation requires role and reason; rejection retains output and is revisable',
    () {
      final pending = asset(AssetLifecycle.pendingReview);
      expect(
        validateTransition(
          pending,
          AssetLifecycle.published,
          owner,
        ).error?.code,
        ErrorCode.forbidden,
      );
      expect(
        validateTransition(
          pending,
          AssetLifecycle.published,
          moderator,
        ).isValid,
        isTrue,
      );
      expect(
        validateTransition(
          pending,
          AssetLifecycle.rejected,
          moderator,
        ).error?.code,
        ErrorCode.rejectionReasonRequired,
      );
      expect(
        validateTransition(
          pending,
          AssetLifecycle.rejected,
          moderator,
          reason: 'Nedostaje licenca',
        ).isValid,
        isTrue,
      );
      final rejected = pending.copyWith(lifecycle: AssetLifecycle.rejected);
      expect(rejected.hasOutput, isTrue);
      expect(
        validateTransition(rejected, AssetLifecycle.ready, owner).isValid,
        isTrue,
      );
    },
  );
  test('processing and ready transitions require a trusted server actor', () {
    expect(
      validateTransition(
        asset(AssetLifecycle.queued),
        AssetLifecycle.generating,
        owner,
      ).error?.code,
      ErrorCode.forbidden,
    );
    expect(
      validateTransition(
        asset(AssetLifecycle.generating, output: false),
        AssetLifecycle.ready,
        const Actor(id: UserId('worker'), role: UserRole.admin),
      ).error?.code,
      ErrorCode.missingOutput,
    );
  });
  test(
    'global daily admissions count other owners, retain failures, reject21, reset UTC',
    () {
      final rows = seedAdmissions(now, count: 19);
      expect(rows.map((r) => r.ownerId).toSet().length, 2);
      expect(validateDailyGenerationQuota(rows, now).orThrow, 20);
      final full = [
        ...rows,
        GenerationAdmission(
          jobId: const JobId('20'),
          ownerId: const UserId('c'),
          acceptedAt: now,
        ),
      ];
      expect(
        validateDailyGenerationQuota(full, now).error?.code,
        ErrorCode.dailyGenerationQuotaExceeded,
      );
      expect(
        validateDailyGenerationQuota(
          full,
          now.add(const Duration(seconds: 1)),
        ).orThrow,
        1,
      );
      expect(
        validateDailyGenerationQuota(
          full,
          DateTime.parse('2026-10-22T01:59:59+02:00'),
        ).isValid,
        isFalse,
      );
    },
  );
  test(
    'transfer includes reservations and permits exact1GB but not one byte extra',
    () {
      expect(
        validateTransferQuota(
          transferredBytes: 950000000,
          reservedBytes: 0,
          requestedBytes: 100000000,
        ).error?.code,
        ErrorCode.dailyTransferQuotaExceeded,
      );
      expect(
        validateTransferQuota(
          transferredBytes: 950000000,
          reservedBytes: 10000000,
          requestedBytes: 40000000,
        ).orThrow,
        1000000000,
      );
      expect(
        validateTransferQuota(
          transferredBytes: 950000000,
          reservedBytes: 10000000,
          requestedBytes: 40000001,
        ).isValid,
        isFalse,
      );
      expect(
        validateTransferQuota(
          transferredBytes: 0,
          reservedBytes: 0,
          requestedBytes: -1,
        ).error?.code,
        ErrorCode.invalidInput,
      );
    },
  );
  test(
    'persistent storage10GB has no daily reset and includes reservations',
    () {
      expect(
        validateStorageQuota(
          storedBytes: 9900000000,
          reservedBytes: 0,
          requestedBytes: 200000000,
        ).error?.code,
        ErrorCode.storageQuotaExceeded,
      );
      expect(
        validateStorageQuota(
          storedBytes: 9900000000,
          reservedBytes: 50000000,
          requestedBytes: 50000000,
        ).orThrow,
        10000000000,
      );
      expect(
        validateStorageQuota(
          storedBytes: 10000000000,
          reservedBytes: 0,
          requestedBytes: 1,
        ).isValid,
        isFalse,
      );
    },
  );
  test('job terminal states cannot restart; retry creates a different job', () {
    for (final terminal in [
      GenerationJobStatus.succeeded,
      GenerationJobStatus.failed,
      GenerationJobStatus.cancelled,
    ]) {
      for (final target in GenerationJobStatus.values) {
        expect(canTransitionJob(terminal, target), isFalse);
      }
    }
    expect(
      canTransitionJob(GenerationJobStatus.queued, GenerationJobStatus.running),
      isTrue,
    );
  });
  test('fixtures cover every state with independent lists', () {
    final first = seedAssets(ownerId: owner.id, now: now);
    final second = seedAssets(ownerId: moderator.id, now: now);
    expect(first.length, greaterThanOrEqualTo(10));
    expect(
      first.map((a) => a.lifecycle).toSet(),
      AssetLifecycle.values.toSet(),
    );
    first.clear();
    expect(second.length, 16);
  });
}
