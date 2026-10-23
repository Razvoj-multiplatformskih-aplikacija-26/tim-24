import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart' as cryptography;

String randomToken([int bytes = 32]) => base64UrlEncode(
      List<int>.generate(bytes, (_) => Random.secure().nextInt(256)),
    ).replaceAll('=', '');
String newId() => randomToken(18);
String digest(String value) => sha256.convert(utf8.encode(value)).toString();

class Passwords {
  static const iterations = 600000;
  static final algorithm = cryptography.Pbkdf2(
    macAlgorithm: cryptography.Hmac.sha256(),
    iterations: iterations,
    bits: 256,
  );
  static Future<String> hash(String password) async {
    final salt = randomToken(16);
    final key = await algorithm.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(password)),
      nonce: utf8.encode(salt),
    );
    return 'pbkdf2-sha256\$$iterations\$$salt\$${base64Encode(await key.extractBytes())}';
  }

  static Future<bool> verify(String password, String encoded) async {
    final parts = encoded.split('\$');
    if (parts.length != 4 ||
        parts[0] != 'pbkdf2-sha256' ||
        parts[1] != '$iterations') {
      return false;
    }
    final key = await algorithm.deriveKey(
      secretKey: cryptography.SecretKey(utf8.encode(password)),
      nonce: utf8.encode(parts[2]),
    );
    return constantTimeEqual(base64Encode(await key.extractBytes()), parts[3]);
  }
}

bool constantTimeEqual(String a, String b) {
  var difference = a.length ^ b.length;
  final max = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < max; i++) {
    difference |= (i < a.length ? a.codeUnitAt(i) : 0) ^
        (i < b.length ? b.codeUnitAt(i) : 0);
  }
  return difference == 0;
}

String workerSignature(
        String secret, String timestamp, String nonce, String body) =>
    Hmac(sha256, utf8.encode(secret))
        .convert(utf8.encode('$timestamp.$nonce.$body'))
        .toString();
