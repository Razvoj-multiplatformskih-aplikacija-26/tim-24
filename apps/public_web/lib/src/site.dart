import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:jaspr/server.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'catalog.dart';
import 'style.dart';

final class PublicWebConfig {
  PublicWebConfig({
    required this.apiOrigin,
    required this.publicOrigin,
    required this.studioOrigin,
  }) {
    for (final uri in [apiOrigin, publicOrigin, studioOrigin]) {
      if (!['http', 'https'].contains(uri.scheme) ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          uri.hasQuery ||
          uri.hasFragment ||
          !['', '/'].contains(uri.path)) {
        throw ArgumentError('Origins must be absolute HTTP(S) origins.');
      }
    }
  }
  final Uri apiOrigin;
  final Uri publicOrigin;
  final Uri studioOrigin;
}

Component _el(
  String tag, [
  List<Component> children = const [],
  Map<String, String> attributes = const {},
]) => Component.element(tag: tag, attributes: attributes, children: children);

Component _text(String text) => Component.text(text);
Component _paragraph(String text, {String? classes}) =>
    _el('p', [_text(text)], {'class': ?classes});
Component _link(String text, String href, {String? classes}) =>
    _el('a', [_text(text)], {'href': href, 'class': ?classes});

/// Serves real HTML per request. No JavaScript or authenticated client is needed.
final class PublicSite {
  PublicSite(this.config, this.catalog) {
    if (!Jaspr.isInitialized) Jaspr.initializeApp();
  }
  final PublicWebConfig config;
  final PublicCatalog catalog;

  Map<String, String> get _headers => {
    'x-content-type-options': 'nosniff',
    'referrer-policy': 'strict-origin-when-cross-origin',
    'content-security-policy':
        "default-src 'self'; img-src 'self' ${config.apiOrigin.origin}; "
        "style-src 'self'; script-src 'none'; connect-src 'none'; "
        "base-uri 'self'; frame-ancestors 'none'; form-action 'self'",
  };

  shelf.Handler get handler => (request) async {
    if (!['GET', 'HEAD'].contains(request.method)) {
      return shelf.Response(405, headers: {..._headers, 'allow': 'GET, HEAD'});
    }
    shelf.Response response;
    try {
      response = await _route(request);
    } on CatalogFailure {
      response = await _page(
        request,
        title: 'Biblioteka je privremeno nedostupna',
        description: 'Pokušajte ponovo da pristupite javnoj biblioteci.',
        status: 503,
        content: [
          _notice(
            'Biblioteka je privremeno nedostupna',
            'Veza sa serverom nije dostupna. Podaci nisu učitani. Pokušajte ponovo.',
            href: request.requestedUri.path,
            action: 'Pokušaj ponovo',
          ),
        ],
      );
    }
    if (request.method == 'HEAD') {
      return shelf.Response(response.statusCode, headers: response.headers);
    }
    return response;
  };

  Future<shelf.Response> _route(shelf.Request request) async {
    final path = request.url.pathSegments;
    if (request.url.path == 'style.css') {
      return shelf.Response.ok(
        publicStyle,
        headers: {
          ..._headers,
          'content-type': 'text/css; charset=utf-8',
          'cache-control': 'public, max-age=3600',
        },
      );
    }
    if (request.url.path == 'favicon.svg') {
      return shelf.Response.ok(
        publicIcon,
        headers: {
          ..._headers,
          'content-type': 'image/svg+xml',
          'cache-control': 'public, max-age=86400',
        },
      );
    }
    if (request.url.path == 'robots.txt') {
      return shelf.Response.ok(
        'User-agent: *\nAllow: /\nSitemap: ${config.publicOrigin.resolve('/sitemap.xml')}\n',
        headers: {..._headers, 'content-type': 'text/plain; charset=utf-8'},
      );
    }
    if (request.url.path == 'sitemap.xml') return _sitemap();
    if (path.isEmpty || request.url.path.isEmpty) return _landing(request);
    if (path.length == 1 && path[0] == 'assets') return _library(request);
    if (path.length == 2 && path[0] == 'categories') {
      if (!supportedCategories.contains(path[1])) return _notFound(request);
      return _library(request, fixedCategory: path[1]);
    }
    if (path.length == 2 && path[0] == 'assets') {
      if (!_validSlug(path[1])) return _notFound(request);
      final asset = await catalog.detail(path[1]);
      if (asset == null) return _notFound(request);
      return _detail(request, asset);
    }
    if (path.length == 1 &&
        const ['about', 'privacy', 'report'].contains(path[0])) {
      return _information(request, path[0]);
    }
    return _notFound(request);
  }

