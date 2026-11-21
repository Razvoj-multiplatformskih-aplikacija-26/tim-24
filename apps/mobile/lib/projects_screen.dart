import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'app_connection.dart';
import 'studio_screens.dart';
import 'studio_theme.dart';
import 'studio_workflows.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});
  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  Future<List<Map<String, dynamic>>>? projects;
  StudioWorkflows? _workflows;
  bool busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final workflows = StudioConnection.maybeOf(context)!.workflows;
    if (!identical(workflows, _workflows)) {
      _workflows = workflows;
      projects = load();
    }
  }

  Future<List<Map<String, dynamic>>> load() =>
      StudioConnection.maybeOf(context)!.workflows.loadProjects();

  void refresh() {
    setState(() => projects = load());
    context.read<AssetBloc>().add(const LoadAssets());
  }

  Future<void> save([Map<String, dynamic>? project]) async {
    final name = TextEditingController(text: project?['name'] as String?);
    final form = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          project == null ? 'Nova kolekcija' : 'Promeni naziv kolekcije',
        ),
        content: Form(
          key: form,
          child: TextFormField(
            autofocus: true,
            controller: name,
            maxLength: titleMaxLength,
            decoration: const InputDecoration(labelText: 'Naziv kolekcije'),
            validator: (value) {
              final r = validateTitle(value ?? '');
              return r.isValid ? null : errorMessage(r.error!);
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Sačuvaj'),
          ),
        ],
      ),
    );
    if (result == true && mounted) {
      setState(() => busy = true);
      try {
        await StudioConnection.maybeOf(context)!.workflows.saveProject(
          name.text,
          id: project?['id'] as String?,
          baseRevision: project?['revision'] as int?,
        );
        if (mounted) {
          refresh();
        }
      } on DomainException catch (e) {
        if (mounted) {
          if (e.error.code == ErrorCode.revisionConflict) refresh();
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(errorMessage(e.error))));
        }
      } finally {
        if (mounted) {
          setState(() => busy = false);
        }
      }
    }
    name.dispose();
  }

  Future<void> assign(Asset asset, String? projectId) async {
    final workflows = StudioConnection.maybeOf(context)!.workflows;
    if (!workflows.canModifyCollections) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Dodela kolekciji zahteva vezu. Prvo sinhronizujte lokalne izmene.',
          ),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      await workflows.assignProject(asset, projectId);
      if (mounted) {
        context.read<AssetBloc>().add(const LoadAssets());
      }
    } on DomainException catch (e) {
      if (mounted) {
        if (e.error.code == ErrorCode.revisionConflict) refresh();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e.error))));
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> chooseAsset(String projectId) async {
    final assets = context
        .read<AssetBloc>()
        .state
        .assets
        .where((a) => a.projectId != projectId)
        .toList();
    final choice = await showDialog<Asset>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Dodaj model u kolekciju'),
        children: assets.isEmpty
            ? [
                const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Nema dostupnih modela.'),
                ),
              ]
            : [
                for (final asset in assets)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, asset),
                    child: Text(asset.title),
                  ),
              ],
      ),
    );
    if (choice != null) {
      await assign(choice, projectId);
    }
  }

  @override
  Widget build(BuildContext context) => StudioShell(
    title: 'Projekti',
    child: BlocBuilder<AssetBloc, AssetState>(
      builder: (context, state) => FutureBuilder<List<Map<String, dynamic>>>(
        future: projects,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return MessageState(
              icon: Icons.cloud_off,
              title: 'Kolekcije nisu učitane',
              description: 'Proverite vezu i pokušajte ponovo.',
              action: FilledButton(
                onPressed: refresh,
                child: const Text('Pokušaj ponovo'),
              ),
            );
          }
          final records = snapshot.data ?? [];
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Projekti i kolekcije',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              const Text(
                'Organizuj modele za sledeći nivo svoje igre.',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 22),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.icon(
                  onPressed: busy ? null : save,
                  icon: const Icon(Icons.create_new_folder_outlined),
                  label: const Text('Nova kolekcija'),
                ),
              ),
              const SizedBox(height: 24),
              if (busy) const LinearProgressIndicator(),
              if (records.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: MessageState(
                    icon: Icons.folder_open,
                    title: 'Napravi prvu kolekciju',
                    description:
                        'Kolekcija grupiše tvoje privatne modele bez promene vidljivosti.',
                  ),
                ),
              for (final project in records)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.folder_outlined, color: accent),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  project['name'] as String,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Promeni naziv',
                                onPressed: busy ? null : () => save(project),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Dodaj model',
                                onPressed: busy
                                    ? null
                                    : () =>
                                          chooseAsset(project['id'] as String),
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                          for (final asset in state.assets.where(
                            (a) => a.projectId == project['id'],
                          ))
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(asset.title),
                              subtitle: Text(lifecycleLabel(asset.lifecycle)),
                              trailing: IconButton(
                                tooltip: 'Ukloni iz kolekcije',
                                onPressed: busy
                                    ? null
                                    : () => assign(asset, null),
                                icon: const Icon(Icons.remove_circle_outline),
                              ),
                            ),
                          if (!state.assets.any(
                            (a) => a.projectId == project['id'],
                          ))
                            const Padding(
                              padding: EdgeInsets.only(top: 14),
                              child: Text(
                                'Kolekcija je prazna.',
                                style: TextStyle(color: muted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
