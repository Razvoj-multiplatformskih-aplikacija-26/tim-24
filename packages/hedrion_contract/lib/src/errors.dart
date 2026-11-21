import 'json.dart';

/// Codes are open strings so an older client can receive a newer rule code.
/// Details carry rule values, never a preformatted user-facing message.
final class ApiErrorDto {
  const ApiErrorDto({
    required this.code,
    this.details,
    this.requestId,
    this.message,
  });
  final String code;
  final Object? details;
  final String? requestId;

  /// Optional legacy diagnostic field. Clients render their local domain text.
  final String? message;
  factory ApiErrorDto.fromJson(JsonObject json) {
    final data = json['error'] is Map ? object(json['error']) : json;
    return ApiErrorDto(
      code: string(data, 'code', fallback: 'unknown'),
      details: data['details'],
      requestId: optionalString(data, 'requestId'),
      message: optionalString(data, 'message'),
    );
  }
  JsonObject toJson() => {
    'code': code,
    if (details != null) 'details': details,
    if (requestId != null) 'requestId': requestId,
    if (message != null) 'message': message,
  };
}
