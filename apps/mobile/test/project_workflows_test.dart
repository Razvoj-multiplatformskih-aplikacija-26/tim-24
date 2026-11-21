import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_mobile/app_connection.dart';
import 'package:hedrion_mobile/main.dart';
import 'package:hedrion_mobile/memory_asset_repository.dart';
import 'package:hedrion_mobile/project_filter.dart';
import 'package:hedrion_mobile/studio_workflows.dart';

/// Projects are deliberately supplied independently of the asset storage.
class ProjectWorkflows implements StudioWorkflows {
  ProjectWorkflows(this.assets, {this.projectName = 'Test kolekcija'});
  final AssetRepository assets;
  final String projectName;
  final assignments = <String?>[];
  bool editable = true;
  @override
  bool get supportsSamples => true;
  @override
  bool get supportsFiles => false;
  @override
  bool get supportsHistory => false;
  @override
  bool get uploadsReference => false;
  @override
  bool get queuesImageOnSubmit => false;
  @override
  bool get online => true;
  @override
  bool get canModifyCollections => editable;
  @override
  Future<List<Map<String, dynamic>>> loadProjects() async => [
    {'id': 'project-alpha', 'name': projectName, 'revision': 1},
  ];
  @override
  Future<Asset> assignProject(Asset asset, String? projectId) async {
    assignments.add(projectId);
    return assets.updateAsset(
      asset.copyWith(projectId: projectId, clearProject: projectId == null),
      asset.revision,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'project filter consumes a port without an asset repository provider',
    (tester) async {
      final assets = MemoryAssetRepository(latency: Duration.zero);
      Widget filter(StudioWorkflows workflows) => StudioConnection(
        workflows: workflows,
        child: MaterialApp(
          home: Scaffold(
            body: ProjectFilter(
              value: 'all',
              assetProjectIds: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpWidget(filter(ProjectWorkflows(assets)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Test kolekcija'), findsOneWidget);
      await tester.tap(find.text('Svi projekti').last);
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        filter(ProjectWorkflows(assets, projectName: 'Druga kolekcija')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('project-filter')));
      await tester.pumpAndSettle();
      expect(find.text('Druga kolekcija'), findsOneWidget);
      expect(find.text('Test kolekcija'), findsNothing);
    },
  );

  testWidgets(
    'project screen assigns and removes through the same injected port',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final assets = MemoryAssetRepository(latency: Duration.zero);
      final chosen = (await assets.loadAssets()).first;
      final workflows = ProjectWorkflows(assets);
      await tester.pumpWidget(
        HedrionStudio(
          repository: assets,
          workflows: workflows,
          initialLocation: '/projects',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Test kolekcija'), findsOneWidget);
      await tester.tap(find.byTooltip('Dodaj model'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(chosen.title));
      await tester.pumpAndSettle();
      expect(workflows.assignments, ['project-alpha']);
      expect(
        (await assets.loadAssets())
            .firstWhere((asset) => asset.id == chosen.id)
            .projectId,
        'project-alpha',
      );
      await tester.tap(find.byTooltip('Ukloni iz kolekcije'));
      await tester.pumpAndSettle();
      expect(workflows.assignments, ['project-alpha', null]);
      expect(
        (await assets.loadAssets())
            .firstWhere((asset) => asset.id == chosen.id)
            .projectId,
        isNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
}
