import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app_connection.dart';
import 'studio_theme.dart';

class GenerationHistory extends StatefulWidget {
  const GenerationHistory({super.key, required this.asset});
  final Asset asset;
  @override
  State<GenerationHistory> createState() => _GenerationHistoryState();
}

class _GenerationHistoryState extends State<GenerationHistory> {
  Future<Map<String, dynamic>>? history;
  int? revision;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load();
  }

  @override
  void didUpdateWidget(GenerationHistory oldWidget) {
    super.didUpdateWidget(oldWidget);
    load();
  }

  void load() {
    final api = StudioConnection.maybeOf(context)?.client;
    if (api != null && revision != widget.asset.revision) {
      revision = widget.asset.revision;
      history = api.request(
        'GET',
        '/api/v1/assets/${widget.asset.id.value}/generations',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (StudioConnection.maybeOf(context)?.client == null) {
      return const SizedBox.shrink();
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: history,
      builder: (context, snapshot) {
        final jobs = (snapshot.data?['jobs'] as List? ?? [])
            .map((value) => Map<String, dynamic>.from(value as Map))
            .toList();
        final successful = jobs
            .where(
              (job) =>
                  job['status'] == 'succeeded' &&
                  job['outputFileId'] == widget.asset.outputFileId,
            )
            .firstOrNull;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (successful != null) ...[
              _OutputMetadata(job: successful),
              const SizedBox(height: 16),
            ],
            Card(
              child: ExpansionTile(
                initiallyExpanded:
                    widget.asset.lifecycle == AssetLifecycle.failed,
                title: const Text('Istorija generisanja'),
                subtitle: const Text(
                  'Svaki novi pokušaj je poseban serverski posao.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                children: [
                  if (snapshot.hasError)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        revision = null;
                        load();
                      }),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Pokušaj ponovo'),
                    )
                  else if (!snapshot.hasData)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    )
                  else if (jobs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text(
                        'Generisanje još nije zatraženo.',
                        style: TextStyle(color: muted),
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (final value in jobs) _job(context, value),
                      ],
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _job(BuildContext context, Map<String, dynamic> job) {
    final status = job['status'] as String?;
    final label = switch (status) {
      'queued' => 'U redu',
      'running' => 'Obrada',
      'succeeded' => 'Završeno',
      'failed' => 'Neuspelo',
      'cancelled' => 'Otkazano',
      _ => 'Nacrt',
    };
    return ListTile(
      leading: Icon(
        status == 'failed' ? Icons.error_outline : Icons.layers_outlined,
        color: status == 'failed' ? const Color(0xffffa49e) : accent,
      ),
      title: Text(label),
      subtitle: Text(
        '${job['provider'] == 'fake' ? 'Demonstracioni provider · deterministički GLB (nije AI)' : 'Provider: ${job['provider'] ?? 'serverski adapter'}'}\n${job['failureMessage'] ?? job['failureCode'] ?? job['acceptedAt'] ?? ''}',
        style: const TextStyle(color: muted, fontSize: 11),
      ),
      isThreeLine: true,
      trailing: status == 'queued'
          ? TextButton(
              onPressed: () => cancel(context, job['id'] as String),
              child: const Text('Otkaži'),
            )
          : null,
    );
  }

  Future<void> cancel(BuildContext context, String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Otkazati zahtev?'),
        content: const Text(
          'Prihvaćeni zahtev i dalje troši mesto u dnevnoj kvoti. Novi pokušaj pravi novi posao.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Otkaži zahtev'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) {
      return;
    }
    try {
      await StudioConnection.maybeOf(
        context,
      )!.client!.request('POST', '/api/v1/generations/$id/cancel');
      if (context.mounted) {
        context.read<AssetBloc>().add(const LoadAssets());
      }
    } on DomainException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e.error))));
      }
    }
  }
}

class _OutputMetadata extends StatelessWidget {
  const _OutputMetadata({required this.job});
  final Map<String, dynamic> job;
  @override
  Widget build(BuildContext context) {
    final metadata = Map<String, dynamic>.from(
          job['metadata'] as Map? ?? const {},
        ),
        metrics = Map<String, dynamic>.from(job['metrics'] as Map? ?? const {});
    final bytes = metrics['output_size_bytes'] as num?;
    Widget item(String title, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: muted, fontSize: 11)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tehnički podaci rezultata',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 18,
              children: [
                item('FORMAT', 'GLB'),
                if (bytes != null)
                  item(
                    'VELIČINA',
                    '${bytes.toInt()} bajtova · ${(bytes / 1000000).toStringAsFixed(2)} MB',
                  ),
                if (metadata['triangleCount'] is num)
                  item('TROUGLOVI', '${metadata['triangleCount']}'),
                if (metadata['vertexCount'] is num)
                  item('TEMENA', '${metadata['vertexCount']}'),
                if (metadata['materialCount'] is num)
                  item('MATERIJALI', '${metadata['materialCount']}'),
                if (job['finishedAt'] is String)
                  item(
                    'GENERISANO',
                    DateTime.tryParse(
                          job['finishedAt'] as String,
                        )?.toLocal().toString().split('.').first ??
                        job['finishedAt'] as String,
                  ),
              ],
            ),
            if (job['provider'] == 'fake')
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Demonstracioni rezultat · nije AI generisanje.',
                  style: TextStyle(color: accent, fontSize: 12),
                ),
              ),
            if (metadata['previewIsGeneratedModel'] == false)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'Pregled prikazuje referentnu sliku. Slika rezultujućeg modela još nije renderovana.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
