import 'dart:convert';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:hedrion_mobile/sqlite_persistence.dart';
import 'package:integration_test/integration_test.dart';

/// Run each phase in a separate app process. The host disables Android's real
/// network between prepare and offline, then restores it before sync.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'DEVICE_TEST_PHASE',
    defaultValue: 'prepare',
  );
  const email = String.fromEnvironment('DEVICE_TEST_EMAIL');
  const password = String.fromEnvironment('DEVICE_TEST_PASSWORD');
  const apiUrl = String.fromEnvironment(
    'HEDRION_API_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
  const expectConflict = bool.fromEnvironment('DEVICE_TEST_EXPECT_CONFLICT');
  const markerKey = 'hedrion-device-test-marker';
  const secure = FlutterSecureStorage();
  testWidgets('native SQLite offline process restart / $phase', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Hedrion · provera sinhronizacije')),
        ),
      ),
    );
    await tester.runAsync(() async {
      final api = HedrionApiClient(apiUrl);
      SqliteOfflinePersistence? persistence;
      try {
        if (phase == 'prepare') {
          if (email.isEmpty || password.isEmpty) {
            throw StateError(
              'Supply DEVICE_TEST_EMAIL and DEVICE_TEST_PASSWORD for the isolated local test account.',
            );
          }
          await api.register(email, password, 'Offline test kreator');
          final remote = ApiAssetRepository(api);
          final created = await remote.createAsset(
            AssetDraft(
              title: 'Test ponovnog pokretanja',
              description: 'Originalni opis.',
            ),
          );
          final owner = UserId(api.user!['id'] as String);
          persistence = SqliteOfflinePersistence(owner.value);
          final cache = OfflineAssetRepository(
            remote,
            persistence,
            ownerId: owner,
          );
          await cache.initialize();
          expect(
            (await cache.loadAssets()).any((a) => a.id == created.id),
            isTrue,
          );
          await secure.write(
            key: markerKey,
            value: jsonEncode({
              'token': api.token,
              'refreshToken': api.refreshToken,
              'user': api.user,
              'assetId': created.id.value,
              'expectedTitle': 'Offline izmena posle restarta',
            }),
          );
          // This is the same secure session format used by the production gate.
          await secure.write(
            key: 'hedrion-session',
            value: jsonEncode({
              'token': api.token,
              'refreshToken': api.refreshToken,
              'user': api.user,
            }),
          );
          debugPrint(
            'HEDRION_DEVICE_TEST_PREPARED assetId=${created.id.value}',
          );
        } else {
          final saved = await secure.read(key: markerKey);
          expect(
            saved,
            isNotNull,
            reason:
                'Prepare must run first on this installation without clearing app data.',
          );
          final marker = jsonDecode(saved!) as Map<String, dynamic>;
          api.token = marker['token'] as String;
          api.refreshToken = marker['refreshToken'] as String?;
          api.user = marker['user'] as Map<String, dynamic>;
          final owner = UserId(api.user!['id'] as String),
              id = AssetId(marker['assetId'] as String);
          persistence = SqliteOfflinePersistence(owner.value);
          final remote = ApiAssetRepository(api),
              cache = OfflineAssetRepository(
                ApiAssetRepository(api),
                persistence,
                ownerId: owner,
              );
          await cache.initialize();
          if (phase == 'offline') {
            Object? networkError;
            try {
              await api.me().timeout(const Duration(seconds: 5));
            } catch (e) {
              networkError = e;
            }
            expect(
              networkError,
              isNotNull,
              reason:
                  'Host must actually disable Android networking before this phase.',
            );
            cache.online = false;
            final asset = (await cache.loadAssets()).singleWhere(
              (a) => a.id == id,
            );
            await cache.updateAsset(
              asset.copyWith(
                title: marker['expectedTitle'] as String,
                favorite: true,
              ),
              asset.revision,
            );
            expect(cache.pendingCount, 1);
            expect(
              (await cache.loadAssets())
                  .singleWhere((a) => a.id == id)
                  .favorite,
              isTrue,
            );
            debugPrint('HEDRION_DEVICE_TEST_OFFLINE_PERSISTED outbox=1');
          } else if (phase == 'sync') {
            expect(
              cache.pendingCount,
              1,
              reason:
                  'The outbox must survive the previous app process exiting.',
            );
            cache.online = false;
            expect(
              (await cache.loadAssets()).singleWhere((a) => a.id == id).title,
              marker['expectedTitle'],
            );
            await api.me();
            cache.online = true;
            final count = await cache.sync();
            if (expectConflict) {
              expect(count, 0);
              expect(cache.conflicts.length, 1);
              await cache.resolveConflict(id, keepLocal: true);
              expect(await cache.sync(), 1);
            } else {
              expect(count, 1);
            }
            expect(cache.pendingCount, 0);
            final server = (await remote.loadAssets()).singleWhere(
              (a) => a.id == id,
            );
            expect(server.title, marker['expectedTitle']);
            expect(server.favorite, isTrue);
            debugPrint(
              'HEDRION_DEVICE_TEST_SYNCED outbox=0 conflictResolved=$expectConflict',
            );
          } else {
            throw StateError('Unknown DEVICE_TEST_PHASE: $phase');
          }
        }
      } finally {
        await persistence?.close();
        api.close();
      }
    });
  });
}
