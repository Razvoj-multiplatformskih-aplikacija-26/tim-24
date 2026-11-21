import 'dart:typed_data';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'moderation_workflows.dart';
import 'moderation_workflows_scope.dart';
import 'studio_theme.dart';

class SubmissionPreview extends StatefulWidget {
  const SubmissionPreview({super.key, required this.asset});
  final Asset asset;
  @override
  State<SubmissionPreview> createState() => _SubmissionPreviewState();
}

class _SubmissionPreviewState extends State<SubmissionPreview> {
  Future<Uint8List>? bytes;
  (ModerationWorkflows, AssetId, String?)? previewKey;
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
    final workflows = BackofficeConnection.of(context).workflows;
    final key = (workflows, widget.asset.id, widget.asset.previewFileId);
    if (previewKey != key) {
      previewKey = key;
      bytes = workflows.supportsFiles && widget.asset.previewFileId != null
          ? requestPreview(workflows)
          : null;
    }
  }

  Future<Uint8List> requestPreview(ModerationWorkflows workflows) {
    final request = Future<Uint8List>.sync(
      () => workflows.fetchPreview(widget.asset),
    );
    // FutureBuilder subscribes at the next build; an immediate offline failure
    // must be handled during that interval as well as displayed by the builder.
    request.ignore();
    return request;
  }

  @override
  Widget build(BuildContext context) {
    final workflows = BackofficeConnection.of(context).workflows;
    if (!workflows.supportsFiles) {
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
                      onPressed: () => setState(() {
                        bytes = requestPreview(workflows);
                      }),
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
