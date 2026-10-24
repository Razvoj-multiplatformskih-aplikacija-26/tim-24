import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'app_connection.dart';
import 'studio_theme.dart';

class StudioPreview extends StatefulWidget {
  const StudioPreview({super.key, required this.asset, this.height = 170});
  final Asset asset;
  final double height;
  @override
  State<StudioPreview> createState() => _StudioPreviewState();
}

class _StudioPreviewState extends State<StudioPreview> {
  Future<Uint8List>? preview;
  String? fileId;
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
    final api = StudioConnection.maybeOf(context)?.client;
    if (api == null || widget.asset.previewFileId == null) {
      fileId = null;
      preview = null;
      return;
    }
    if (fileId != widget.asset.previewFileId) {
      fileId = widget.asset.previewFileId;
      preview = api.fetchPreview(widget.asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = StudioConnection.maybeOf(context)?.client;
    if (api == null) {
      return AssetArtwork(asset: widget.asset, height: widget.height);
    }
    return Container(
      height: widget.height,
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xff191b18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: preview == null
          ? const Center(
              child: Icon(Icons.view_in_ar_outlined, size: 58, color: muted),
            )
          : FutureBuilder<Uint8List>(
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
                        () => preview = api.fetchPreview(widget.asset),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Pokušaj ponovo'),
                    ),
                  );
                }
                return const Center(child: CircularProgressIndicator());
              },
            ),
    );
  }
}
