import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_mobile/initial_route.dart';
import 'package:hedrion_mobile/main.dart';
import 'package:hedrion_mobile/memory_asset_repository.dart';

void main() {
  test(
    'authentication preserves local hash routes and rejects external routes',
    () {
      expect(
        creatorInitialRoute(
          Uri.parse('http://localhost:8082/#/assets/model-1?tab=history'),
        ),
        '/assets/model-1?tab=history',
      );
      expect(
        creatorInitialRoute(Uri.parse('http://localhost:8082/#/projects')),
        '/projects',
      );
      expect(
        creatorInitialRoute(
          Uri.parse('http://localhost:8082/#https://other.test'),
        ),
        '/',
      );
      expect(
        creatorInitialRoute(Uri.parse('http://localhost:8082/#//other.test')),
        '/',
      );
    },
  );
  testWidgets(
    'captured detail survives temporary authentication app route reset',
    (tester) async {
      final store = MemoryAssetRepository(latency: Duration.zero);
      final asset = (await store.loadAssets()).first;
      final captured = creatorInitialRoute(
        Uri.parse('http://localhost:8082/#/assets/${asset.id.value}'),
      );
      await tester.pumpWidget(const MaterialApp(home: Text('Prijava')));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        HedrionStudio(repository: store, initialLocation: captured),
      );
      await tester.pumpAndSettle();
      expect(find.text(asset.title), findsOneWidget);
      expect(find.text('Biblioteka'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
