import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app_connection.dart';
import 'memory_asset_repository.dart';

class ProjectFilter extends StatefulWidget {
  const ProjectFilter({
    super.key,
    required this.value,
    required this.onChanged,
    required this.assetProjectIds,
  });
  final String value;
  final ValueChanged<String> onChanged;
  final Set<String> assetProjectIds;
  @override
  State<ProjectFilter> createState() => _ProjectFilterState();
}

class _ProjectFilterState extends State<ProjectFilter> {
  Future<List<Map<String, dynamic>>>? projects;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    projects ??= load();
  }

  Future<List<Map<String, dynamic>>> load() async {
    final api = StudioConnection.maybeOf(context)?.client;
    if (api == null) {
      final repository = context.read<AssetRepository>();
      return repository is MemoryAssetRepository
          ? repository.projects.toList()
          : [];
    }
    final data = await api.request('GET', '/api/v1/projects');
    return (data['projects'] as List)
        .map((p) => Map<String, dynamic>.from(p as Map))
        .toList();
  }

  @override
  Widget build(BuildContext context) =>
      FutureBuilder<List<Map<String, dynamic>>>(
        future: projects,
        builder: (context, snapshot) {
          final names = <String, String>{
            for (final p in snapshot.data ?? <Map<String, dynamic>>[])
              p['id'] as String: p['name'] as String,
          };
          for (final id in widget.assetProjectIds) {
            names.putIfAbsent(id, () => id);
          }
          if (!['all', 'unassigned'].contains(widget.value)) {
            names.putIfAbsent(widget.value, () => widget.value);
          }
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                key: const Key('project-filter'),
                value: widget.value,
                underline: const SizedBox(),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('Svi projekti'),
                  ),
                  const DropdownMenuItem(
                    value: 'unassigned',
                    child: Text('Bez projekta'),
                  ),
                  for (final entry in names.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => widget.onChanged(value ?? 'all'),
              ),
              if (snapshot.hasError)
                IconButton(
                  tooltip: 'Ponovo učitaj projekte',
                  onPressed: () => setState(() => projects = load()),
                  icon: const Icon(Icons.refresh, size: 17),
                ),
            ],
          );
        },
      );
}
