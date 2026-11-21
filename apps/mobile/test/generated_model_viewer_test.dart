import 'dart:convert';
import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:hedrion_mobile/asset_preview.dart';
import 'package:hedrion_mobile/app_connection.dart';
import 'package:hedrion_mobile/generated_model_viewer.dart';
import 'package:hedrion_mobile/generation_history.dart';
import 'package:hedrion_mobile/studio_workflow_adapters.dart';
import 'package:hedrion_mobile/studio_workflows.dart';
import 'package:hedrion_mobile/studio_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Uint8List glb(Map<String, Object?> document) {
  final json = utf8.encode(jsonEncode(document));
  final padded = (json.length + 3) ~/ 4 * 4;
  final bytes = Uint8List(20 + padded)..fillRange(20, 20 + padded, 32);
  final header = ByteData.sublistView(bytes);
  header.setUint32(0, 0x46546c67, Endian.little);
  header.setUint32(4, 2, Endian.little);
  header.setUint32(8, bytes.length, Endian.little);
  header.setUint32(12, padded, Endian.little);
  header.setUint32(16, 0x4e4f534a, Endian.little);
  bytes.setRange(20, 20 + json.length, json);
  return bytes;
}

class _ViewerWorkflows implements StudioWorkflows {
  _ViewerWorkflows(this.bytes, {this.supportsFiles = true});
  final Uint8List bytes;
  int downloads = 0, histories = 0;
  @override
  final bool supportsFiles;
  @override
  bool get supportsHistory => false;
  @override
  Future<Uint8List> download(Asset asset) async {
    downloads++;
    return bytes;
  }

  @override
  Future<Map<String, dynamic>> generationHistory(AssetId id) async {
    histories++;
    throw StateError('This implementation does not offer history.');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'file-only implementation views GLB without requesting history',
    () async {
      final bytes = glb({
        'asset': {'version': '2.0'},
      });
      final workflows = _ViewerWorkflows(bytes);
      final asset = seedAssets(ownerId: const UserId('creator')).first;
      final result = await loadGeneratedModelView(workflows, asset);
      expect(Uri.parse(result.source).data!.contentAsBytes(), bytes);
      expect(result.cameraOrbit, isNull);
      expect(workflows.downloads, 1);
      expect(workflows.histories, 0);
    },
  );

  testWidgets('local implementation uses artwork and hides remote history', (
    tester,
  ) async {
    final workflows = _ViewerWorkflows(Uint8List(0), supportsFiles: false);
    final asset = seedAssets(ownerId: const UserId('creator')).first;
    await tester.pumpWidget(
      MaterialApp(
        home: StudioConnection(
          workflows: workflows,
          child: Column(
            children: [
              StudioPreview(asset: asset, interactive: true),
              GenerationHistory(asset: asset),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(AssetArtwork), findsOneWidget);
    expect(find.text('Istorija generisanja'), findsNothing);
    expect(workflows.downloads, 0);
    expect(workflows.histories, 0);
    expect(tester.takeException(), isNull);
  });

  test(
    'initial camera faces SPAR3D and TRELLIS fronts; others keep default',
    () {
      expect(generatedModelCameraOrbit('spar3d'), '180deg 75deg auto');
      expect(generatedModelCameraOrbit('trellis2'), '90deg 75deg auto');
      expect(generatedModelCameraOrbit('hunyuan3d_21'), isNull);
      expect(generatedModelCameraOrbit('fake'), isNull);
      expect(generatedModelCameraOrbit(null), isNull);
      expect(generatedModelCameraOrbit('future-provider'), isNull);
    },
  );

  for (final historyFails in [false, true]) {
    test(
      'model stays viewable with ${historyFails ? 'unavailable' : 'matching'} history',
      () async {
        final bytes = glb({
          'asset': {'version': '2.0'},
        });
        final asset = seedAssets(
          ownerId: const UserId('creator'),
        ).first.copyWith(outputFileId: 'model-1');
        final api = HedrionApiClient(
          'https://studio.test',
          client: MockClient((request) async {
            if (request.url.path.endsWith('/generations')) {
              if (historyFails) {
                return http.Response('{"code":"unavailable"}', 503);
              }
              return http.Response(
                jsonEncode({
                  'jobs': [
                    // A newer job for a different result must not control this GLB.
                    {
                      'id': 'newer-job',
                      'status': 'succeeded',
                      'outputFileId': 'other-output',
                      'provider': 'hunyuan3d_21',
                    },
                    {
                      'id': 'matching-job',
                      'status': 'succeeded',
                      'outputFileId': 'model-1',
                      'provider': 'spar3d',
                    },
                  ],
                }),
                200,
              );
            }
            if (request.url.path.endsWith('/download-url')) {
              return http.Response('{"url":"/api/v1/files/model-1"}', 200);
            }
            return http.Response.bytes(bytes, 200);
          }),
        );
        final result = await loadGeneratedModelView(
          HttpStudioWorkflows(api),
          asset,
        );
        expect(Uri.parse(result.source).data!.contentAsBytes(), bytes);
        expect(result.cameraOrbit, historyFails ? isNull : '180deg 75deg auto');
        api.close();
      },
    );
  }

  test('renderer source contains only the authenticated GLB bytes', () {
    final bytes = glb({
      'asset': {'version': '2.0'},
    });
    final uri = Uri.parse(generatedModelSource(bytes));
    expect(uri.scheme, 'data');
    expect(uri.data!.mimeType, 'model/gltf-binary');
    expect(uri.data!.contentAsBytes(), bytes);
  });

  test('truncated and wrong GLB output is rejected before rendering', () {
    expect(
      () => generatedModelSource(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final bytes = glb({
      'asset': {'version': '2.0'},
    });
    bytes[8] = 0;
    expect(() => generatedModelSource(bytes), throwsFormatException);
  });

  test('private viewer does not fetch external image or buffer resources', () {
    for (final group in ['images', 'buffers']) {
      final bytes = glb({
        'asset': {'version': '2.0'},
        group: [
          {'uri': 'https://untrusted.example/resource'},
        ],
      });
      expect(() => generatedModelSource(bytes), throwsFormatException);
    }
  });
}
