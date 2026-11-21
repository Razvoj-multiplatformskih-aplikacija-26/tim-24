import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../packages/platform_session/test_support/native_session_flow.dart';

/// Run three times on the same installation with --no-uninstall. Android
/// Keystore-backed storage must persist prepare -> restore and remain empty
/// after restore logs out -> verify-cleared. No real application key is touched.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'KT2_SESSION_PHASE',
    defaultValue: 'prepare',
  );
  testWidgets('Android secure session across process restart / $phase', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('KT2 · native session acceptance')),
        ),
      ),
    );
    await tester.runAsync(
      () => runNativeSessionPhase(
        phase: phase,
        apiUrl: const String.fromEnvironment(
          'HEDRION_API_URL',
          defaultValue: 'http://10.0.2.2:8080',
        ),
        email: const String.fromEnvironment(
          'KT2_SESSION_EMAIL',
          defaultValue: 'creator1@hedrion.test',
        ),
        password: const String.fromEnvironment(
          'KT2_SESSION_PASSWORD',
          defaultValue: 'HedrionCreator123!',
        ),
        key: const String.fromEnvironment(
          'KT2_SESSION_KEY',
          defaultValue: 'kt2-native-test-mobile',
        ),
        scope: 'studio',
        expectedRole: 'creator',
      ),
    );
  });
}
