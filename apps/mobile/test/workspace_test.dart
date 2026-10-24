import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
    'text preview validates, retains request and saves a private draft',
    (tester) async {
      size(tester, const Size(1440, 1000));
      final repository = MemoryAssetRepository(latency: Duration.zero);
      await tester.pumpWidget(
        HedrionStudio(repository: repository, initialLocation: '/workspace'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('generate-button')));
      await tester.pump();
      expect(
        find.text('Opiši svoju ideju u najmanje 3 znaka.'),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('generation-prompt')),
        'A crystal game prop',
      );
      await tester.tap(find.byKey(const Key('generate-button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('THIS SESSION'), findsOneWidget);
      expect(find.text('A crystal game prop'), findsWidgets);
      await tester.tap(find.text('↖ Reuse prompt'));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('generation-prompt')))
            .controller!
            .text,
        'A crystal game prop',
      );
      await tester.tap(find.text('Sačuvaj nacrt'));
      await tester.pumpAndSettle();
      final draft = (await repository.loadAssets()).singleWhere(
        (a) => a.title == 'A crystal game prop',
      );
      expect(draft.lifecycle, AssetLifecycle.draft);
      expect(draft.description, 'A crystal game prop');
      expect(draft.outputFileId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

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
      await tester.tap(find.byKey(const Key('generate-button')));
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
      await tester.tap(find.byKey(const Key('generate-button')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('IMAGE CONCEPT'), findsOneWidget);
      await tester.tap(find.text('Sačuvaj nacrt'));
      await tester.pump();
      expect((await repository.loadAssets()).length, 16);
      expect(find.byKey(const Key('generation-error')), findsOneWidget);
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
