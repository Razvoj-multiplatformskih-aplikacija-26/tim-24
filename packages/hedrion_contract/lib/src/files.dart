import 'assets.dart';
import 'json.dart';

final class DownloadLinkDto {
  const DownloadLinkDto({required this.url, this.byteLength, this.mime});

  final String url;
  final int? byteLength;
  final String? mime;

  factory DownloadLinkDto.fromJson(JsonObject json) => DownloadLinkDto(
    url: string(json, 'url'),
    mime: optionalString(json, 'mime'),
    byteLength: json['byteLength'] == null ? null : integer(json, 'byteLength'),
  );

  JsonObject toJson() => {
    'url': url,
    if (byteLength != null) 'byteLength': byteLength,
    if (mime != null) 'mime': mime,
  };
}

final class UploadOfferDto {
  const UploadOfferDto({
    required this.url,
    required this.maxBytes,
    required this.byteLength,
    this.mime,
  });

  final String url;
  final int maxBytes, byteLength;
  final String? mime;

  JsonObject toJson() => {
    'url': url,
    'method': 'PUT',
    'maxBytes': maxBytes,
    'headers': {'Content-Type': mime, 'X-File-Length': '$byteLength'},
    'note':
        'Quota is atomically reserved when the transfer starts; this URL grants no bypass.',
  };
}

final class StoredFileDto {
  const StoredFileDto({
    required this.id,
    required this.byteLength,
    required this.mime,
  });

  final String id, mime;
  final int byteLength;

  factory StoredFileDto.fromJson(JsonObject json) => StoredFileDto(
    id: string(json, 'id'),
    byteLength: integer(json, 'byteLength'),
    mime: string(json, 'mime'),
  );

  JsonObject toJson() => {'id': id, 'byteLength': byteLength, 'mime': mime};
}

final class UploadResultDto {
  const UploadResultDto({required this.asset, this.file});

  final AssetDto asset;
  final StoredFileDto? file;

  factory UploadResultDto.fromJson(JsonObject json) => UploadResultDto(
    asset: AssetResponseDto.fromJson(json).asset,
    file: json['file'] == null
        ? null
        : StoredFileDto.fromJson(object(json['file'])),
  );

  JsonObject toJson() => {
    'asset': asset.toJson(),
    if (file != null) 'file': file!.toJson(),
  };
}
