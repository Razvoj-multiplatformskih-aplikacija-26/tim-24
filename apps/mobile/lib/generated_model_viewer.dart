import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

/// Observed exporter axes: SPAR3D faces -Z and TRELLIS.2 faces +X.
/// Other providers keep model-viewer's default +Z view and automatic framing.
String? generatedModelCameraOrbit(String? provider) => switch (provider) {
  'spar3d' => '180deg 75deg auto',
  'trellis2' => '90deg 75deg auto',
  _ => null,
};

class GeneratedModelViewData {
  const GeneratedModelViewData({required this.source, this.cameraOrbit});
  final String source;
  final String? cameraOrbit;
}

/// The renderer receives authenticated, already downloaded bytes. Session
/// credentials are never included in a model URL, HTML, or renderer logs.
String generatedModelSource(Uint8List bytes) {
  if (bytes.length < 28 || bytes.length > 200000000) {
    throw const FormatException('Neispravan ili prevelik GLB model.');
  }
  final header = ByteData.sublistView(bytes);
  final jsonLength = header.getUint32(12, Endian.little);
  if (header.getUint32(0, Endian.little) != 0x46546c67 ||
      header.getUint32(4, Endian.little) != 2 ||
      header.getUint32(8, Endian.little) != bytes.length ||
      header.getUint32(16, Endian.little) != 0x4e4f534a ||
      jsonLength == 0 ||
      jsonLength % 4 != 0 ||
      jsonLength > 16000000 ||
      20 + jsonLength > bytes.length) {
    throw const FormatException('Rezultat nije ispravan GLB 2.0 model.');
  }
  final document = jsonDecode(utf8.decode(bytes.sublist(20, 20 + jsonLength)));
  if (document is! Map || (document['asset'] as Map?)?['version'] != '2.0') {
    throw const FormatException('Rezultat nije ispravan GLB 2.0 model.');
  }
  for (final group in ['buffers', 'images']) {
    final values = document[group];
    if (values != null && values is! List) {
      throw const FormatException('Neispravni resursi modela.');
    }
    for (final value in values as List? ?? const []) {
      if (value is! Map) {
        throw const FormatException('Neispravni resursi modela.');
      }
      final uri = value['uri'];
      if (uri != null && (uri is! String || !uri.startsWith('data:'))) {
        throw const FormatException('Model sadrži spoljašnje resurse.');
      }
    }
  }
  return Uri.dataFromBytes(bytes, mimeType: 'model/gltf-binary').toString();
}

class GeneratedModelViewer extends StatelessWidget {
  const GeneratedModelViewer({
    super.key,
    required this.source,
    required this.title,
    this.cameraOrbit,
  });

  final String source, title;
  final String? cameraOrbit;

  @override
  Widget build(BuildContext context) => ModelViewer(
    key: ValueKey((source, cameraOrbit)),
    src: source,
    alt: 'Generisani 3D model: $title',
    backgroundColor: const Color(0xff191b18),
    cameraControls: true,
    cameraOrbit: cameraOrbit,
    autoRotate: false,
    ar: false,
    environmentImage: 'neutral',
    exposure: 1,
    shadowIntensity: 0.7,
    loading: Loading.eager,
    debugLogging: false,
  );
}
