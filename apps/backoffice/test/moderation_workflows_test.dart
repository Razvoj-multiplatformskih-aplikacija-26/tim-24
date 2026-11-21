import 'dart:convert';
import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:hedrion_backoffice/main.dart';
import 'package:hedrion_backoffice/moderation_workflows.dart';
import 'package:hedrion_backoffice/moderation_workflows_adapters.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final class IndependentStore implements AssetRepository {
  IndependentStore(this.asset);
  Asset asset;
  @override
  Future<List<Asset>> loadAssets() async => [asset];
  @override
  Future<Asset> transitionAsset(
    AssetId id,
    AssetLifecycle target, {
    required int baseRevision,
    String? reason,
    String? idempotencyKey,
  }) async =>
      asset = asset.copyWith(lifecycle: target, revision: baseRevision + 1);
  @override
  Future<Asset> createAsset(AssetDraft draft) async =>
      throw UnimplementedError();
  @override
  Future<Asset> updateAsset(Asset asset, int baseRevision) async =>
      throw UnimplementedError();
  @override
  Future<void> deleteAsset(AssetId id, int baseRevision) async =>
      throw UnimplementedError();
}

final class IndependentWorkflows implements ModerationWorkflows {
  IndependentWorkflows(this.asset);
  final Asset asset;
  int previewRequests = 0;
  @override
  Actor get actor =>
      const Actor(id: UserId('current-staff'), role: UserRole.admin);
  @override
  bool get supportsSamples => false;
  @override
  bool get supportsFiles => true;
  @override
  Map<String, dynamic> get statistics => {
    'reviewedToday': 7,
    'approvalRate': .5,
    'activeJobs': 2,
  };
  @override
  Map<String, dynamic>? submissionFor(AssetId id) => id == asset.id
      ? {
          'id': 'submission',
          'submitterName': 'Autor iz porta',
          'submittedAt': '2026-11-14T12:00:00Z',
          'audit': [],
        }
      : null;
  @override
  void demonstrate(String command) => throw UnimplementedError();
  @override
  Future<Uint8List> fetchPreview(Asset asset) async {
    previewRequests++;
    throw const DomainException(DomainError(ErrorCode.unavailable));
  }
}

void main() {
  final asset = Asset(
    id: const AssetId('one'),
    ownerId: const UserId('author'),
    title: 'Model iz drugog izvora',
    lifecycle: AssetLifecycle.pendingReview,
    createdAt: DateTime.utc(2026, 11, 14),
    updatedAt: DateTime.utc(2026, 11, 14),
    previewFileId: 'preview',
    outputFileId: 'model',
  );

  test(
    'HTTP workflows expose the current login and loaded matching metadata',
    () async {
      final api = HedrionApiClient(
        'http://localhost',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'assets': [asset.toJson()],
              'submissions': [
                {
                  'id': 'submission',
                  'assetId': asset.id.value,
                  'status': 'pending_review',
                  'revision': 1,
                  'submitterName': 'Autor sa servera',
                },
              ],
              'stats': {'reviewedToday': 4, 'activeJobs': 1},
            }),
            200,
          ),
        ),
      );
      addTearDown(api.close);
      api.user = {'id': 'logged-in-admin', 'role': 'admin'};
      final repository = ApiAssetRepository(api, moderator: true);
      final workflows = HttpModerationWorkflows(api, repository: repository);
      await repository.loadAssets();
      expect(workflows.actor.id, const UserId('logged-in-admin'));
      expect(workflows.actor.role, UserRole.admin);
      expect(workflows.statistics['reviewedToday'], 4);
      expect(
        workflows.submissionFor(asset.id)!['submitterName'],
        'Autor sa servera',
      );
      expect(workflows.submissionFor(const AssetId('missing')), isNull);
      api.user = {'id': 'another-staff', 'role': 'moderator'};
      expect(workflows.actor.id, const UserId('another-staff'));
      expect(workflows.actor.role, UserRole.moderator);
      expect(workflows.supportsSamples, isFalse);
    },
  );

  testWidgets(
    'moderation accepts independent workflows for actor, metadata and preview',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workflows = IndependentWorkflows(asset);
      final store = IndependentStore(asset);
      await tester.pumpWidget(
        HedrionBackoffice(repository: store, workflows: workflows),
      );
      await tester.pumpAndSettle();
      expect(find.text('Administrator'), findsOneWidget);
      expect(find.text('Autor: Autor iz porta'), findsOneWidget);
      expect(find.text('DANAS PREGLEDANO'), findsOneWidget);
      expect(find.text('50%'), findsOneWidget);
      expect(find.byTooltip('Demonstracione komande'), findsNothing);
      expect(workflows.previewRequests, 1);
      final retry = find.widgetWithText(TextButton, 'Pokušaj ponovo');
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(workflows.previewRequests, 2);
      expect(tester.takeException(), isNull);
    },
  );
}
