import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'app_connection.dart';
import 'generated_model_viewer.dart';
import 'studio_theme.dart';
import 'studio_workflows.dart';

/// Resolve orientation alongside the private model download. Missing history
/// must not prevent a valid model from being viewed.
Future<GeneratedModelViewData> loadGeneratedModelView(
  StudioWorkflows workflows,
  Asset asset,
) async {
  final Future<String?> orbit = !workflows.supportsHistory
      ? Future<String?>.value(null)
      : Future.sync(() => workflows.generationHistory(asset.id))
            .then<String?>((history) {
              final jobs = (history['jobs'] as List? ?? []).whereType<Map>();
              final matchingOutput = jobs
                  .where(
                    (job) =>
                        job['status'] == 'succeeded' &&
                        job['outputFileId'] == asset.outputFileId,
                  )
                  .firstOrNull;
              final provider =
                  matchingOutput?['provider'] ??
                  matchingOutput?['modelProvider'];
              return generatedModelCameraOrbit(
                provider is String ? provider : null,
              );
            })
            .timeout(const Duration(seconds: 3), onTimeout: () => null)
            .catchError((_) => null);
  final source = generatedModelSource(await workflows.download(asset));
  return GeneratedModelViewData(source: source, cameraOrbit: await orbit);
}

class StudioPreview extends StatefulWidget {
  const StudioPreview({
    super.key,
    required this.asset,
    this.height = 170,
    this.interactive = false,
  });
  final Asset asset;
  final double height;
  final bool interactive;
  @override
  State<StudioPreview> createState() => _StudioPreviewState();
}

class _StudioPreviewState extends State<StudioPreview> {
  Future<Uint8List>? preview;
  String? fileId;
  Future<GeneratedModelViewData>? model;
  String? outputId;
  bool showImage = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(StudioPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final workflows = StudioConnection.maybeOf(context)?.workflows;
    if (workflows != null &&
        workflows.supportsFiles &&
        widget.interactive &&
        widget.asset.outputFileId != null) {
      if (outputId != widget.asset.outputFileId) {
        outputId = widget.asset.outputFileId;
        showImage = false;
        model = loadGeneratedModelView(workflows, widget.asset);
      }
    } else {
      outputId = null;
      model = null;
    }
    if (workflows == null ||
        !workflows.supportsFiles ||
        widget.asset.previewFileId == null) {
      fileId = null;
      preview = null;
      return;
    }
    // A large preview starts with GLB only. Fetch the PNG when the user selects
    // it; thumbnails never download a whole 3D model.
    if (model != null && !showImage) return;
    if (fileId != widget.asset.previewFileId) {
      fileId = widget.asset.previewFileId;
      preview = workflows.fetchPreview(widget.asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final workflows = StudioConnection.maybeOf(context)?.workflows;
    if (workflows == null || !workflows.supportsFiles) {
      return AssetArtwork(asset: widget.asset, height: widget.height);
    }
    if (widget.asset.previewFileId == null && model == null) {
      return const SizedBox.shrink();
    }
    return Container(
      height: widget.height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff191b18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: model != null && !showImage
          ? Stack(
              children: [
                Positioned.fill(
                  child: FutureBuilder<GeneratedModelViewData>(
                    key: ValueKey(outputId),
                    future: model,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return GeneratedModelViewer(
                          source: snapshot.data!.source,
                          title: widget.asset.title,
                          cameraOrbit: snapshot.data!.cameraOrbit,
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('3D pregled trenutno nije dostupan.'),
                              TextButton.icon(
                                onPressed: () => setState(() {
                                  model = loadGeneratedModelView(
                                    workflows,
                                    widget.asset,
                                  );
                                }),
                                icon: const Icon(Icons.refresh),
                                label: const Text('Pokušaj ponovo'),
                              ),
                            ],
                          ),
                        );
                      }
                      return const Center(
                        child: CircularProgressIndicator(
                          semanticsLabel: 'Učitavanje 3D modela',
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  left: 10,
                  bottom: 10,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      color: const Color(0xbb191b18),
                      child: const Text(
                        'Prevuci za rotaciju · Približi za detalje',
                        style: TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
                if (widget.asset.previewFileId != null)
                  Positioned(
                    right: 8,
                    top: 8,
                    child: FilledButton.tonalIcon(
                      onPressed: () => setState(() {
                        showImage = true;
                        _load();
                      }),
                      icon: const Icon(Icons.image_outlined, size: 17),
                      label: const Text('Slika'),
                    ),
                  ),
              ],
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: FutureBuilder<Uint8List>(
                    future: preview,
                    builder: (context, snapshot) {
                      if (snapshot.hasData) {
                        return Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => const Center(
                            child: Text('Format pregleda nije podržan.'),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Center(
                          child: TextButton.icon(
                            onPressed: () => setState(
                              () => preview = workflows.fetchPreview(
                                widget.asset,
                              ),
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Pokušaj ponovo'),
                          ),
                        );
                      }
                      return const Center(child: CircularProgressIndicator());
                    },
                  ),
                ),
                if (model != null)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: FilledButton.tonalIcon(
                      onPressed: () => setState(() => showImage = false),
                      icon: const Icon(Icons.view_in_ar_outlined, size: 17),
                      label: const Text('3D pregled'),
                    ),
                  ),
              ],
            ),
    );
  }
}
