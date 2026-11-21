import 'json.dart';

/// Lifecycle and license are stable wire names, independent of domain enums.
/// Instants always serialize as ISO-8601 UTC; revisions are integral counters.
final class AssetDto {
  AssetDto({
    required this.id,
    required this.ownerId,
    required this.title,
    required this.lifecycle,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.category = 'props',
    this.projectId,
    List<String> tags = const [],
    this.favorite = false,
    this.revision = 1,
    this.outputFileId,
    this.previewFileId,
    this.rejectionReason,
    this.allowDownload = false,
    this.license = 'ccBy',
  }) : tags = List.unmodifiable(tags);
  final String id, ownerId, title, lifecycle, description, category, license;
  final String? projectId, outputFileId, previewFileId, rejectionReason;
  final DateTime createdAt, updatedAt;
  final List<String> tags;
  final bool favorite, allowDownload;
  final int revision;
  factory AssetDto.fromJson(JsonObject json) => AssetDto(
    id: string(json, 'id'),
    ownerId: string(json, 'ownerId'),
    title: string(json, 'title'),
    lifecycle: string(json, 'lifecycle'),
    createdAt: date(json, 'createdAt'),
    updatedAt: date(json, 'updatedAt'),
    description: string(json, 'description', fallback: ''),
    category: string(json, 'category', fallback: 'props'),
    projectId: optionalString(json, 'projectId'),
    tags: strings(json, 'tags'),
    favorite: boolean(json, 'favorite'),
    revision: integer(json, 'revision', fallback: 1),
    outputFileId: optionalString(json, 'outputFileId'),
    previewFileId: optionalString(json, 'previewFileId'),
    rejectionReason: optionalString(json, 'rejectionReason'),
    allowDownload: boolean(json, 'allowDownload'),
    license: string(json, 'license', fallback: 'ccBy'),
  );
  JsonObject toJson() => {
    'id': id,
    'ownerId': ownerId,
    'title': title,
    'description': description,
    'category': category,
    'projectId': projectId,
    'tags': tags,
    'favorite': favorite,
    'lifecycle': lifecycle,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'revision': revision,
    'outputFileId': outputFileId,
    'previewFileId': previewFileId,
    'rejectionReason': rejectionReason,
    'allowDownload': allowDownload,
    'license': license,
  };
}

final class AssetDraftDto {
  AssetDraftDto({
    required this.title,
    this.description = '',
    this.category = 'props',
    this.projectId,
    List<String> tags = const [],
  }) : tags = List.unmodifiable(tags);
  final String title, description, category;
  final String? projectId;
  final List<String> tags;
  factory AssetDraftDto.fromJson(JsonObject json) => AssetDraftDto(
    title: string(json, 'title', fallback: ''),
    description: string(json, 'description', fallback: ''),
    category: string(json, 'category', fallback: 'props'),
    projectId: optionalString(json, 'projectId'),
    tags: strings(json, 'tags'),
  );
  JsonObject toJson() => {
    'title': title,
    'description': description,
    'category': category,
    'projectId': projectId,
    'tags': tags,
  };
}

/// Patch semantics retain the distinction between absent and cleared project.
final class AssetUpdateDto {
  AssetUpdateDto({
    required this.baseRevision,
    this.title,
    this.description,
    this.category,
    this.favorite,
    this.projectId,
    this.hasProjectId = false,
    List<String>? tags,
  }) : tags = tags == null ? null : List.unmodifiable(tags);
  final int baseRevision;
  final String? title, description, category, projectId;
  final bool? favorite;
  final bool hasProjectId;
  final List<String>? tags;
  factory AssetUpdateDto.fromJson(JsonObject json) => AssetUpdateDto(
    baseRevision: integer(json, 'baseRevision', fallback: 0),
    title: optionalString(json, 'title'),
    description: optionalString(json, 'description'),
    category: optionalString(json, 'category'),
    favorite: json.containsKey('favorite') ? boolean(json, 'favorite') : null,
    projectId: optionalString(json, 'projectId'),
    hasProjectId: json.containsKey('projectId'),
    tags: json.containsKey('tags') ? strings(json, 'tags') : null,
  );
  JsonObject toJson() => {
    'baseRevision': baseRevision,
    if (title != null) 'title': title,
    if (description != null) 'description': description,
    if (category != null) 'category': category,
    if (favorite != null) 'favorite': favorite,
    if (hasProjectId) 'projectId': projectId,
    if (tags != null) 'tags': tags,
  };
}

final class AssetResponseDto {
  const AssetResponseDto(this.asset);
  final AssetDto asset;
  factory AssetResponseDto.fromJson(JsonObject json) => AssetResponseDto(
    AssetDto.fromJson(json['asset'] is Map ? object(json['asset']) : json),
  );
  JsonObject toJson() => {'asset': asset.toJson()};
}

final class AssetPageDto {
  AssetPageDto({required List<AssetDto> assets, this.nextCursor})
    : assets = List.unmodifiable(assets);
  final List<AssetDto> assets;

  /// Opaque cursor returned by the server, passed back without interpretation.
  final String? nextCursor;
  factory AssetPageDto.fromJson(JsonObject json) {
    final values = json['assets'];
    if (values is! List) throw const FormatException('Expected assets');
    return AssetPageDto(
      assets: values.map((v) => AssetDto.fromJson(object(v))).toList(),
      nextCursor: optionalString(json, 'nextCursor'),
    );
  }
  JsonObject toJson() => {
    'assets': assets.map((v) => v.toJson()).toList(),
    'nextCursor': nextCursor,
  };
}

/// The public projection intentionally has no owner ID or private metadata.
final class PublicAssetDto {
  const PublicAssetDto({
    required this.slug,
    required this.title,
    required this.description,
    required this.category,
    required this.license,
    required this.allowDownload,
    this.previewUrl,
    this.modelUrl,
  });
  final String slug, title, description, category, license;
  final bool allowDownload;
  final String? previewUrl, modelUrl;
  factory PublicAssetDto.fromJson(JsonObject json) => PublicAssetDto(
    slug: string(json, 'slug'),
    title: string(json, 'title'),
    description: string(json, 'description', fallback: ''),
    category: string(json, 'category', fallback: 'props'),
    license: string(json, 'license'),
    allowDownload: boolean(json, 'allowDownload'),
    previewUrl: optionalString(json, 'previewUrl'),
    modelUrl: optionalString(json, 'modelUrl'),
  );
  JsonObject toJson() => {
    'slug': slug,
    'title': title,
    'description': description,
    'category': category,
    'license': license,
    'allowDownload': allowDownload,
    if (previewUrl != null) 'previewUrl': previewUrl,
    if (modelUrl != null) 'modelUrl': modelUrl,
  };
}