  Future<shelf.Response> _landing(shelf.Request request) async {
    final featured = await catalog.list(limit: 4);
    return _page(
      request,
      title: 'Hedrion — biblioteka 3D modela za igre',
      description:
          'Istražite odobrene 3D modele zajednice. Pregledajte rekvizite, pronađite licencu i preuzmite GLB kada autor dozvoli.',
      content: [
        _el(
          'section',
          [
            _el(
              'span',
              [_text('OD IDEJE DO VAŠEG SLEDEĆEG SVETA')],
              {'class': 'eyebrow'},
            ),
            _el('h1', [
              _text('Pronađite oblik\n'),
              _el('em', [_text('sledeće ideje.')]),
            ]),
            _paragraph(
              'Biblioteka 3D modela za vaše igre. Istražite radove zajednice, proverite licencu i pronađite rekvizit za svoj sledeći projekat.',
            ),
            _el(
              'div',
              [
                _link('Istražite biblioteku →', '/assets', classes: 'button'),
                _link(
                  'Otvorite svoj studio',
                  config.studioOrigin.toString(),
                  classes: 'button secondary',
                ),
              ],
              {'class': 'actions'},
            ),
          ],
          {'class': 'hero'},
        ),
        _categoryLinks(),
        _sectionTitle('Iz biblioteke zajednice', 'Odobreno za javno deljenje'),
        if (featured.assets.isEmpty)
          _notice(
            'Biblioteka čeka prve radove',
            'Ovde će se pojaviti modeli koje autori predlože i moderator odobri. Privatni modeli ostaju u studiju.',
          )
        else
          _grid(featured.assets),
        _el(
          'div',
          [
            _link(
              'Pogledajte sve modele →',
              '/assets',
              classes: 'button secondary',
            ),
          ],
          {'class': 'actions'},
        ),
      ],
    );
  }

  Future<shelf.Response> _library(
    shelf.Request request, {
    String? fixedCategory,
  }) async {
    final params = request.url.queryParameters;
    final query = (params['q'] ?? '').trim();
    final category =
        fixedCategory ??
        (params['category']?.isNotEmpty == true ? params['category'] : null);
    final page = int.tryParse(params['page'] ?? '1');
    final suppliedCursor = params['cursor'];
    if (query.length > 100 ||
        page == null ||
        page < 1 ||
        page > 100 ||
        (category != null && !supportedCategories.contains(category)) ||
        (suppliedCursor != null && !_validSlug(suppliedCursor))) {
      return _page(
        request,
        title: 'Neispravan filter',
        description: 'Proverite pretragu biblioteke.',
        status: 400,
        content: [
          _notice(
            'Proverite filtere',
            'Pretraga može imati do 100 znakova. Izaberite podržanu kategoriju i stranicu od 1 do 100.',
            href: '/assets',
            action: 'Vrati filtere',
          ),
        ],
      );
    }
    // Cursor URLs need one API request. Direct numbered links are resolved on
    // the server, retaining the API's stable slug ordering and bounded pages.
    var cursor = suppliedCursor;
    if (cursor == null && page > 1) {
      for (var index = 1; index < page; index++) {
        final previous = await catalog.list(
          query: query,
          category: category,
          cursor: cursor,
        );
        cursor = previous.nextCursor;
        if (cursor == null) return _notFound(request);
      }
    }
    final result = await catalog.list(
      query: query,
      category: category,
      cursor: cursor,
    );
    final title = category == null
        ? 'Biblioteka 3D modela'
        : categoryLabel(category);
    return _page(
      request,
      title: '$title — Hedrion',
      description:
          'Javna biblioteka odobrenih 3D modela. $title, licence autora i GLB preuzimanje.',
      noIndex: query.isNotEmpty,
      content: [
        _el('span', [_text('JAVNA BIBLIOTEKA')], {'class': 'eyebrow'}),
        _sectionTitle(title, 'Stranica $page · samo odobreni modeli'),
        _paragraph(
          'Pronađite statične rekvizite za svoju sledeću igru. Svaki rad ima jasno navedenu licencu.',
          classes: 'muted',
        ),
        _searchForm(query, category),
        _categoryLinks(category),
        if (result.assets.isEmpty)
          _notice(
            'Nema modela za ove filtere',
            'Pokušajte kraći naziv ili drugu kategoriju. Samo odobreni radovi ulaze u javnu biblioteku.',
            href: '/assets',
            action: 'Prikaži sve modele',
          )
        else
          _grid(result.assets),
        _el(
          'nav',
          [
            if (page > 1)
              _link(
                '← Prva stranica',
                _libraryUrl(query, category, 1),
                classes: 'button secondary',
              )
            else
              _el('span'),
            _el('span', [_text('Stranica $page')], {'class': 'muted'}),
            if (result.nextCursor != null && page < 100)
              _link(
                'Sledeća stranica →',
                _libraryUrl(query, category, page + 1, result.nextCursor),
                classes: 'button secondary',
              )
            else
              _el('span'),
          ],
          {'class': 'pagination', 'aria-label': 'Stranice biblioteke'},
        ),
      ],
    );
  }

