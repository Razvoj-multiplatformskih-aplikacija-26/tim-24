import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_mobile/asset_preview.dart';
import 'package:hedrion_mobile/main.dart';
import 'package:hedrion_mobile/memory_asset_repository.dart';
import 'package:hedrion_mobile/mesh_scene.dart';
import 'package:hedrion_mobile/model_viewport.dart';

void size(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
    'text preview validates, retains request and queues a private model',
    (tester) async {
      size(tester, const Size(1440, 1000));
      final repository = MemoryAssetRepository(latency: Duration.zero);
      await tester.pumpWidget(
        HedrionStudio(repository: repository, initialLocation: '/workspace'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prikaži demo uzorak'));
      await tester.pump();
      expect(
        find.text('Opiši svoju ideju u najmanje 3 znaka.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('generation-prompt')),
        'A crystal game prop',
      );
      await tester.tap(find.text('Prikaži demo uzorak'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('THIS SESSION'), findsOneWidget);
      expect(find.text('A crystal game prop'), findsWidgets);
      expect(find.text('DEMO UZORAK'), findsOneWidget);
      expect((await repository.loadAssets()).length, 16);
      expect(repository.acceptedToday, 18);
      await tester.tap(find.text('↖ Reuse prompt'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('generation-prompt')))
            .controller!
            .text,
        'A crystal game prop',
      );
      await tester.tap(find.text('Zatraži demo generisanje'));
      await tester.pumpAndSettle();
      final asset = (await repository.loadAssets()).singleWhere(
        (a) => a.title == 'A crystal game prop',
      );
      expect(asset.lifecycle, AssetLifecycle.queued);
      expect(asset.description, 'A crystal game prop');
      expect(asset.outputFileId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'mobile studio queues text in one tap without opening a demo sample',
    (tester) async {
      size(tester, const Size(390, 844));
      final repository = MemoryAssetRepository(latency: Duration.zero);
      await tester.pumpWidget(
        HedrionStudio(repository: repository, initialLocation: '/workspace'),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('generation-prompt')),
        'Demo mač',
      );
      expect(find.text('Sačuvaj nacrt'), findsNothing);
      await tester.tap(find.text('Zatraži demo generisanje'));
      await tester.pumpAndSettle();

      final assets = await repository.loadAssets();
      final asset = assets.singleWhere((asset) => asset.title == 'Demo mač');
      expect(asset.lifecycle, AssetLifecycle.queued);
      expect(asset.outputFileId, isNull);
      expect(repository.acceptedToday, 19);
      expect(find.text('Demo mač'), findsWidgets);
      expect(find.byType(StudioPreview), findsNothing);
      expect(find.text('Zatraži generisanje'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('quota rejection keeps the form and reuses the saved draft', (
    tester,
  ) async {
    size(tester, const Size(390, 844));
    var now = DateTime.utc(2026, 11, 3);
    final repository = MemoryAssetRepository(
      latency: Duration.zero,
      clock: () => now,
    )..exhaustQuota();
    await tester.pumpWidget(
      HedrionStudio(repository: repository, initialLocation: '/workspace'),
    );
    await tester.pumpAndSettle();
    final prompt = find.byKey(const Key('generation-prompt'));
    final request = find.text('Zatraži demo generisanje');
    await tester.enterText(prompt, 'Drveni sanduk');
    await tester.tap(request);
    await tester.pumpAndSettle();

    expect(
      find.text('Dnevna kvota za generisanje je popunjena.'),
      findsOneWidget,
    );
    expect(tester.widget<TextField>(prompt).controller!.text, 'Drveni sanduk');
    final draft = (await repository.loadAssets()).singleWhere(
      (asset) => asset.title == 'Drveni sanduk',
    );
    expect(draft.lifecycle, AssetLifecycle.draft);
    expect(repository.acceptedToday, 20);

    now = now.add(const Duration(days: 1));
    await tester.enterText(prompt, 'Drveni sanduk sa metalnom bravom');
    await tester.tap(request);
    await tester.pumpAndSettle();

    final assets = await repository.loadAssets();
    final asset = assets.singleWhere((asset) => asset.id == draft.id);
    expect(assets.length, 17);
    expect(asset.lifecycle, AssetLifecycle.queued);
    expect(asset.description, 'Drveni sanduk sa metalnom bravom');
    expect(repository.acceptedToday, 1);
  });

  testWidgets(
    'image flow requires an uploaded reference and supports switching to text',
    (tester) async {
      size(tester, const Size(1280, 850));
      await tester.pumpWidget(
        HedrionStudio(
          repository: MemoryAssetRepository(latency: Duration.zero),
          initialLocation: '/workspace?flow=image-to-3d',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reference-upload')), findsOneWidget);
      expect(find.text('Sačuvaj nacrt'), findsOneWidget);
      await tester.tap(find.text('Prikaži demo uzorak'));
      await tester.pump();
      expect(find.text('Dodaj referentnu sliku da nastaviš.'), findsOneWidget);
      await tester.tap(find.text('Text to 3D'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('reference-upload')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'image concept stays in session and cannot create a fake 3D result',
    (tester) async {
      size(tester, const Size(1440, 1000));
      final repository = MemoryAssetRepository(latency: Duration.zero);
      await tester.pumpWidget(
        HedrionStudio(
          repository: repository,
          initialLocation: '/workspace?flow=text-to-image',
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('generation-prompt')),
        'A bonsai concept',
      );
      await tester.tap(find.text('Prikaži demo uzorak'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('IMAGE CONCEPT'), findsOneWidget);
      expect((await repository.loadAssets()).length, 16);
      expect(find.text('Sačuvaj nacrt'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('viewport responds to orbit, wireframe and reset', (
    tester,
  ) async {
    size(tester, const Size(1280, 850));
    await tester.pumpWidget(
      HedrionStudio(
        repository: MemoryAssetRepository(latency: Duration.zero),
        initialLocation: '/workspace',
      ),
    );
    await tester.pumpAndSettle();
    final viewport = find
        .byWidgetPredicate((w) => w is ModelViewport && w.interactive)
        .first;
    ScenePainter painter() => tester
        .widgetList<CustomPaint>(
          find.descendant(of: viewport, matching: find.byType(CustomPaint)),
        )
        .map((w) => w.painter)
        .whereType<ScenePainter>()
        .single;
    final initial = painter().yaw;
    await tester.drag(viewport, const Offset(90, 30));
    await tester.pump();
    expect(painter().yaw, isNot(initial));
    await tester.tap(find.byTooltip('Wireframe'));
    await tester.pump();
    expect(painter().material, ViewportMaterial.wireframe);
    await tester.tap(find.byTooltip('Reset view').first);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 350));
    expect(painter().yaw, initial);
    expect(tester.takeException(), isNull);
  });

  for (final dimensions in [
    const Size(390, 844),
    const Size(800, 600),
    const Size(1024, 768),
  ]) {
    testWidgets('workspace adapts without overflow at $dimensions', (
      tester,
    ) async {
      size(tester, dimensions);
      await tester.pumpWidget(
        HedrionStudio(
          repository: MemoryAssetRepository(latency: Duration.zero),
          initialLocation: '/workspace',
        ),
      );
      await tester.pumpAndSettle();
      if (dimensions.width < 1000) {
        await tester.tap(find.text('Preview'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Assets').first);
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
    });
  }

  test('all sample geometry projects to finite coordinates', () {
    for (final model in SampleModel.values) {
      for (final yaw in [-2.0, 0.0, 2.0]) {
        final faces = projectScene(
          SampleScene(model),
          yaw: yaw,
          pitch: .9,
          zoom: 2.4,
        );
        expect(faces, isNotEmpty);
        expect(
          faces.every(
            (f) => f.points.every((p) => p.$1.isFinite && p.$2.isFinite),
          ),
          isTrue,
        );
      }
    }
  });
}
