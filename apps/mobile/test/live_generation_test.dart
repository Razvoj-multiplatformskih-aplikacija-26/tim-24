import 'dart:convert';
import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:hedrion_mobile/app_connection.dart';
import 'package:hedrion_mobile/generation_setup.dart';
import 'package:hedrion_mobile/main.dart';
import 'package:hedrion_mobile/memory_asset_repository.dart';
import 'package:hedrion_mobile/workspace_screen.dart';
import 'package:hedrion_mobile/studio_workflow_adapters.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('live workspace sends chosen model, prompt and seed to server', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Map<String, dynamic>? submitted;
    final api = HedrionApiClient(
      'http://localhost:8080',
      client: MockClient((request) async {
        if (request.url.path.endsWith('/capabilities')) {
          return http.Response(
            jsonEncode({
              'demo': false,
              'textTo3d': true,
              'imageTo3d': true,
              'generationModels': [
                {'id': 'spar3d', 'available': true},
                {'id': 'hunyuan3d_21', 'available': true},
                {'id': 'trellis2', 'available': true},
              ],
            }),
            200,
          );
        }
        if (request.method == 'POST' &&
            request.url.path.endsWith('/generations')) {
          submitted = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"job":{"id":"job-1","status":"queued"}}', 202);
        }
        if (request.url.path.endsWith('/generations')) {
          return http.Response('{"jobs":[]}', 200);
        }
        return http.Response('{}', 200);
      }),
    );
    final repository = MemoryAssetRepository(latency: Duration.zero);
    await tester.pumpWidget(
      HedrionStudio(
        repository: repository,
        api: api,
        initialLocation: '/workspace',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prikaži demo uzorak'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('generation-prompt')),
      'Brass clockwork owl',
    );
    await tester.tap(find.text('SPAR3D · Fast'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRELLIS.2 · Quality').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Generiši 3D model'));
    await tester.pumpAndSettle();
    expect(submitted?['modelProvider'], 'trellis2');
    expect(submitted?['inputType'], 'text_to_3d');
    expect(submitted?['sourcePrompt'], 'Brass clockwork owl');
    expect(submitted?['seed'], 42);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets('unavailable model shows explanation and cannot submit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var submissions = 0;
    final api = HedrionApiClient(
      'http://localhost:8080',
      client: MockClient((request) async {
        if (request.method == 'POST') submissions++;
        return http.Response(
          jsonEncode({
            'demo': false,
            'textTo3d': true,
            'imageTo3d': true,
            'generationModels': [
              {'id': 'spar3d', 'available': false},
            ],
          }),
          200,
        );
      }),
    );
    await tester.pumpWidget(
      HedrionStudio(
        repository: MemoryAssetRepository(latency: Duration.zero),
        api: api,
        initialLocation: '/workspace',
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Izabrani model trenutno nije dostupan. Izaberi drugi model.'),
      findsOneWidget,
    );
    expect(find.text('Generiši 3D model'), findsNothing);
    expect(submissions, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    api.close();
  });

  testWidgets(
    'image upload failure stays on form; retry queues same draft with fresh revision',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemoryAssetRepository(latency: Duration.zero);
      var uploads = 0;
      Map<String, dynamic>? submitted;
      final api = HedrionApiClient(
        'http://localhost:8080',
        client: MockClient((request) async {
          if (request.url.path.endsWith('/capabilities')) {
            return http.Response(
              '{"demo":false,"imageTo3d":true,"textTo3d":true}',
              200,
            );
          }
          if (request.method == 'PUT') {
            uploads++;
            if (uploads == 1) {
              return http.Response('{"code":"unavailable"}', 503);
            }
            final asset = (await repository.loadAssets()).singleWhere(
              (item) => item.title == 'owl.png',
            );
            return http.Response(
              jsonEncode({'asset': asset.copyWith(revision: 5).toJson()}),
              200,
            );
          }
          if (request.method == 'POST') {
            submitted = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response(
              '{"job":{"id":"job-1","status":"queued"}}',
              202,
            );
          }
          return http.Response('{}', 200);
        }),
      );
      final router = GoRouter(
        initialLocation: '/workspace',
        routes: [
          GoRoute(
            path: '/workspace',
            builder: (_, _) => WorkspaceScreen(
              flow: GenerationFlow.imageTo3d,
              pickReferenceImage: () async => XFile.fromData(
                base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
                ),
                name: 'owl.png',
                path: 'owl.png',
                mimeType: 'image/png',
              ),
            ),
          ),
          GoRoute(
            path: '/assets/:id',
            builder: (_, _) => const Text('Posao je poslat'),
          ),
        ],
      );
      await tester.pumpWidget(
        StudioConnection(
          workflows: HttpStudioWorkflows(api, repository: repository),
          client: api,
          child: RepositoryProvider<AssetRepository>.value(
            value: repository,
            child: BlocProvider(
              create: (_) => AssetBloc(repository)..add(const LoadAssets()),
              child: MaterialApp.router(routerConfig: router),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reference-upload')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Generiši 3D model'));
      await tester.pumpAndSettle();
      expect(uploads, 1);
      expect(submitted, isNull);
      expect(find.byKey(const Key('generation-error')), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/workspace');
      await tester.tap(find.text('Generiši 3D model'));
      await tester.pumpAndSettle();
      expect(uploads, 2);
      expect(submitted?['baseRevision'], 5);
      expect(submitted?['modelProvider'], 'spar3d');
      expect(submitted?['inputType'], 'image_to_3d');
      expect(
        (await repository.loadAssets())
            .where((item) => item.title == 'owl.png')
            .length,
        1,
      );
      expect(
        find.text('Posao je poslat'),
        findsOneWidget,
        reason:
            'Route: ${router.routeInformationProvider.value.uri.path}; '
            'error: ${tester.widgetList<Text>(find.byKey(const Key('generation-error'))).map((text) => text.data).toList()}',
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      api.close();
    },
  );
}