  String _libraryUrl(
    String query,
    String? category,
    int page, [
    String? cursor,
  ]) => Uri(
    path: '/assets',
    queryParameters: {
      if (query.isNotEmpty) 'q': query,
      'category': ?category,
      if (page > 1) 'page': '$page',
      'cursor': ?cursor,
    },
  ).toString();

  Future<shelf.Response> _detail(
    shelf.Request request,
    PublicAsset asset,
  ) => _page(
    request,
    title: '${asset.title} — Hedrion',
    description: asset.description.isEmpty
        ? '${asset.title}, 3D model autora ${asset.author}. ${asset.licenseLabel}.'
        : asset.description.substring(
            0,
            asset.description.length.clamp(0, 180),
          ),
    image: _fileUrl(asset, 'preview'),
    content: [
      _el(
        'div',
        [
          _link('Biblioteka', '/assets'),
          _text(' / '),
          _link(
            categoryLabel(asset.category),
            '/categories/${Uri.encodeComponent(asset.category)}',
          ),
          _text(' / ${asset.title}'),
        ],
        {'class': 'breadcrumb'},
      ),
      _el(
        'article',
        [
          _el(
            'div',
            [
              _el('img', [], {
                'src': _fileUrl(asset, 'preview'),
                'alt': 'Slika pregleda: ${asset.title}',
                'width': '640',
                'height': '480',
              }),
            ],
            {'class': 'preview'},
          ),
          _el('div', [
            _el(
              'span',
              [_text(categoryLabel(asset.category))],
              {'class': 'eyebrow'},
            ),
            _el('h1', [_text(asset.title)]),
            _paragraph('Autor: ${asset.author}', classes: 'muted'),
            _paragraph(asset.description, classes: 'description'),
            _el(
              'dl',
              [
                _el('dt', [_text('Format')]),
                _el('dd', [_text('GLB')]),
                _el('dt', [_text('Licenca')]),
                _el('dd', [_text(asset.licenseLabel)]),
                _el('dt', [_text('Kategorija')]),
                _el('dd', [_text(categoryLabel(asset.category))]),
                _el('dt', [_text('Preuzimanje')]),
                _el('dd', [
                  _text(
                    asset.allowDownload ? 'Dozvoljeno' : 'Samo javni pregled',
                  ),
                ]),
              ],
              {'class': 'details-list'},
            ),
            if (asset.tags.isNotEmpty)
              _el(
                'div',
                [
                  for (final tag in asset.tags)
                    _el('span', [_text('#$tag')], {'class': 'tag'}),
                ],
                {'class': 'categories'},
              ),
            if (asset.allowDownload)
              _link(
                '↓ Preuzmi GLB',
                _fileUrl(asset, 'model'),
                classes: 'button',
              )
            else
              _paragraph(
                'Autor je omogućio javni pregled bez preuzimanja.',
                classes: 'muted',
              ),
            _el('small', [
              _text(
                'Prikazana je slika pregleda. Preuzimanje podleže zajedničkoj dnevnoj kvoti prenosa; server može privremeno odbiti prenos.',
              ),
            ]),
            _el('small', [
              _link(
                'Prijavite problem sa sadržajem',
                '/report?asset=${Uri.encodeQueryComponent(asset.slug)}',
              ),
            ]),
          ]),
        ],
        {'class': 'detail'},
      ),
    ],
  );

