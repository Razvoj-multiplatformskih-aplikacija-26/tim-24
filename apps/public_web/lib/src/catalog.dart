import 'dart:convert';

import 'package:domain/domain.dart';
import 'package:http/http.dart' as http;

final class CatalogFailure implements Exception {
  const CatalogFailure(this.statusCode);
  final int statusCode;
}

/// Public DTO deliberately excludes private IDs, e-mail and storage keys.
final class PublicAsset {
  const PublicAsset({
    required this.slug,
    required this.title,
    required this.description,
    required this.category,
    required this.author,
    required this.license,
    required this.allowDownload,
    required this.tags,
  });

  final String slug;
  final String title;
  final String description;
  final String category;
  final String author;
  final AssetLicense license;
  final bool allowDownload;
  final List<String> tags;

  static PublicAsset? fromJson(Map<String, dynamic> json) {
    // The public API is authoritative; reject explicitly nonpublic payloads too.
    if (json['lifecycle'] != null &&
        json['lifecycle'] != AssetLifecycle.published.name) {
      return null;
    }
    if (json['status'] != null &&
        json['status'] != PublicationStatus.approved.name) {
      return null;
    }
    final slug = json['slug'];
    final title = json['title'];
    if (slug is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,200}$').hasMatch(slug) ||
        title is! String ||
        title.isEmpty) {
      return null;
    }
    final licenseName = json['license'];
    final license = AssetLicense.values.where((v) => v.name == licenseName);
    if (license.isEmpty) return null;
    final tags = json['tags'];
    return PublicAsset(
      slug: slug,
      title: title,
      description: json['description'] is String
          ? json['description'] as String
          : '',
      category: json['category'] is String
          ? json['category'] as String
          : 'props',
      author: json['author'] is String ? json['author'] as String : 'Autor',
      license: license.first,
      allowDownload:
          json['allowDownload'] == true &&
          license.first != AssetLicense.allRightsReserved,
      tags: List.unmodifiable(
        tags is List ? tags.whereType<String>().take(20) : <String>[],
      ),
    );
  }

  String get licenseLabel => switch (license) {
    AssetLicense.ccBy => 'CC BY 4.0',
    AssetLicense.cc0 => 'CC0 1.0',
    AssetLicense.allRightsReserved => 'Sva prava zadržana',
  };
}

final class CatalogPage {
  const CatalogPage(this.assets, {this.nextCursor});
  final List<PublicAsset> assets;
  final String? nextCursor;
}

abstract interface class PublicCatalog {
  Future<CatalogPage> list({
    String query = '',
    String? category,
    String? cursor,
    int limit = 12,
  });
  Future<PublicAsset?> detail(String slug);
}

final class HttpPublicCatalog implements PublicCatalog {
  HttpPublicCatalog(this.apiOrigin, this.client);
  final Uri apiOrigin;
  final http.Client client;

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String>? query,
  ]) async {
    try {
      final response = await client
          .get(apiOrigin.replace(path: path, queryParameters: query))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode == 404) throw const CatalogFailure(404);
      if (response.statusCode != 200 || response.bodyBytes.length > 2_000_000) {
        throw const CatalogFailure(503);
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map<String, dynamic>) throw const CatalogFailure(502);
      return data;
    } on CatalogFailure {
      rethrow;
    } catch (_) {
      throw const CatalogFailure(503);
    }
  }

  @override
  Future<CatalogPage> list({
    String query = '',
    String? category,
    String? cursor,
    int limit = 12,
  }) async {
    final boundedLimit = limit.clamp(1, 100);
    final data = await _get('/api/v1/public/assets', {
      if (query.isNotEmpty) 'q': query,
      'category': ?category,
      'cursor': ?cursor,
      'limit': '$boundedLimit',
    });
    final records = data['assets'];
    if (records is! List) throw const CatalogFailure(502);
    final assets = records
        .whereType<Map<String, dynamic>>()
        .map(PublicAsset.fromJson)
        .whereType<PublicAsset>()
        .toList(growable: false);
    final rawCursor = records.isEmpty || records.last is! Map
        ? null
        : (records.last as Map)['slug'];
    return CatalogPage(
      assets,
      nextCursor: records.length >= boundedLimit && rawCursor is String
          ? rawCursor
          : null,
    );
  }

  @override
  Future<PublicAsset?> detail(String slug) async {
    try {
      final data = await _get('/api/v1/public/assets/$slug');
      final record = data['asset'] is Map<String, dynamic>
          ? data['asset'] as Map<String, dynamic>
          : data;
      return PublicAsset.fromJson(record);
    } on CatalogFailure catch (error) {
      if (error.statusCode == 404) return null;
      rethrow;
    }
  }
}

String categoryLabel(String category) => switch (category) {
  'props' => 'Rekviziti',
  'weapons' => 'Oružje',
  'furniture' => 'Nameštaj',
  'nature' => 'Priroda',
  'architecture' => 'Arhitektura',
  _ => category,
};
