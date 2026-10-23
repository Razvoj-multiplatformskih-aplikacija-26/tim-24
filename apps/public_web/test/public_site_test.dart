import 'dart:convert';

import 'package:hedrion_public_web/hedrion_public_web.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

http.Response utf8Response(String body, int status) => http.Response(
  body,
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> publicJson(
  String slug, {
  String title = 'Magični sanduk',
  String status = 'approved',
  String lifecycle = 'published',
  String license = 'ccBy',
  bool downloads = true,
}) => {
  'slug': slug,
  'title': title,
  'description': 'Stilizovan rekvizit za igru.',
  'category': 'props',
  'tags': ['fantasy', 'chest'],
  'author': 'Autor zajednice',
  'license': license,
  'allowDownload': downloads,
  'status': status,
  'lifecycle': lifecycle,
  'previewUrl': 'https://unmetered.invalid/model.png',
  'downloadUrl': 'https://unmetered.invalid/model.glb',
};

final config = PublicWebConfig(
  apiOrigin: Uri.parse('http://127.0.0.1:8080'),
  publicOrigin: Uri.parse('https://library.example.test'),
  studioOrigin: Uri.parse('https://studio.example.test'),
);

PublicSite siteWith(http.Client client) =>
    PublicSite(config, HttpPublicCatalog(config.apiOrigin, client));

Future<(Response, String)> request(
  PublicSite site,
  String path, {
  String method = 'GET',
}) async {
  final response = await site.handler(
    Request(method, Uri.parse('https://library.example.test$path')),
  );
  return (response, await response.readAsString());
}

void main() {
  group('public API adapter', () {
    test(
      'only public endpoints requested with no authentication or private DTOs',
      () async {
        final calls = <Uri>[];
        final client = MockClient((req) async {
          calls.add(req.url);
          expect(req.headers['authorization'], isNull);
          expect(req.url.path, startsWith('/api/v1/public/assets'));
          return utf8Response(
            jsonEncode({
              'assets': [publicJson('chest')],
            }),
            200,
          );
        });
        final page = await HttpPublicCatalog(
          config.apiOrigin,
          client,
        ).list(query: 'sanduk', category: 'props', cursor: 'before', limit: 12);
        expect(page.assets.single.title, 'Magični sanduk');
        expect(calls.single.queryParameters, {
          'q': 'sanduk',
          'category': 'props',
          'cursor': 'before',
          'limit': '12',
        });
      },
    );

    test(
      'explicitly private, pending, malformed and unknown-license records filtered',
      () async {
        final client = MockClient(
          (_) async => utf8Response(
            jsonEncode({
              'assets': [
                publicJson('public'),
                publicJson('private', lifecycle: 'ready'),
                publicJson('pending', status: 'pending_review'),
                publicJson('../bad'),
                publicJson('license', license: 'unknown'),
                {
                  'id': 'private-id',
                  'ownerId': 'secret-owner',
                  'email': 'private@example.test',
                },
              ],
            }),
            200,
          ),
        );
        final page = await HttpPublicCatalog(config.apiOrigin, client).list();
        expect(page.assets.map((a) => a.slug), ['public']);
      },
    );

    test(
      'direct detail and wrapped detail supported; private detail hidden',
      () async {
        for (final wrapped in [false, true]) {
          final client = MockClient(
            (_) async => utf8Response(
              jsonEncode(
                wrapped ? {'asset': publicJson('chest')} : publicJson('chest'),
              ),
              200,
            ),
          );
          expect(
            (await HttpPublicCatalog(
              config.apiOrigin,
              client,
            ).detail('chest'))?.slug,
            'chest',
          );
        }
        final client = MockClient(
          (_) async => utf8Response(
            jsonEncode(publicJson('private', lifecycle: 'draft')),
            200,
          ),
        );
        expect(
          await HttpPublicCatalog(config.apiOrigin, client).detail('private'),
          isNull,
        );
      },
    );
  });

  group('Jaspr HTML responses', () {
    test(
      'case-sensitive generated slugs survive listing, detail and cursor URLs',
      () async {
        const slug = 'smoke-model-1792595665460639-mWM7CXkJ';
        final calls = <Uri>[];
        final client = MockClient((req) async {
          calls.add(req.url);
          if (req.url.path == '/api/v1/public/assets/$slug') {
            return utf8Response(jsonEncode(publicJson(slug)), 200);
          }
          return utf8Response(
            jsonEncode({
              'assets': [publicJson(slug)],
            }),
            200,
          );
        });
        final site = siteWith(client);
        final (listing, listingHtml) = await request(site, '/assets');
        expect(listing.statusCode, 200);
        expect(listingHtml, contains('/assets/$slug'));
        final (detail, detailHtml) = await request(site, '/assets/$slug');
        expect(detail.statusCode, 200);
        expect(detailHtml, contains('<h1>Magični sanduk</h1>'));
        expect(detailHtml, contains('/public/assets/$slug/files/model'));
        final (cursorPage, _) = await request(
          site,
          '/assets?page=2&cursor=$slug',
        );
        expect(cursorPage.statusCode, 200);
        expect(calls[1].path, '/api/v1/public/assets/$slug');
        expect(calls.last.queryParameters['cursor'], slug);
      },
    );

    test(
      'renders actual anonymous HTML content, canonical metadata and metered links',
      () async {
        final client = MockClient(
          (_) async => utf8Response(jsonEncode(publicJson('chest')), 200),
        );
        final (response, html) = await request(
          siteWith(client),
          '/assets/chest',
        );
        expect(response.statusCode, 200);
        expect(html, contains('<!DOCTYPE html>'));
        expect(html, contains('lang="sr-Latn"'));
        expect(html, contains('<h1>Magični sanduk</h1>'));
        expect(html, contains('Stilizovan rekvizit za igru.'));
        expect(html, contains('Autor zajednice'));
        expect(html, contains('CC BY 4.0'));
        expect(
          html,
          contains(
            'rel="canonical" href="https://library.example.test/assets/chest"',
          ),
        );
        expect(html, contains('property="og:image"'));
        expect(
          html,
          contains(
            'http://127.0.0.1:8080/api/v1/public/assets/chest/files/model',
          ),
        );
        expect(html, isNot(contains('unmetered.invalid')));
        expect(html, isNot(contains('<script')));
        expect(
          response.headers['content-security-policy'],
          contains("script-src 'none'"),
        );
      },
    );

    test('untrusted text and attributes escaped by Jaspr', () async {
      final asset = publicJson('escaped', title: '<script>alert("x")</script>');
      asset['description'] = '<img src=x onerror=alert(1)>';
      asset['author'] = '<b>unsafe</b>';
      final client = MockClient(
        (_) async => utf8Response(jsonEncode(asset), 200),
      );
      final (_, html) = await request(siteWith(client), '/assets/escaped');
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('&lt;img'));
      expect(html, isNot(contains('<script>')));
      expect(html, isNot(contains('<b>unsafe')));
    });

    test(
      'download denied by author or restricted license never exposes model link',
      () async {
        for (final asset in [
          publicJson('chest', downloads: false),
          publicJson('chest', license: 'allRightsReserved'),
        ]) {
          final client = MockClient(
            (_) async => utf8Response(jsonEncode(asset), 200),
          );
          final (_, html) = await request(siteWith(client), '/assets/chest');
          expect(html, isNot(contains('/files/model')));
          expect(html, contains('Samo javni pregled'));
        }
      },
    );

    test(
      'search and category rendered server-side with stable cursor pagination',
      () async {
        final records = List.generate(
          12,
          (i) => publicJson('model-${i.toString().padLeft(2, '0')}'),
        );
        final client = MockClient((req) async {
          expect(req.url.queryParameters['q'], 'sanduk');
          expect(req.url.queryParameters['category'], 'props');
          return utf8Response(jsonEncode({'assets': records}), 200);
        });
        final (response, html) = await request(
          siteWith(client),
          '/assets?q=sanduk&category=props',
        );
        expect(response.statusCode, 200);
        expect(html, contains('value="sanduk"'));
        expect(html, contains('page=2'));
        expect(html, contains('cursor=model-11'));
        expect(html, contains('noindex, follow'));
      },
    );

    test(
      'direct page number advances server cursor without skipping data',
      () async {
        final cursors = <String?>[];
        final client = MockClient((req) async {
          cursors.add(req.url.queryParameters['cursor']);
          final start = cursors.length == 1 ? 0 : 12;
          return utf8Response(
            jsonEncode({
              'assets': List.generate(
                12,
                (i) => publicJson(
                  'model-${(start + i).toString().padLeft(2, '0')}',
                ),
              ),
            }),
            200,
          );
        });
        final (_, html) = await request(siteWith(client), '/assets?page=2');
        expect(cursors, [null, 'model-11']);
        expect(html, contains('/assets/model-12'));
        expect(html, isNot(contains('/assets/model-00')));
        expect(html, contains('Stranica 2'));
      },
    );

    test('empty library honest and no fabricated models', () async {
      final client = MockClient(
        (_) async => utf8Response('{"assets":[]}', 200),
      );
      final (response, html) = await request(siteWith(client), '/assets');
      expect(response.statusCode, 200);
      expect(html, contains('Nema modela za ove filtere'));
      expect(html, isNot(contains('class="card"')));
    });

    test(
      'API failure returns retryable 503 without private failure details',
      () async {
        final client = MockClient(
          (_) async => utf8Response('private diagnostic secret', 500),
        );
        final (response, html) = await request(siteWith(client), '/assets');
        expect(response.statusCode, 503);
        expect(response.headers['retry-after'], '30');
        expect(html, contains('Pokušaj ponovo'));
        expect(html, isNot(contains('private diagnostic')));
      },
    );

    test('missing or nonpublic detail returns 404 and noindex', () async {
      for (final status in [200, 404]) {
        final client = MockClient(
          (_) async => utf8Response(
            status == 200
                ? jsonEncode(publicJson('draft', lifecycle: 'draft'))
                : '{}',
            status,
          ),
        );
        final (response, html) = await request(
          siteWith(client),
          '/assets/draft',
        );
        expect(response.statusCode, 404);
        expect(html, contains('Stranica nije pronađena'));
        expect(html, isNot(contains('Magični sanduk')));
        expect(response.headers['x-robots-tag'], contains('noindex'));
      }
    });

    test(
      'sitemap only includes approved slugs and robots points to canonical origin',
      () async {
        final client = MockClient(
          (_) async => utf8Response(
            jsonEncode({
              'assets': [
                publicJson('approved'),
                publicJson('private', lifecycle: 'ready'),
              ],
            }),
            200,
          ),
        );
        final site = siteWith(client);
        final (response, xml) = await request(site, '/sitemap.xml');
        expect(response.statusCode, 200);
        expect(response.headers['content-type'], startsWith('application/xml'));
        expect(xml, contains('https://library.example.test/assets/approved'));
        expect(xml, isNot(contains('/assets/private')));
        final (_, robots) = await request(site, '/robots.txt');
        expect(
          robots,
          contains('Sitemap: https://library.example.test/sitemap.xml'),
        );
      },
    );

    test('static information remains accessible while API offline', () async {
      final client = MockClient((_) async => throw StateError('offline'));
      for (final path in [
        '/about',
        '/privacy',
        '/report',
        '/style.css',
        '/favicon.svg',
      ]) {
        final (response, body) = await request(siteWith(client), path);
        expect(response.statusCode, 200, reason: path);
        expect(body, isNotEmpty);
      }
    });

    test(
      'invalid filters rejected and unsupported methods cannot mutate',
      () async {
        final client = MockClient(
          (_) async => throw StateError('must not fetch'),
        );
        final site = siteWith(client);
        for (final path in [
          '/assets?page=0',
          '/assets?page=101',
          '/assets?category=private',
        ]) {
          final (response, _) = await request(site, path);
          expect(response.statusCode, 400);
        }
        expect((await request(site, '/categories/private')).$1.statusCode, 404);
        expect(
          (await request(site, '/assets', method: 'POST')).$1.statusCode,
          405,
        );
      },
    );
  });
}