  String _fileUrl(PublicAsset asset, String kind) => config.apiOrigin
      .resolve('/api/v1/public/assets/${asset.slug}/files/$kind')
      .toString();

  Component _grid(List<PublicAsset> assets) => _el(
    'div',
    [
      for (final asset in assets)
        _el(
          'article',
          [
            _el(
              'a',
              [
                _el(
                  'div',
                  [
                    _el('img', [], {
                      'src': _fileUrl(asset, 'preview'),
                      'alt': asset.title,
                      'loading': 'lazy',
                      'width': '320',
                      'height': '240',
                    }),
                  ],
                  {'class': 'preview'},
                ),
                _el(
                  'div',
                  [
                    _el(
                      'div',
                      [
                        _el(
                          'span',
                          [_text(categoryLabel(asset.category))],
                          {'class': 'tag'},
                        ),
                        _el(
                          'span',
                          [_text('GLB · ${asset.licenseLabel}')],
                          {'class': 'format'},
                        ),
                      ],
                      {'class': 'tag-row'},
                    ),
                    _el('h3', [_text(asset.title)]),
                    _paragraph('Autor: ${asset.author}'),
                  ],
                  {'class': 'card-body'},
                ),
              ],
              {
                'href': '/assets/${asset.slug}',
                'aria-label': 'Otvori model ${asset.title}',
              },
            ),
          ],
          {'class': 'card'},
        ),
    ],
    {'class': 'grid'},
  );

  Component _sectionTitle(String title, String subtitle) => _el(
    'div',
    [
      _el('h2', [_text(title)]),
      _el('small', [_text(subtitle)]),
    ],
    {'class': 'section-title'},
  );

  Component _categoryLinks([String? selected]) => _el(
    'div',
    [
      _link(
        'Svi modeli',
        '/assets',
        classes: selected == null ? 'category active' : 'category',
      ),
      for (final category in supportedCategories)
        _link(
          categoryLabel(category),
          '/categories/$category',
          classes: selected == category ? 'category active' : 'category',
        ),
    ],
    {'class': 'categories', 'aria-label': 'Kategorije'},
  );

  Component _searchForm(String query, String? category) => _el(
    'form',
    [
      _el(
        'div',
        [
          _el('label', [_text('Pretraga modela')], {'for': 'q'}),
          _el('input', [], {
            'id': 'q',
            'name': 'q',
            'type': 'search',
            'value': query,
            'maxlength': '100',
            'placeholder': 'Naziv modela…',
          }),
        ],
        {'class': 'field'},
      ),
      _el(
        'div',
        [
          _el('label', [_text('Kategorija')], {'for': 'category'}),
          _el(
            'select',
            [
              _el(
                'option',
                [_text('Sve kategorije')],
                {'value': '', if (category == null) 'selected': ''},
              ),
              for (final value in supportedCategories)
                _el(
                  'option',
                  [_text(categoryLabel(value))],
                  {'value': value, if (category == value) 'selected': ''},
                ),
            ],
            {'id': 'category', 'name': 'category'},
          ),
        ],
        {'class': 'field'},
      ),
      _el('button', [_text('Pretraži')], {'type': 'submit', 'class': 'button'}),
    ],
    {
      'action': '/assets',
      'method': 'get',
      'class': 'filters',
      'role': 'search',
    },
  );

