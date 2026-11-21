import 'dart:convert';
import 'package:hedrion_contract/hedrion_contract.dart';
import 'package:test/test.dart';

void main() {
  test('wire asset retains UTC instants and independent string states', () {
    final dto = AssetDto.fromJson({
      'id': 'asset',
      'ownerId': 'creator',
      'title': 'Kameni zmaj',
      'lifecycle': 'futureState',
      'license': 'futureLicense',
      'createdAt': '2026-11-14T13:00:00+02:00',
      'updatedAt': '2026-11-14T12:00:00Z',
      'tags': ['zmaj'],
      'revision': 7,
      'unknownNewServerField': true,
    });
    final wire = jsonDecode(jsonEncode(dto.toJson())) as Map<String, dynamic>;
    expect(wire['createdAt'], '2026-11-14T11:00:00.000Z');
    expect(wire['lifecycle'], 'futureState');
    expect(wire['license'], 'futureLicense');
    expect(wire['revision'], 7);
    expect(dto.tags, ['zmaj']);
    expect(() => dto.tags.add('mutation'), throwsUnsupportedError);
  });

  test('patch differentiates absent project from explicit removal', () {
    final absent = AssetUpdateDto.fromJson({
      'baseRevision': 3,
      'title': 'Novo',
    });
    final removed = AssetUpdateDto.fromJson({
      'baseRevision': 3,
      'projectId': null,
    });
    expect(absent.toJson().containsKey('projectId'), isFalse);
    expect(removed.toJson().containsKey('projectId'), isTrue);
    expect(removed.toJson()['projectId'], isNull);
  });

  test('new error codes and structured data survive JSON without enums', () {
    final dto = ApiErrorDto.fromJson({
      'error': {
        'code': 'newRuleFromFutureServer',
        'details': {'limit': 4, 'current': 4, 'requested': 1},
        'requestId': 'request-42',
      },
    });
    expect(ApiErrorDto.fromJson(dto.toJson()).code, 'newRuleFromFutureServer');
    expect(dto.details, {'limit': 4, 'current': 4, 'requested': 1});
    expect(dto.requestId, 'request-42');
  });

  test('native backoffice login identifies application without cookies', () {
    final dto = LoginRequestDto.fromJson(
      const LoginRequestDto(
        email: 'm@example.test',
        password: 'long-development-password',
        browserSessionScope: 'backoffice',
      ).toJson(),
    );
    expect(dto.browserSession, isFalse);
    expect(dto.browserSessionScope, 'backoffice');
  });

  test(
    'generation keeps selected model, reproducible seed and source prompt',
    () {
      final dto = GenerationRequestDto.fromJson(
        const GenerationRequestDto(
          baseRevision: 8,
          inputType: 'text_to_3d',
          sourcePrompt: 'Mali robot',
          modelProvider: 'trellis2',
          seed: 4294967295,
        ).toJson(),
      );
      expect(dto.modelProvider, 'trellis2');
      expect(dto.seed, 4294967295);
      expect(dto.sourcePrompt, 'Mali robot');
      expect(dto.baseRevision, 8);
    },
  );

  test('malformed primitives fail as a format error at the HTTP boundary', () {
    expect(() => AssetDraftDto.fromJson({'title': 3}), throwsFormatException);
    expect(
      () => AssetUpdateDto.fromJson({'baseRevision': '3'}),
      throwsFormatException,
    );
    expect(
      () => GenerationRequestDto.fromJson({'baseRevision': 3, 'seed': '42'}),
      throwsFormatException,
    );
  });

  test('cursor values remain opaque through query and response', () {
    const cursor = 'opaque /+ marker';
    final request = PageRequestDto.fromQuery(
      const PageRequestDto(cursor: cursor, limit: 12).toQuery(),
    );
    final page = AssetPageDto.fromJson(
      AssetPageDto(assets: [], nextCursor: cursor).toJson(),
    );
    expect(request.cursor, cursor);
    expect(request.limit, 12);
    expect(page.nextCursor, cursor);
  });
}
