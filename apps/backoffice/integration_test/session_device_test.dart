import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../../../packages/platform_session/test_support/native_session_flow.dart';

/// Launch each phase in a separate Windows process. Preserve app data between
/// invocations; this uses only an isolated kt2-native-test-* secure-store key.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const phase = String.fromEnvironment(
    'KT2_SESSION_PHASE',
    defaultValue: 'prepare',
  );
  testWidgets('Windows secure session across process restart / $phase', (
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
          defaultValue: 'http://127.0.0.1:8080',
        ),
        email: const String.fromEnvironment(
          'KT2_SESSION_EMAIL',
          defaultValue: 'moderator@hedrion.test',
        ),
        password: const String.fromEnvironment(
          'KT2_SESSION_PASSWORD',
          defaultValue: 'HedrionModerator123!',
        ),
        key: const String.fromEnvironment(
          'KT2_SESSION_KEY',
          defaultValue: 'kt2-native-test-backoffice',
        ),
        scope: 'backoffice',
        expectedRole: 'moderator',
      ),
    );
  });
}
