import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'live_backoffice.dart';
import 'studio_theme.dart';

class SubmissionPreview extends StatefulWidget {
  const SubmissionPreview({super.key, required this.asset});
  final Asset asset;
  @override
  State<SubmissionPreview> createState() => _SubmissionPreviewState();
}

class _SubmissionPreviewState extends State<SubmissionPreview> {
  Future<Uint8List>? bytes;
  String? fileId;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  @override
  void didUpdateWidget(SubmissionPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    load();
  }

  void load() {
    final api = BackofficeConnection.maybeOf(context)?.api;
    if (api != null && fileId != widget.asset.previewFileId) {
      fileId = widget.asset.previewFileId;
      bytes = api.fetchPreview(widget.asset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = BackofficeConnection.maybeOf(context)?.api;
    if (api == null) {
      return AssetArtwork(asset: widget.asset, height: 195);
    }
    return SizedBox(
      height: 195,
      width: double.infinity,
      child: bytes == null
          ? const Center(child: Text('Nema dostupnog pregleda.'))
          : FutureBuilder<Uint8List>(
              future: bytes,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  return Image.memory(
                    snapshot.data!,
                    fit: BoxFit.contain,
                    errorBuilder: (_, e, st) =>
                        const Center(child: Text('Pregled nije podržan.')),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: TextButton.icon(
                      onPressed: () => setState(
                        () => bytes = api.fetchPreview(widget.asset),
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
