/// UI-only catalog for reviewing the redesign without a database or GPU.
/// Run from the repository root: dart run apps/public_web/bin/preview.dart
/// The normal public server always uses its real, approved public API.
library;

import 'dart:convert';
import 'dart:io';
import 'package:domain/domain.dart';
import 'package:hedrion_public_web/hedrion_public_web.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
// Reuse pure Dart sample geometry only in this local design preview.
// ignore: avoid_relative_lib_imports
import '../../mobile/lib/mesh_scene.dart';

class _DesignCatalog implements PublicCatalog {
  final assets = [
    for (final model in SampleModel.values)
      PublicAsset(
        slug: 'demo-${model.name}',
        title: sampleName(model),
        description:
            'Lokalni primer za pregled dizajna. Ovo nije AI generisan model niti stvarna objava zajednice.',
        category: model == SampleModel.bonsai
            ? 'nature'
            : model == SampleModel.portal
            ? 'architecture'
            : 'props',
        author: 'Hedrion · Design demo',
        license: AssetLicense.allRightsReserved,
        allowDownload: false,
        tags: ['demo', 'design-preview'],
      ),
  ];
  @override
  Future<CatalogPage> list({
    String query = '',
    String? category,
    String? cursor,
    int limit = 12,
  }) async => CatalogPage(
    assets
        .where(
          (a) =>
              (category == null || a.category == category) &&
              a.title.toLowerCase().contains(query.toLowerCase()),
        )
        .take(limit)
        .toList(),
  );
  @override
  Future<PublicAsset?> detail(String slug) async =>
      assets.where((a) => a.slug == slug).firstOrNull;
}

String _artwork(SampleModel model) {
  final svg = StringBuffer(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 320 400">',
  );
  svg.write(
    '<ellipse cx="160" cy="363" rx="68" ry="10" fill="#11170c" opacity=".5"/>',
  );
  for (final face in projectScene(SampleScene(model))) {
    final c = face.color;
    final r = (((c >> 16) & 255) * face.light).round();
    final g = (((c >> 8) & 255) * face.light).round();
    final b = ((c & 255) * face.light).round();
    final color = ((r << 16) | (g << 8) | b).toRadixString(16).padLeft(6, '0');
    final points = face.points
        .map(
          (p) =>
              '${(160 + p.$1 * 88).toStringAsFixed(1)},${(196 + p.$2 * 88).toStringAsFixed(1)}',
        )
        .join(' ');
    svg.write(
      '<polygon points="$points" fill="#$color" stroke="#$color" stroke-width=".35"/>',
    );
  }
  svg.write('</svg>');
  return svg.toString();
}

Future<void> main() async {
  final config = PublicWebConfig(
    apiOrigin: Uri.parse('http://127.0.0.1:8081'),
    publicOrigin: Uri.parse('http://127.0.0.1:8081'),
    studioOrigin: Uri.parse('http://127.0.0.1:8082'),
  );
  final site = PublicSite(config, _DesignCatalog());
  final artwork = {
    for (final model in SampleModel.values)
      'demo-${model.name}': _artwork(model),
  };
  final server = await shelf_io.serve(
    (Request request) async {
      final path = request.url.pathSegments;
      if (path.length == 7 &&
          path.take(4).join('/') == 'api/v1/public/assets' &&
          path[5] == 'files' &&
          path[6] == 'preview') {
        final svg = artwork[path[4]];
        if (svg != null) {
          return Response.ok(
            utf8.encode(svg),
            headers: {
              'content-type': 'image/svg+xml',
              'x-hedrion-preview': 'local-design-demo',
            },
          );
        }
      }
      return site.handler(request);
    },
    '127.0.0.1',
    8081,
  );
  stdout.writeln(
    'Design preview (sample content): http://${server.address.host}:${server.port}',
  );
}