  Component _notice(
    String title,
    String description, {
    String? href,
    String? action,
  }) => _el(
    'section',
    [
      _el('h2', [_text(title)]),
      _paragraph(description),
      if (href != null && action != null)
        _link(action, href, classes: 'button secondary'),
    ],
    {'class': 'notice', 'role': 'status'},
  );

  Future<shelf.Response> _notFound(shelf.Request request) => _page(
    request,
    title: 'Stranica nije pronađena — Hedrion',
    description: 'Model nije javno dostupan ili stranica ne postoji.',
    status: 404,
    content: [
      _notice(
        'Stranica nije pronađena',
        'Model je možda povučen iz biblioteke ili ova adresa ne postoji.',
        href: '/assets',
        action: 'Otvori biblioteku',
      ),
    ],
  );

  Future<shelf.Response> _information(shelf.Request request, String page) {
    final (title, sections) = switch (page) {
      'about' => (
        'O Hedrionu',
        <(String, String)>[
          (
            'Studio za stvaranje',
            'Hedrion je studentski AI studio za kreiranje, organizovanje i deljenje statičnih 3D rekvizita za video-igre. Kreatorski studio na telefonu i vebu koristi isti nalog i privatnu biblioteku.',
          ),
          (
            'Privatno dok ne odlučite drugačije',
            'Modeli ulaze u javnu biblioteku tek kada autor zatraži objavljivanje i moderator odobri prijavu. Autor bira licencu i da li dozvoljava preuzimanje.',
          ),
          (
            'Tim',
            'Vasilije Stankovic — SI 100/24 i Jovan Petrovic — SI 115/24. Projekat za predmet Razvoj multiplatformskih aplikacija.',
          ),
        ],
      ),
      'privacy' => (
        'Privatnost',
        <(String, String)>[
          (
            'Anonimna biblioteka',
            'Za pregled ove biblioteke nije potreban nalog. Ovaj veb ne koristi analitičke kolačiće. Javni API vraća odobrene naslove, opise, kategorije, oznake, javni naziv autora i izabranu licencu.',
          ),
          (
            'Privatni modeli i nalozi',
            'Privatnim modelima pristupa njihov vlasnik kroz prijavljeni studio. Adresa e-pošte i interne putanje skladišta nisu deo javnih stranica. Nemojte stavljati lične podatke u sadržaj koji predlažete za objavljivanje.',
          ),
          (
            'Prenos fajlova',
            'Preuzimanja i slike pregleda prolaze kroz server koji ograničava ukupan dnevni prenos fajlova. Hosting može beležiti tehničke podatke zahteva radi rada servisa; politika konkretne javne instalacije mora navesti operatera i rokove čuvanja pre produkcije.',
          ),
        ],
      ),
      _ => (
        'Prijava sadržaja',
        <(String, String)>[
          (
            'Šta navesti u prijavi',
            'Sačuvajte javnu adresu modela, opis problema i podatke o pravima ili drugom osnovu prijave. Ne šaljite poverljive dokumente kroz javne komentare.',
          ),
          (
            'Zahtev za proveru ili uklanjanje',
            'Otvorite prijavu u javnom GitHub repozitorijumu tima. Navedite adresu modela i razlog provere ili povlačenja. Za slanje na GitHub-u potreban je nalog; prijava se šalje tek kada tamo potvrdite formular. Lične podatke i dokaze koji nisu za javnost dostavite operateru instalacije dogovorenim privatnim putem.',
          ),
        ],
      ),
    };
    return _page(
      request,
      title: '$title — Hedrion',
      description: title,
      content: [
        _el(
          'article',
          [
            _el('h1', [_text(title)]),
            for (final (heading, body) in sections) ...[
              _el('h2', [_text(heading)]),
              _paragraph(body),
            ],
            if (page == 'report') ...[
              _link(
                'Otvori prijavu na GitHub-u ↗',
                'https://github.com/Razvoj-multiplatformskih-aplikacija-26/tim-24/issues/new',
                classes: 'button',
              ),
              _paragraph('Za proveru statusa obratite se članovima tima.'),
              _link('Podaci o timu', '/about', classes: 'button secondary'),
            ],
          ],
          {'class': 'prose'},
        ),
      ],
    );
  }

