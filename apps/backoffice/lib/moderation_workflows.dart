import 'dart:typed_data';
import 'package:domain/domain.dart';

/// Application operations and metadata consumed by the moderation screens.
/// Adapters choose storage and transport; widgets use the same port throughout.
abstract interface class ModerationWorkflows {
  Actor get actor;
  bool get supportsSamples;
  bool get supportsFiles;
  Map<String, dynamic> get statistics;
  Map<String, dynamic>? submissionFor(AssetId id);
  void demonstrate(String command);
  Future<Uint8List> fetchPreview(Asset asset);
}
