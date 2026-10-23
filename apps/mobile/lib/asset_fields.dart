import 'package:domain/domain.dart';

List<String> parseTags(String value) => value
    .split(',')
    .map((tag) => tag.trim())
    .where((tag) => tag.isNotEmpty)
    .toSet()
    .toList();
String? validateTagsField(String? value) {
  final result = validateDraft(
    AssetDraft(title: 'Model', tags: parseTags(value ?? '')),
  );
  return result.isValid ? null : errorMessage(result.error!);
}
