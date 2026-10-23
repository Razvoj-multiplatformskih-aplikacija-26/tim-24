import 'dart:io';
import 'package:hedrion_api/hedrion_api.dart';

Future<void> main() async {
  final env = Platform.environment,
      url = env['DATABASE_URL'],
      email = env['MODERATOR_EMAIL'],
      password = env['MODERATOR_PASSWORD'];
  if (url == null ||
      email == null ||
      password == null ||
      password.length < 12) {
    stderr.writeln(
        'Set DATABASE_URL, MODERATOR_EMAIL and MODERATOR_PASSWORD (12+ characters). No built-in privileged passwords.');
    exitCode = 64;
    return;
  }
  final db = Database.connect(url);
  try {
    final hash = await Passwords.hash(password);
    await db.transaction((tx) async {
      if (await tx.one('SELECT id FROM users WHERE email=@email',
              {'email': email.toLowerCase()}) !=
          null) {
        throw const ApiFailure(409, 'existingUser',
            'Account exists. Privilege changes must be reviewed separately.');
      }
      await tx.query(
          "INSERT INTO users(id,email,password_hash,display_name,role) VALUES(@id,@email,@hash,@name,'moderator')",
          {
            'id': newId(),
            'email': email.toLowerCase(),
            'hash': hash,
            'name': env['MODERATOR_NAME'] ?? 'Moderator'
          });
    });
    stdout.writeln('Moderator created.');
  } finally {
    await db.close();
  }
}
