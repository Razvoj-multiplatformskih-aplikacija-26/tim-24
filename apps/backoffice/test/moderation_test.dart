import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_backoffice/main.dart';
import 'package:hedrion_backoffice/memory_moderation_repository.dart';

void main() {
  test(
    'reject retains result and concurrent stale moderation conflicts',
    () async {
      final repository = MemoryModerationRepository(latency: Duration.zero);
      final assets = await repository.loadAssets();
      expect(assets.length, greaterThanOrEqualTo(10));
      expect(
        assets.map((a) => a.lifecycle).toSet(),
        AssetLifecycle.values.toSet(),
      );
      final pending = assets.firstWhere(
        (a) => a.lifecycle == AssetLifecycle.pendingReview,
      );
      final rejected = await repository.transitionAsset(
        pending.id,
        AssetLifecycle.rejected,
        baseRevision: pending.revision,
        reason: 'Dopunite opis.',
      );
      expect(rejected.outputFileId, pending.outputFileId);
      await expectLater(
        repository.transitionAsset(
          pending.id,
          AssetLifecycle.published,
          baseRevision: pending.revision,
        ),
        throwsA(
          isA<DomainException>().having(
            (e) => e.error.code,
            'conflict',
            ErrorCode.revisionConflict,
          ),
        ),
      );
    },
  );
  testWidgets('keyboard approval and resize keep selected asset', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = MemoryModerationRepository(latency: Duration.zero);
    final pending = (await repository.loadAssets()).firstWhere(
      (a) => a.lifecycle == AssetLifecycle.pendingReview,
    );
    await tester.pumpWidget(HedrionBackoffice(repository: repository));
    await tester.pumpAndSettle();
    repository.failNext = true;
    await tester.tap(find.byTooltip('Osveži (Ctrl+R)'));
    await tester.pumpAndSettle();
    expect(find.text('Pokušaj ponovo'), findsOneWidget);
    await tester.tap(find.text('Pokušaj ponovo'));
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      (await repository.loadAssets())
          .firstWhere((a) => a.id == pending.id)
          .lifecycle,
      AssetLifecycle.published,
    );
    tester.view.physicalSize = const Size(700, 1000);
    await tester.pumpAndSettle();
    expect(find.byType(DataTable), findsNothing);
    expect(find.text(pending.title), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
