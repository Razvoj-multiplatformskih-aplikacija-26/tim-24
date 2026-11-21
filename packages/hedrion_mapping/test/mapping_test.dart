import 'package:domain/domain.dart';
import 'package:hedrion_contract/hedrion_contract.dart';
import 'package:hedrion_mapping/hedrion_mapping.dart';
import 'package:test/test.dart';

void main() {
  test(
    'job mapping keeps its domain identity and extensible Modal timings',
    () {
      const domain = GenerationJob(
        id: JobId('job'),
        assetId: AssetId('asset'),
        ownerId: UserId('owner'),
        status: GenerationJobStatus.succeeded,
        inputType: 'text_to_3d',
        outputFileId: 'glb',
      );
      final wire = jobToDto(domain).toJson()
        ..['provider'] = 'trellis2'
        ..['seed'] = 123
        ..['timings'] = {'inferenceSeconds': 59.0};
      final dto = GenerationJobDto.fromJson(wire);
      expect(jobFromDto(dto).id.value, 'job');
      expect(jobFromDto(dto).outputFileId, 'glb');
      expect(dto.toJson()['provider'], 'trellis2');
      expect(dto.toJson()['timings'], {'inferenceSeconds': 59.0});
    },
  );

  test('publication mapping translates snake-case wire state both ways', () {
    const domain = PublicationSubmission(
      id: SubmissionId('submission'),
      assetId: AssetId('asset'),
      submitterId: UserId('owner'),
      status: PublicationStatus.pendingReview,
      titleSnapshot: 'Kameni zmaj',
      descriptionSnapshot: 'Opis',
      outputFileId: 'glb',
      license: AssetLicense.ccBy,
      allowDownload: true,
      revision: 3,
    );
    final dto = PublicationSubmissionDto.fromJson(
      publicationToDto(domain).toJson(),
    );
    expect(dto.status, 'pending_review');
    final restored = publicationFromDto(dto);
    expect(restored.status, PublicationStatus.pendingReview);
    expect(restored.titleSnapshot, domain.titleSnapshot);
    expect(restored.outputFileId, 'glb');
    expect(restored.submitterId.value, 'owner');
    expect(restored.allowDownload, isTrue);
  });

  test('domain asset crosses DTO boundary both ways without losing fields', () {
    final asset = seedAssets(ownerId: const UserId('creator')).first.copyWith(
      title: 'Drveni vitez',
      category: 'props',
      tags: ['drvo', 'vitez'],
      favorite: true,
      revision: 9,
      license: AssetLicense.allRightsReserved,
      outputFileId: 'model',
      previewFileId: 'preview',
    );
    expect(
      assetFromDto(AssetDto.fromJson(assetToDto(asset).toJson())).toJson(),
      asset.toJson(),
    );
  });

  test('draft mapping retains project/tags and validates in shared domain', () {
    final wire = AssetDraftDto(
      title: ' Kameni toranj ',
      description: 'Opis',
      projectId: 'project',
      category: 'architecture',
      tags: ['toranj'],
    );
    final domain = draftFromDto(wire);
    expect(validateDraft(domain).isValid, isTrue);
    expect(draftToDto(domain).title, 'Kameni toranj');
    expect(draftToDto(domain).projectId, 'project');
    expect(draftToDto(domain).tags, ['toranj']);
  });

  test(
    'client compiled with old title limit explains the server new limit',
    () {
      // This DTO models a response from a server rebuilt with a tighter rule.
      const server = ApiErrorDto(
        code: 'invalidTitle',
        details: {'minLength': 3, 'maxLength': 40, 'actualLength': 45},
        message: 'Do not render this server diagnostic',
      );
      final error = errorFromDto(
        ApiErrorDto.fromJson(server.toJson()),
        status: 422,
      );
      expect(error.code, ErrorCode.invalidTitle);
      expect(error.message, 'Naziv mora imati od 3 do 40 znakova.');
      expect(error.message, isNot(contains('60')));
      expect(errorToDto(error).details, server.details);
    },
  );

  test(
    'local rule and network round trip produce the same code and message',
    () {
      final local = validateTitle('x').error!;
      final transported = errorFromDto(
        ApiErrorDto.fromJson(errorToDto(local).toJson()),
      );
      expect(transported.code, local.code);
      expect(transported.details, local.details);
      expect(transported.message, local.message);
    },
  );

  test(
    'new server rule is safe on an old client and cannot inject diagnostics',
    () {
      final unknown = errorFromDto(
        const ApiErrorDto(
          code: 'newPremiumTierLimit',
          details: {'limit': 2},
          message: 'SQL stacktrace or arbitrary text',
        ),
        status: 429,
      );
      expect(unknown.code, ErrorCode.serverRuleRejected);
      expect(unknown.details, {'limit': 2});
      expect(unknown.message, contains('Osvežite podatke'));
      expect(unknown.message, isNot(contains('SQL')));
    },
  );

  test(
    'active job limit differs from a daily quota and legacy session expires',
    () {
      expect(
        errorFromDto(
          const ApiErrorDto(code: 'activeJobLimit'),
          status: 429,
        ).code,
        ErrorCode.activeJobLimit,
      );
      expect(
        errorFromDto(
          const ApiErrorDto(code: 'DAILY_GENERATION_QUOTA_EXCEEDED'),
          status: 429,
        ).code,
        ErrorCode.dailyGenerationQuotaExceeded,
      );
      expect(
        errorFromDto(
          const ApiErrorDto(code: 'invalidRefresh'),
          status: 401,
        ).code,
        ErrorCode.sessionExpired,
      );
    },
  );

  test(
    'unknown state or license stays conservatively private on older clients',
    () {
      final json =
          assetToDto(seedAssets(ownerId: const UserId('owner')).first).toJson()
            ..['lifecycle'] = 'futureModerationState'
            ..['license'] = 'futureLicense';
      final oldClient = assetFromJson(json);
      expect(oldClient.lifecycle, AssetLifecycle.draft);
      expect(oldClient.license, AssetLicense.allRightsReserved);
    },
  );
}
