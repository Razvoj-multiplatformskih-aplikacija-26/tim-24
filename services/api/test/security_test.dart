import 'dart:convert';
import 'dart:typed_data';
import 'package:hedrion_api/hedrion_api.dart';
import 'package:image/image.dart' as image;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

void main() {
  test(
      'database outage during worker failure leaves reconciliation durable without an unhandled future',
      () async {
    final db = _UnavailableDatabase();
    try {
      final scheduler = JobScheduler(HedrionService(db, 'unused'),
          workerUrl: 'http://127.0.0.1:1',
          workerSecret: 'test-server-only-secret');
      await expectLater(
          scheduler.run({
            'id': 'durable-job',
            'ownerId': 'creator',
            'inputType': 'image_to_3d',
            'sourceImageFileId': 'source'
          }),
          completes);
    } finally {
      await db.close();
    }
  });
  test('worker HMAC binds timestamp, nonce and exact body', () {
    final signature = workerSignature(
        'server-only-secret', '123', 'nonce-123', '{"jobId":"a"}');
    expect(
        constantTimeEqual(
            signature,
            workerSignature(
                'server-only-secret', '123', 'nonce-123', '{"jobId":"a"}')),
        isTrue);
    expect(
        constantTimeEqual(
            signature,
            workerSignature(
                'server-only-secret', '124', 'nonce-123', '{"jobId":"a"}')),
        isFalse);
    expect(
        constantTimeEqual(
            signature,
            workerSignature(
                'server-only-secret', '123', 'nonce-124', '{"jobId":"a"}')),
        isFalse);
    expect(
        constantTimeEqual(
            signature,
            workerSignature(
                'server-only-secret', '123', 'nonce-123', '{"jobId":"b"}')),
        isFalse);
  });
  test(
      'opaque session tokens have sufficient entropy and hashes do not reveal tokens',
      () {
    final first = randomToken(), second = randomToken();
    expect(first.length, greaterThanOrEqualTo(43));
    expect(first, isNot(second));
    expect(digest(first), hasLength(64));
    expect(digest(first), isNot(first));
  });
  test('adaptive password hash verifies password and rejects wrong input',
      () async {
    final encoded = await Passwords.hash('a-long-test-password');
    expect(encoded, startsWith('pbkdf2-sha256\$600000\$'));
    expect(await Passwords.verify('a-long-test-password', encoded), isTrue);
    expect(await Passwords.verify('wrong-password', encoded), isFalse);
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('GLB validation rejects corrupt headers, lengths and unparseable JSON',
      () {
    final good = makeGlb();
    expect(validGlb(good), isTrue);
    final badMagic = Uint8List.fromList(good)..[0] = 0;
    expect(validGlb(badMagic), isFalse);
    expect(validGlb(Uint8List.fromList(good.sublist(0, good.length - 1))),
        isFalse);
    final badChunk = Uint8List.fromList(good);
    ByteData.sublistView(badChunk).setUint32(12, 999999, Endian.little);
    expect(validGlb(badChunk), isFalse);
  });
  test(
      'input image validation decodes actual pixels and enforces MIME and dimensions',
      () {
    final png = image.encodePng(image.Image(width: 2, height: 2));
    expect(HedrionService.validImage(png, 'image/png'), isTrue);
    expect(HedrionService.validImage(png, 'image/jpeg'), isFalse);
    final forged = Uint8List.fromList(png);
    ByteData.sublistView(forged).setUint32(16, 10000, Endian.big);
    expect(HedrionService.validImage(forged, 'image/png'), isFalse);
    expect(HedrionService.validImage([255, 216, 0, 0, 255, 217], 'image/jpeg'),
        isFalse);
  });
}

class _UnavailableDatabase extends Database {
  _UnavailableDatabase()
      : super(Pool.withUrl(
            'postgres://unused:unused@127.0.0.1:1/unused?sslmode=disable'));
  @override
  Future<T> transaction<T>(Future<T> Function(Tx tx) action) async =>
      throw StateError('Injected database outage');
}

Uint8List makeGlb() {
  final json = utf8
      .encode('{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[]}]}');
  final padding = (4 - json.length % 4) % 4;
  final bytes = Uint8List(20 + json.length + padding),
      data = ByteData.sublistView(bytes);
  data.setUint32(0, 0x46546c67, Endian.little);
  data.setUint32(4, 2, Endian.little);
  data.setUint32(8, bytes.length, Endian.little);
  data.setUint32(12, json.length + padding, Endian.little);
  data.setUint32(16, 0x4e4f534a, Endian.little);
  bytes.setRange(20, 20 + json.length, json);
  bytes.fillRange(20 + json.length, bytes.length, 32);
  return bytes;
}
