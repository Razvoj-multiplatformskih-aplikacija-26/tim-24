import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_mobile/main.dart';
import 'package:hedrion_mobile/memory_asset_repository.dart';

void main() {
  test('quota refusal keeps draft and accepted count unchanged', () async {
    final repository = MemoryAssetRepository(latency: Duration.zero);
    repository.exhaustQuota();
    final draft = await repository.createAsset(
      AssetDraft(title: 'Novi sanduk'),
    );
    await expectLater(
      repository.transitionAsset(
        draft.id,
        AssetLifecycle.queued,
        baseRevision: draft.revision,
      ),
      throwsA(
        isA<DomainException>().having(
          (e) => e.error.code,
          'quota',
          ErrorCode.dailyGenerationQuotaExceeded,
        ),
      ),
    );
    final current = (await repository.loadAssets()).firstWhere(
      (a) => a.id == draft.id,
    );
    expect(current.lifecycle, AssetLifecycle.draft);
    expect(current.revision, draft.revision);
    expect(repository.acceptedToday, 20);
  });
  test(
    'creator and moderator stores are not shared and seed covers all states',
    () async {
      final a = MemoryAssetRepository(latency: Duration.zero),
          b = MemoryAssetRepository(latency: Duration.zero);
      final records = await a.loadAssets();
      expect(records.length, greaterThanOrEqualTo(10));
      expect(
        records.map((a) => a.lifecycle).toSet(),
        AssetLifecycle.values.toSet(),
      );
      await a.deleteAsset(records.first.id, records.first.revision);
      expect((await b.loadAssets()).length, records.length);
    },
  );
  testWidgets('library search, validated form, create and retry states', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1250, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryAssetRepository(latency: Duration.zero);
    await tester.pumpWidget(HedrionStudio(repository: repository));
    await tester.pumpAndSettle();
    expect(find.text('Novi model'), findsOneWidget);
    repository.failNext = true;
    await tester.tap(find.byTooltip('Osveži biblioteku'));
    await tester.pumpAndSettle();
    expect(find.text('Pokušaj ponovo'), findsOneWidget);
    await tester.tap(find.text('Pokušaj ponovo'));
    await tester.pumpAndSettle();
    expect(find.text('Pokušaj ponovo'), findsNothing);
    await tester.enterText(find.byType(TextField).first, 'nepostojeci');
    await tester.pump();
    expect(find.text('Nema modela za ovaj izbor'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await tester.tap(find.text('Novi model'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Sačuvaj privatni nacrt'));
    await tester.tap(find.text('Sačuvaj privatni nacrt'));
    await tester.pumpAndSettle();
    expect(find.text('Naziv mora imati od 3 do 60 znakova.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Test rekvizit');
    await tester.enterText(
      find.byKey(const Key('create-tags')),
      'drvo, igra, drvo',
    );
    await tester.ensureVisible(find.text('Sačuvaj privatni nacrt'));
    await tester.tap(find.text('Sačuvaj privatni nacrt'));
    await tester.pumpAndSettle();
    expect(find.text('Test rekvizit'), findsOneWidget);
    expect((await repository.loadAssets()).length, 17);
    expect(
      (await repository.loadAssets())
          .singleWhere((a) => a.title == 'Test rekvizit')
          .tags,
      ['drvo', 'igra'],
    );
  });
  test(
    'publication options and collection removal preserve private model',
    () async {
      final repository = MemoryAssetRepository(latency: Duration.zero);
      var ready = (await repository.loadAssets()).firstWhere(
        (a) => a.lifecycle == AssetLifecycle.ready,
      );
      final project = repository.saveProject('Prva kolekcija');
      ready = await repository.updateAsset(
        ready.copyWith(projectId: project['id'] as String),
        ready.revision,
      );
      expect(ready.projectId, project['id']);
      ready = await repository.updateAsset(
        ready.copyWith(clearProject: true),
        ready.revision,
      );
      expect(ready.projectId, isNull);
      await expectLater(
        repository.submitPublication(
          ready.id,
          baseRevision: ready.revision,
          license: AssetLicense.allRightsReserved,
          allowDownload: true,
          confirmRights: true,
          idempotencyKey: 'invalid-license',
        ),
        throwsA(isA<DomainException>()),
      );
      final submitted = await repository.submitPublication(
        ready.id,
        baseRevision: ready.revision,
        license: AssetLicense.allRightsReserved,
        allowDownload: false,
        confirmRights: true,
        idempotencyKey: 'preview-only',
      );
      expect(submitted.lifecycle, AssetLifecycle.pendingReview);
      expect(submitted.allowDownload, isFalse);
      expect(submitted.outputFileId, ready.outputFileId);
      final replay = await repository.submitPublication(
        ready.id,
        baseRevision: ready.revision,
        license: AssetLicense.allRightsReserved,
        allowDownload: false,
        confirmRights: true,
        idempotencyKey: 'preview-only',
      );
      expect(replay.revision, submitted.revision);
      final withdrawn = await repository.transitionAsset(
        submitted.id,
        AssetLifecycle.ready,
        baseRevision: submitted.revision,
      );
      expect(withdrawn.lifecycle, AssetLifecycle.ready);
      expect(withdrawn.outputFileId, ready.outputFileId);
    },
  );
  testWidgets('phone layout keeps touch navigation and details accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryAssetRepository(latency: Duration.zero);
    await tester.pumpWidget(HedrionStudio(repository: repository));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('Kristalni mač'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Kristalni mač'));
    await tester.pumpAndSettle();
    expect(find.text('Zatraži generisanje'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
