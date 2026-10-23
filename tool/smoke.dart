import 'dart:io';
import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'package:http/http.dart' as http;

/// Actual localhost HTTP smoke: API -> private Python worker -> disk -> moderation -> SSR.
/// Creates its own uniquely named creator; never modifies existing accounts.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/smoke.dart <reference.png>');
    exitCode = 64;
    return;
  }
  final env = Platform.environment;
  final base = env['SMOKE_API_URL'] ?? 'http://127.0.0.1:8080';
  final public = env['SMOKE_PUBLIC_URL'] ?? 'http://127.0.0.1:8081';
  final moderatorEmail = env['MODERATOR_EMAIL'],
      moderatorPassword = env['MODERATOR_PASSWORD'];
  if (moderatorEmail == null || moderatorPassword == null) {
    throw StateError(
      'Set MODERATOR_EMAIL and MODERATOR_PASSWORD for the provisioned test moderator.',
    );
  }
  final creator = HedrionApiClient(base),
      browser = HedrionApiClient(base),
      moderator = HedrionApiClient(base);
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final email = 'smoke-$stamp@example.test', password = 'Smoke-$stamp-Password';
  void check(bool condition, String label) {
    if (!condition) {
      throw StateError(label);
    }
    stdout.writeln('PASS $label');
  }

  try {
    await creator.register(email, password, 'Smoke kreator');
    await browser.login(email, password);
    await moderator.login(moderatorEmail, moderatorPassword);
    final repo = ApiAssetRepository(creator),
        webRepo = ApiAssetRepository(browser);
    final draft = await repo.createAsset(
      AssetDraft(
        title: 'Smoke model $stamp',
        description: 'Automatska end-to-end provera.',
      ),
    );
    final uploaded = await creator.uploadImage(
      draft.id,
      Uint8List.fromList(await File(args.first).readAsBytes()),
      mime: 'image/png',
    );
    check(
      (await webRepo.loadAssets()).any((a) => a.id == draft.id),
      'same account sees uploaded draft from second session',
    );
    final key = 'smoke-generation-$stamp';
    final accepted = await creator.generate(
      draft.id,
      baseRevision: uploaded.revision,
      idempotencyKey: key,
    );
    final replay = await creator.generate(
      draft.id,
      baseRevision: uploaded.revision,
      idempotencyKey: key,
    );
    check(
      (accepted['job'] as Map)['id'] == (replay['job'] as Map)['id'],
      'generation retry returns original accepted job',
    );
    Asset current = uploaded;
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    do {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      current = (await webRepo.loadAssets()).firstWhere(
        (a) => a.id == draft.id,
      );
      if (current.lifecycle == AssetLifecycle.failed) {
        throw StateError('Worker generation failed');
      }
    } while (current.lifecycle != AssetLifecycle.ready &&
        DateTime.now().isBefore(deadline));
    check(
      current.lifecycle == AssetLifecycle.ready,
      'Python fake worker result persisted before ready',
    );
    final glb = await browser.download(current);
    check(
      glb.length > 20 && String.fromCharCodes(glb.take(4)) == 'glTF',
      'second session downloads actual GLB',
    );
    check(
      (await browser.fetchPreview(current)).length > 100,
      'private preview passes metered API',
    );
    final submission = await creator.request(
      'POST',
      '/api/v1/assets/${current.id.value}/submissions',
      key: 'smoke-submit-$stamp',
      revision: current.revision,
      body: {
        'baseRevision': current.revision,
        'confirmRights': true,
        'license': 'ccBy',
        'allowDownload': true,
      },
    );
    final detail = submission['submission'] as Map<String, dynamic>;
    final slug = detail['slug'] as String;
    final before = await http.get(
      Uri.parse('$base/api/v1/public/assets/$slug'),
    );
    check(
      before.statusCode == 404,
      'pending submission is absent from anonymous API',
    );
    final moderation = ApiAssetRepository(moderator, moderator: true);
    final pending = (await moderation.loadAssets()).firstWhere(
      (a) => a.id == current.id,
    );
    await moderation.transitionAsset(
      pending.id,
      AssetLifecycle.published,
      baseRevision: pending.revision,
      idempotencyKey: 'smoke-approve-$stamp',
    );
    final publicDetail = await http.get(Uri.parse('$public/assets/$slug'));
    check(
      publicDetail.statusCode == 200 &&
          publicDetail.body.contains('Smoke model $stamp') &&
          publicDetail.body.contains('<title>'),
      'Jaspr returns approved content as actual HTML without login',
    );
    final publicGlb = await http.get(
      Uri.parse('$base/api/v1/public/assets/$slug/files/model'),
    );
    check(
      publicGlb.statusCode == 200 && publicGlb.bodyBytes.length == glb.length,
      'anonymous download uses same metered gateway',
    );
    final now = (await repo.loadAssets()).firstWhere((a) => a.id == draft.id);
    await repo.updateAsset(
      now.copyWith(title: 'Privatna izmena $stamp'),
      now.revision,
    );
    final html = await http.get(Uri.parse('$public/assets/$slug'));
    check(
      html.body.contains('Smoke model $stamp') &&
          !html.body.contains('Privatna izmena $stamp'),
      'approved public snapshot is stable after private edit',
    );
    stdout.writeln('Smoke completed. Public detail: $public/assets/$slug');
  } finally {
    creator.close();
    browser.close();
    moderator.close();
  }
}