  Future<shelf.Response> _sitemap() async {
    final paths = <String>{
      '/',
      '/assets',
      '/about',
      '/privacy',
      '/report',
      for (final category in supportedCategories) '/categories/$category',
    };
    String? cursor;
    for (var page = 0; page < 100; page++) {
      final result = await catalog.list(cursor: cursor, limit: 100);
      paths.addAll(result.assets.map((asset) => '/assets/${asset.slug}'));
      if (result.nextCursor == null) break;
      if (result.nextCursor == cursor || page == 99) {
        throw const CatalogFailure(503);
      }
      cursor = result.nextCursor;
    }
    const escape = HtmlEscape(HtmlEscapeMode.element);
    final xml =
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
        '${paths.map((path) => '<url><loc>${escape.convert(config.publicOrigin.resolve(path).toString())}</loc></url>').join()}'
        '</urlset>';
    return shelf.Response.ok(
      xml,
      headers: {
        ..._headers,
        'content-type': 'application/xml; charset=utf-8',
        'cache-control': 'no-cache',
      },
    );
  }

  Future<shelf.Response> _page(
    shelf.Request request, {
    required String title,
    required String description,
    required List<Component> content,
    int status = 200,
    String? image,
    bool noIndex = false,
  }) async {
    final canonical = config.publicOrigin
        .replace(
          path: request.requestedUri.path,
          query: request.requestedUri.hasQuery
              ? request.requestedUri.query
              : null,
        )
        .toString();
    final document = Document(
      lang: 'sr-Latn',
      title: title,
      meta: {
        'description': description,
        if (noIndex || status != 200) 'robots': 'noindex, follow',
      },
      head: [
        _el('link', [], {'rel': 'canonical', 'href': canonical}),
        _el('link', [], {'rel': 'stylesheet', 'href': '/style.css'}),
        _el('link', [], {
          'rel': 'icon',
          'href': '/favicon.svg',
          'type': 'image/svg+xml',
        }),
        for (final entry in {
          'og:title': title,
          'og:description': description,
          'og:url': canonical,
          'og:type': image == null ? 'website' : 'article',
          'og:site_name': 'Hedrion',
          'og:image': ?image,
        }.entries)
          _el('meta', [], {'property': entry.key, 'content': entry.value}),
      ],
      body: Component.fragment([
        _link('Pređi na sadržaj', '#content', classes: 'skip'),
        _el('header', [
          _el(
            'nav',
            [
              _el(
                'a',
                [
                  _el(
                    'span',
                    [_text('⬡')],
                    {'class': 'mark', 'aria-hidden': 'true'},
                  ),
                  _text('HEDRION'),
                ],
                {
                  'href': '/',
                  'class': 'brand',
                  'aria-label': 'Hedrion početna',
                },
              ),
              _el(
                'div',
                [
                  _link('Biblioteka', '/assets'),
                  _link('O projektu', '/about'),
                  _link(
                    'Otvorite studio ↗',
                    config.studioOrigin.toString(),
                    classes: 'button',
                  ),
                ],
                {'class': 'nav-links'},
              ),
            ],
            {'aria-label': 'Glavna navigacija'},
          ),
        ]),
        _el('main', content, {'id': 'content'}),
        _el('footer', [
          _el(
            'div',
            [
              _text('Hedrion · Modeli zajednice. Ideje bez granica.'),
              _el(
                'div',
                [
                  _link('O projektu', '/about'),
                  _link('Privatnost', '/privacy'),
                  _link('Prijava sadržaja', '/report'),
                ],
                {'class': 'footer-links'},
              ),
            ],
            {'class': 'footer-inner'},
          ),
        ]),
      ]),
    );
    final rendered = await renderComponent(document, request: request);
    return shelf.Response(
      status,
      body: rendered.body,
      headers: {
        ..._headers,
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-cache',
        if (status == 503) 'retry-after': '30',
        if (noIndex || status != 200) 'x-robots-tag': 'noindex, follow',
      },
    );
  }

  bool _validSlug(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(value);
}
