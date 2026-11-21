typedef JsonObject = Map<String, dynamic>;

JsonObject object(Object? value) {
  if (value is! Map) throw const FormatException('Expected an object');
  return Map<String, dynamic>.from(value);
}

String string(JsonObject json, String key, {String? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) return fallback;
  if (value is! String) throw FormatException('Expected string: $key');
  return value;
}

String? optionalString(JsonObject json, String key) =>
    json[key] == null ? null : string(json, key);

int integer(JsonObject json, String key, {int? fallback}) {
  final value = json[key];
  if (value == null && fallback != null) return fallback;
  if (value is! int) throw FormatException('Expected integer: $key');
  return value;
}

bool boolean(JsonObject json, String key, {bool fallback = false}) {
  final value = json[key];
  if (value == null) return fallback;
  if (value is! bool) throw FormatException('Expected boolean: $key');
  return value;
}

List<String> strings(JsonObject json, String key) {
  final value = json[key];
  if (value == null) return const [];
  if (value is! List || value.any((e) => e is! String)) {
    throw FormatException('Expected string list: $key');
  }
  return List<String>.unmodifiable(value.cast<String>());
}

DateTime date(JsonObject json, String key) =>
    DateTime.parse(string(json, key)).toUtc();

DateTime? optionalDate(JsonObject json, String key) =>
    json[key] == null ? null : date(json, key);
