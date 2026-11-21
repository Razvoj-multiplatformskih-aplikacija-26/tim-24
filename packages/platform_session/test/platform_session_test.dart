import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:platform_session/platform_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'secure adapter survives a new instance and separates application scopes',
    () async {
      const studio = SecureSessionStorage(key: 'studio');
      const backoffice = SecureSessionStorage(key: 'backoffice');
      await studio.write(
        StoredSession(
          token: 'studio-access',
          refreshToken: 'studio-refresh',
          user: {'id': 'a', 'role': 'creator'},
        ),
      );
      await backoffice.write(
        StoredSession(
          token: 'office-access',
          refreshToken: 'office-refresh',
          user: {'id': 'm', 'role': 'moderator'},
        ),
      );
      expect(
        (await const SecureSessionStorage(key: 'studio').read())!.token,
        'studio-access',
      );
      await studio.clear();
      expect(await studio.read(), isNull);
      expect((await backoffice.read())!.token, 'office-access');
    },
  );

  test(
    'invalid stored credentials are deleted instead of crashing restore',
    () async {
      FlutterSecureStorage.setMockInitialValues({
        'studio': 'invalid-session-json',
      });
      const studio = SecureSessionStorage(key: 'studio');
      expect(await studio.read(), isNull);
      expect(await const FlutterSecureStorage().read(key: 'studio'), isNull);
    },
  );
}
