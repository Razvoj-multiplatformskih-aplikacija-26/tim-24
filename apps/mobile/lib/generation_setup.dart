import 'dart:typed_data';
import 'mesh_scene.dart';

enum GenerationFlow {
  textTo3d('Text to 3D', 'text-to-3d'),
  imageTo3d('Image to 3D', 'image-to-3d'),
  textToImage('Text to Image', 'text-to-image');

  const GenerationFlow(this.label, this.route);
  final String label, route;
  static GenerationFlow fromRoute(String? route) =>
      values.where((v) => v.route == route).firstOrNull ?? textTo3d;
}

/// Provider-neutral request. No Modal endpoint or provider credentials in UI.
class GenerationSetup {
  const GenerationSetup({
    required this.flow,
    required this.prompt,
    required this.modelId,
    this.lowPoly = false,
    this.textured = true,
    this.pose = false,
    this.enhance = true,
    this.seed = 42,
    this.imageName,
    this.imageBytes,
  });
  final GenerationFlow flow;
  final String prompt, modelId;
  final bool lowPoly, textured, pose, enhance;
  final int seed;
  final String? imageName;
  final Uint8List? imageBytes;

  Map<String, Object?> toJson() => {
    'flow': flow.route,
    'prompt': prompt,
    'model': modelId,
    'lowPoly': lowPoly,
    'textured': textured,
    'pose': pose,
    'enhance': enhance,
    'seed': seed,
    'imageName': imageName,
  };
}

class GenerationPreview {
  const GenerationPreview({
    required this.setup,
    required this.sample,
    required this.createdAt,
  });
  final GenerationSetup setup;
  final SampleModel sample;
  final DateTime createdAt;
  String get title => setup.prompt.trim().isEmpty
      ? setup.imageName ?? 'Image study'
      : setup.prompt.trim().split('\n').first;
}

/// Replace this port with the selected generation provider later.
abstract interface class GenerationGateway {
  Future<GenerationPreview> preview(GenerationSetup setup);
}

class LocalPreviewGateway implements GenerationGateway {
  const LocalPreviewGateway();
  @override
  Future<GenerationPreview> preview(GenerationSetup setup) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final text = setup.prompt.toLowerCase();
    final sample = text.contains('crystal')
        ? SampleModel.crystal
        : text.contains('tree') || text.contains('bonsai')
        ? SampleModel.bonsai
        : text.contains('vase') || text.contains('vessel')
        ? SampleModel.vessel
        : text.contains('chest')
        ? SampleModel.chest
        : text.contains('portal')
        ? SampleModel.portal
        : SampleModel.sentinel;
    return GenerationPreview(
      setup: setup,
      sample: sample,
      createdAt: DateTime.now(),
    );
  }
}
