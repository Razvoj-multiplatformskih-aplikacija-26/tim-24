import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'app_connection.dart';
import 'asset_preview.dart';
import 'memory_asset_repository.dart';
import 'studio_theme.dart';
import 'sync_panel.dart';
import 'generation_history.dart';
import 'reference_image_button.dart';
import 'asset_fields.dart';
import 'project_filter.dart';

class StudioShell extends StatelessWidget {
  const StudioShell({
    super.key,
    required this.child,
    this.title = 'Moj studio',
  });
  final Widget child;
  final String title;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final repository = context.read<AssetRepository>();
      final connection = StudioConnection.maybeOf(context);
      final live = connection?.client != null;
      Widget navigation() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 30, 24, 38),
            child: Row(
              children: [
                Icon(Icons.view_in_ar_rounded, color: accent, size: 30),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'hedrion',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                    ),
                  ),
                ),
              ],
            ),
          ),
          for (final item in [
            (Icons.dashboard_outlined, 'Moj studio', '/'),
            (Icons.folder_outlined, 'Projekti', '/projects'),
            (Icons.public_outlined, 'Moje prijave', '/submissions'),
            (Icons.settings_outlined, 'Profil i podešavanja', '/profile'),
          ])
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                selected: title == item.$2,
                selectedTileColor: accent.withValues(alpha: .1),
                leading: Icon(item.$1),
                title: Text(item.$2),
                onTap: () => context.go(item.$3),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xff31384d)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.science_outlined, color: accent),
                  SizedBox(height: 10),
                  Text(
                    live ? 'Povezani studio' : 'KT1 demonstracija',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  SizedBox(height: 6),
                  Text(
                    live
                        ? 'Tvoj nalog i biblioteka dostupni su na telefonu i vebu.'
                        : 'Lokalni podaci u memoriji. Generisanje je simulirano.',
                    style: TextStyle(color: muted, fontSize: 12, height: 1.5),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: Color(0xff332c53),
              child: Text('VK', style: TextStyle(color: accent)),
            ),
            title: Text('Kreator'),
            subtitle: Text(
              live
                  ? '${connection!.client!.user?['displayName'] ?? 'Prijavljen nalog'}'
                  : 'Demo nalog',
              style: const TextStyle(color: muted),
            ),
          ),
          const SizedBox(height: 18),
        ],
      );
      return Scaffold(
        drawer: wide
            ? null
            : Drawer(backgroundColor: background, child: navigation()),
        appBar: wide
            ? null
            : AppBar(
                title: const Text(
                  'hedrion',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Osveži biblioteku',
                    onPressed: () =>
                        context.read<AssetBloc>().add(const LoadAssets()),
                    icon: const Icon(Icons.refresh),
                  ),
                  _demoMenu(context, repository),
                ],
              ),
        body: Row(
          children: [
            if (wide) ...[
              SizedBox(width: 235, child: navigation()),
              const VerticalDivider(width: 1, color: Color(0xff242b40)),
            ],
            Expanded(
              child: Column(
                children: [
                  if (wide)
                    Container(
                      height: 76,
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Color(0xff242b40)),
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(title, style: const TextStyle(color: muted)),
                          const Spacer(),
                          const Icon(
                            Icons.cloud_done_outlined,
                            color: muted,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            live ? 'Povezano sa serverom' : 'Lokalni demo',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          IconButton(
                            tooltip: 'Osveži biblioteku',
                            onPressed: () => context.read<AssetBloc>().add(
                              const LoadAssets(),
                            ),
                            icon: const Icon(Icons.refresh),
                          ),
                          _demoMenu(context, repository),
                        ],
                      ),
                    ),
                  const SyncPanel(),
                  Expanded(
                    child: BlocListener<AssetBloc, AssetState>(
                      listenWhen: (a, b) =>
                          b.error != null && a.error != b.error,
                      listener: (context, state) =>
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(errorMessage(state.error!))),
                          ),
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: title == 'Projekti'
                    ? 1
                    : title == 'Moje prijave'
                    ? 2
                    : 0,
                onDestinationSelected: (i) =>
                    context.go(['/', '/projects', '/submissions'][i]),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    label: 'Studio',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    label: 'Projekti',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.public_outlined),
                    label: 'Prijave',
                  ),
                ],
              ),
      );
    },
  );
  Widget _demoMenu(BuildContext context, AssetRepository repository) =>
      repository is! MemoryAssetRepository
      ? IconButton(
          tooltip: 'Odjavi se',
          onPressed: StudioConnection.maybeOf(context)?.onLogout,
          icon: const Icon(Icons.logout),
        )
      : PopupMenuButton<String>(
          tooltip: 'Demonstracione komande',
          icon: const Icon(Icons.more_vert),
          onSelected: (value) {
            switch (value) {
              case 'fail':
                repository.failNext = true;
                context.read<AssetBloc>().add(const LoadAssets());
              case 'quota':
                repository.exhaustQuota();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      '20/20 mesta je zauzeto zahtevima drugih korisnika. Novi zahtev biće odbijen.',
                    ),
                  ),
                );
              case 'reset':
                repository.reset();
                context.read<AssetBloc>().add(const LoadAssets());
              case 'transfer':
                try {
                  repository.demonstrateTransferQuota();
                } on DomainException catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '950 MB + 100 MB: ${errorMessage(e.error)}',
                      ),
                    ),
                  );
                }
              case 'storage':
                try {
                  repository.demonstrateStorageQuota();
                } on DomainException catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '9.900 MB + 200 MB: ${errorMessage(e.error)}',
                      ),
                    ),
                  );
                }
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'fail',
              child: Text('Izazovi grešku sledećeg zahteva'),
            ),
            PopupMenuItem(
              value: 'quota',
              child: Text('Popuni dnevnu kvotu (20/20)'),
            ),
            PopupMenuItem(
              value: 'reset',
              child: Text('Vrati demonstracione podatke'),
            ),
            PopupMenuItem(
              value: 'transfer',
              child: Text('Proveri kvotu prenosa (950 + 100 MB)'),
            ),
            PopupMenuItem(
              value: 'storage',
              child: Text('Proveri skladište (9.900 + 200 MB)'),
            ),
          ],
        );
}

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.projectsOnly = false,
    this.submissionsOnly = false,
  });
  final bool projectsOnly, submissionsOnly;
  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String query = '', category = 'all', project = 'all';
  AssetLifecycle? status;
  bool favorite = false;
  @override
  Widget build(BuildContext context) => StudioShell(
    title: widget.projectsOnly
        ? 'Projekti'
        : widget.submissionsOnly
        ? 'Moje prijave'
        : 'Moj studio',
    child: BlocBuilder<AssetBloc, AssetState>(
      builder: (context, state) {
        if ((state.status == AssetLoadStatus.loading && state.assets.isEmpty) ||
            state.status == AssetLoadStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.status == AssetLoadStatus.failure && state.assets.isEmpty) {
          return MessageState(
            icon: Icons.cloud_off_outlined,
            title: 'Biblioteka nije učitana',
            description: errorMessage(state.error!),
            action: FilledButton.icon(
              onPressed: () =>
                  context.read<AssetBloc>().add(const LoadAssets()),
              icon: const Icon(Icons.refresh),
              label: const Text('Pokušaj ponovo'),
            ),
          );
        }
        final assets = state.assets
            .where(
              (a) =>
                  '${a.title} ${a.description} ${a.tags.join(' ')}'
                      .toLowerCase()
                      .contains(query.toLowerCase()) &&
                  (status == null || a.lifecycle == status) &&
                  (!favorite || a.favorite) &&
                  (category == 'all' || a.category == category) &&
                  (project == 'all' ||
                      (project == 'unassigned' && a.projectId == null) ||
                      a.projectId == project) &&
                  (!widget.submissionsOnly ||
                      [
                        AssetLifecycle.pendingReview,
                        AssetLifecycle.published,
                        AssetLifecycle.rejected,
                      ].contains(a.lifecycle)),
            )
            .toList();
        final categories = state.assets.map((a) => a.category).toSet().toList()
          ..sort();
        return CustomScrollView(
          slivers: [
            if (state.error != null)
              SliverToBoxAdapter(
                child: MaterialBanner(
                  content: Text(errorMessage(state.error!)),
                  actions: [
                    TextButton(
                      onPressed: () =>
                          context.read<AssetBloc>().add(const LoadAssets()),
                      child: const Text('Pokušaj ponovo'),
                    ),
                  ],
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 30, 24, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'RADNI PROSTOR ZA 3D IDEJE',
                      style: TextStyle(
                        color: accent,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 20,
                      runSpacing: 14,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.projectsOnly
                                  ? 'Projekti i kolekcije'
                                  : widget.submissionsOnly
                                  ? 'Moje javne prijave'
                                  : 'Tvoj sledeći svet počinje ovde.',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -.8,
                                  ),
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'Kreiraj, organizuj i podeli svoje 3D modele.',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                        FilledButton.icon(
                          onPressed: () => context.go('/create'),
                          icon: const Icon(Icons.add),
                          label: const Text('Novi model'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _metric(
                          'MOJI MODELI',
                          '${state.assets.length}',
                          Icons.view_in_ar_outlined,
                        ),
                        _metric(
                          'SPREMNI ZA RAD',
                          '${state.assets.where((a) => a.outputFileId != null).length}',
                          Icons.check_circle_outline,
                        ),
                        _metric(
                          'NA JAVNOJ PROVERI',
                          '${state.assets.where((a) => a.lifecycle == AssetLifecycle.pendingReview).length}',
                          Icons.public,
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Pretraži svoju biblioteku...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => setState(() => query = value),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          label: const Text('Svi modeli'),
                          selected: status == null && !favorite,
                          onSelected: (_) => setState(() {
                            status = null;
                            favorite = false;
                          }),
                        ),
                        FilterChip(
                          label: const Text('Omiljeni'),
                          avatar: const Icon(Icons.star_outline, size: 16),
                          selected: favorite,
                          onSelected: (v) => setState(() => favorite = v),
                        ),
                        for (final s in [
                          AssetLifecycle.ready,
                          AssetLifecycle.generating,
                          AssetLifecycle.pendingReview,
                          AssetLifecycle.failed,
                        ])
                          FilterChip(
                            label: Text(lifecycleLabel(s)),
                            selected: status == s,
                            onSelected: (v) =>
                                setState(() => status = v ? s : null),
                          ),
                        DropdownButton<String>(
                          key: const Key('category-filter'),
                          value: category,
                          underline: const SizedBox(),
                          items: [
                            const DropdownMenuItem(
                              value: 'all',
                              child: Text('Sve kategorije'),
                            ),
                            for (final c in categories)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (v) =>
                              setState(() => category = v ?? 'all'),
                        ),
                        ProjectFilter(
                          value: project,
                          onChanged: (value) => setState(() => project = value),
                          assetProjectIds: state.assets
                              .map((a) => a.projectId)
                              .whereType<String>()
                              .toSet(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    Text(
                      '${assets.length} modela',
                      style: const TextStyle(color: muted, fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
            ),
            if (assets.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: MessageState(
                  icon: Icons.search_off,
                  title: 'Nema modela za ovaj izbor',
                  description: 'Promenite pretragu ili napravite prvi model.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 30),
                sliver: SliverLayoutBuilder(
                  builder: (context, constraints) => SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: (constraints.crossAxisExtent / 260)
                          .floor()
                          .clamp(1, 5),
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                      mainAxisExtent: 332,
                    ),
                    itemCount: assets.length,
                    itemBuilder: (context, index) =>
                        _AssetCard(asset: assets[index]),
                  ),
                ),
              ),
          ],
        );
      },
    ),
  );
  Widget _metric(String label, String value, IconData icon) => Container(
    width: 205,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xff273047)),
    ),
    child: Row(
      children: [
        Icon(icon, color: accent),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: muted,
                  fontSize: 9,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset});
  final Asset asset;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go('/assets/${asset.id.value}'),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StudioPreview(asset: asset),
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 14, 5, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      asset.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    asset.favorite ? Icons.star : Icons.star_border,
                    color: asset.favorite ? accent : muted,
                    size: 18,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Row(
                children: [
                  StatusBadge(asset.lifecycle),
                  const Spacer(),
                  Text(
                    asset.category,
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                asset.tags.isEmpty
                    ? 'Bez oznaka'
                    : asset.tags.map((tag) => '#$tag').join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: accent, fontSize: 10),
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Text(
                'Kreirano ${asset.createdAt.toLocal().toIso8601String().split('T').first}',
                style: const TextStyle(color: muted, fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class CreateAssetScreen extends StatefulWidget {
  const CreateAssetScreen({super.key});
  @override
  State<CreateAssetScreen> createState() => _CreateAssetScreenState();
}

class _CreateAssetScreenState extends State<CreateAssetScreen> {
  final form = GlobalKey<FormState>();
  final title = TextEditingController(),
      description = TextEditingController(),
      project = TextEditingController(),
      tags = TextEditingController();
  String category = 'props';
  XFile? image;
  Uint8List? bytes;
  bool submitted = false;
  bool uploading = false;
  Set<AssetId> beforeCreate = {};
  Future<void> submit(BuildContext context, AssetState state) async {
    if (!form.currentState!.validate()) {
      return;
    }
    setState(() => uploading = true);
    try {
      String? projectId;
      final projectName = project.text.trim();
      if (projectName.isNotEmpty) {
        final api = StudioConnection.maybeOf(context)?.client;
        if (api == null) {
          final repo = context.read<AssetRepository>() as MemoryAssetRepository;
          projectId =
              (repo.projects
                          .where((p) => p['name'] == projectName)
                          .firstOrNull ??
                      repo.saveProject(projectName))['id']
                  as String;
        } else {
          final records = await api.request('GET', '/api/v1/projects');
          final previous = (records['projects'] as List)
              .cast<Map<String, dynamic>>()
              .where((p) => p['name'] == projectName)
              .firstOrNull;
          projectId =
              (previous ??
                      await api.request(
                        'POST',
                        '/api/v1/projects',
                        body: {'name': projectName},
                      ))['id']
                  as String;
        }
      }
      if (!context.mounted) {
        return;
      }
      beforeCreate = state.assets.map((a) => a.id).toSet();
      setState(() {
        submitted = true;
        uploading = false;
      });
      context.read<AssetBloc>().add(
        CreateAsset(
          AssetDraft(
            title: title.text,
            description: description.text,
            category: category,
            projectId: projectId,
            tags: parseTags(tags.text),
          ),
        ),
      );
    } on DomainException catch (e) {
      if (context.mounted) {
        setState(() => uploading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e.error))));
      }
    }
  }

  Future<void> finishCreate(BuildContext context, AssetState state) async {
    if (state.error != null) {
      setState(() => submitted = false);
      return;
    }
    final api = StudioConnection.maybeOf(context)?.client;
    final created = state.assets
        .where((a) => !beforeCreate.contains(a.id))
        .firstOrNull;
    if (api != null && bytes != null && created != null) {
      setState(() => uploading = true);
      try {
        await api.uploadImage(
          created.id,
          bytes!,
          mime: bytes!.length > 2 && bytes![0] == 137
              ? 'image/png'
              : 'image/jpeg',
        );
      } on DomainException catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Nacrt je sačuvan. ${errorMessage(e.error)}'),
            ),
          );
        }
      }
      if (context.mounted) {
        context.read<AssetBloc>().add(const LoadAssets());
        context.go('/assets/${created.id.value}');
      }
    } else if (context.mounted) {
      context.go('/');
    }
  }

  @override
  void dispose() {
    title.dispose();
    description.dispose();
    project.dispose();
    tags.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2048,
        maxHeight: 2048,
        requestFullMetadata: false,
      );
      if (file == null) {
        return;
      }
      final data = await file.readAsBytes();
      if (data.length > 10000000) {
        throw StateError('Slika može imati najviše 10 MB.');
      }
      if (mounted) {
        setState(() {
          image = file;
          bytes = data;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Slika nije dostupna. Proverite dozvolu za galeriju i pokušajte ponovo.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => StudioShell(
    child: BlocConsumer<AssetBloc, AssetState>(
      listenWhen: (a, b) => submitted && a.busy && !b.busy,
      listener: finishCreate,
      builder: (context, state) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Biblioteka'),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'OD IDEJE DO MODELA',
                    style: TextStyle(
                      color: accent,
                      letterSpacing: 2,
                      fontSize: 10,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Kreiraj novi model',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Model je privatan dok izričito ne zatražiš objavljivanje.',
                    style: TextStyle(color: muted),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '01   Referentna slika',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (bytes != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.memory(
                                bytes!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.contain,
                              ),
                            ),
                          OutlinedButton.icon(
                            onPressed: state.busy ? null : pickImage,
                            icon: const Icon(
                              Icons.add_photo_alternate_outlined,
                            ),
                            label: Text(
                              image?.name ??
                                  (kIsWeb
                                      ? 'Izaberi lokalnu sliku'
                                      : 'Izaberi iz galerije'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            StudioConnection.maybeOf(context)?.client == null
                                ? 'PNG / JPEG · do 10 MB. U demonstraciji slika ostaje na uređaju.'
                                : 'PNG / JPEG · do 10 MB. Slika se šalje kada sačuvaš nacrt.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          const SizedBox(height: 15),
                          const Text(
                            'Tekstualni unos još nije dostupan. Izaberi referentnu sliku.',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '02   Detalji modela',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 18),
                          TextFormField(
                            controller: title,
                            decoration: const InputDecoration(
                              labelText: 'Naziv modela',
                              hintText: 'Na primer: Kameni sanduk',
                            ),
                            maxLength: 60,
                            validator: (value) {
                              final result = validateTitle(value ?? '');
                              return result.isValid
                                  ? null
                                  : errorMessage(result.error!);
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: description,
                            decoration: const InputDecoration(
                              labelText: 'Opis',
                            ),
                            maxLines: 3,
                            maxLength: 2000,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            initialValue: category,
                            decoration: const InputDecoration(
                              labelText: 'Kategorija',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'props',
                                child: Text('Rekviziti'),
                              ),
                              DropdownMenuItem(
                                value: 'furniture',
                                child: Text('Nameštaj'),
                              ),
                              DropdownMenuItem(
                                value: 'nature',
                                child: Text('Priroda'),
                              ),
                              DropdownMenuItem(
                                value: 'weapons',
                                child: Text('Oružje'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => category = value ?? 'props'),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: project,
                            decoration: const InputDecoration(
                              labelText: 'Projekat / kolekcija (opciono)',
                            ),
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            key: const Key('create-tags'),
                            controller: tags,
                            decoration: const InputDecoration(
                              labelText: 'Oznake',
                              hintText: 'kamen, stilizovano, enterijer',
                              helperText: 'Odvoji oznake zarezom.',
                            ),
                            validator: validateTagsField,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: state.busy || uploading
                        ? null
                        : () => submit(context, state),
                    icon: state.busy || uploading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add),
                    label: const Text('Sačuvaj privatni nacrt'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class AssetDetailScreen extends StatelessWidget {
  const AssetDetailScreen({super.key, required this.id});
  final AssetId id;
  @override
  Widget build(BuildContext context) => StudioShell(
    child: BlocBuilder<AssetBloc, AssetState>(
      builder: (context, state) {
        final matches = state.assets.where((a) => a.id == id);
        if (matches.isEmpty) {
          return MessageState(
            icon: Icons.view_in_ar_outlined,
            title: 'Model nije dostupan',
            description: 'Osvežite biblioteku ili proverite adresu.',
            action: TextButton(
              onPressed: () => context.go('/'),
              child: const Text('Moj studio'),
            ),
          );
        }
        final asset = matches.first;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextButton.icon(
                    onPressed: () => context.go('/'),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Biblioteka'),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 18,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        asset.title,
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      StatusBadge(asset.lifecycle),
                    ],
                  ),
                  const SizedBox(height: 18),
                  StudioPreview(asset: asset, height: 330),
                  const SizedBox(height: 12),
                  Text(
                    StudioConnection.maybeOf(context)?.client == null
                        ? 'Ilustracija u KT1 režimu. 3D viewport nije aktivan.'
                        : 'Pregled slike rezultata. Interaktivni 3D viewport nije aktivan; GLB možeš preuzeti ispod.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (asset.outputFileId != null &&
                          StudioConnection.maybeOf(context)?.client != null)
                        _DownloadButton(asset: asset),
                      if ([
                            AssetLifecycle.draft,
                            AssetLifecycle.failed,
                          ].contains(asset.lifecycle) &&
                          StudioConnection.maybeOf(context)?.client != null)
                        ReferenceImageButton(asset: asset),
                      FilledButton.tonalIcon(
                        onPressed: state.busy
                            ? null
                            : () => _edit(context, asset),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Uredi detalje'),
                      ),
                      OutlinedButton.icon(
                        onPressed: state.busy
                            ? null
                            : () => context.read<AssetBloc>().add(
                                UpdateAsset(
                                  asset.copyWith(favorite: !asset.favorite),
                                  asset.revision,
                                ),
                              ),
                        icon: Icon(
                          asset.favorite ? Icons.star : Icons.star_border,
                        ),
                        label: Text(
                          asset.favorite ? 'Ukloni iz omiljenih' : 'Omiljeni',
                        ),
                      ),
                      if ([
                        AssetLifecycle.draft,
                        AssetLifecycle.failed,
                      ].contains(asset.lifecycle))
                        FilledButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => context.read<AssetBloc>().add(
                                  TransitionAsset(
                                    asset.id,
                                    AssetLifecycle.queued,
                                    baseRevision: asset.revision,
                                    idempotencyKey:
                                        '${asset.id.value}-${asset.revision}-generation',
                                  ),
                                ),
                          icon: const Icon(Icons.auto_awesome),
                          label: Text(
                            asset.lifecycle == AssetLifecycle.failed
                                ? 'Pokušaj ponovo'
                                : 'Zatraži generisanje',
                          ),
                        ),
                      if (asset.lifecycle == AssetLifecycle.ready)
                        FilledButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => _publish(context, asset),
                          icon: const Icon(Icons.public),
                          label: const Text('Predloži za javnu biblioteku'),
                        ),
                      if (asset.lifecycle == AssetLifecycle.rejected)
                        FilledButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => context.read<AssetBloc>().add(
                                  TransitionAsset(
                                    asset.id,
                                    AssetLifecycle.ready,
                                    baseRevision: asset.revision,
                                  ),
                                ),
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Pripremi novu prijavu'),
                        ),
                      if ([
                        AssetLifecycle.published,
                        AssetLifecycle.pendingReview,
                      ].contains(asset.lifecycle))
                        OutlinedButton.icon(
                          onPressed: state.busy
                              ? null
                              : () => _withdraw(context, asset),
                          icon: const Icon(Icons.public_off),
                          label: Text(
                            asset.lifecycle == AssetLifecycle.published
                                ? 'Ukloni iz javne biblioteke'
                                : 'Povuci javnu prijavu',
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: state.busy
                            ? null
                            : () => _delete(context, asset),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Obriši'),
                      ),
                    ],
                  ),
                  if (state.busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 18),
                      child: LinearProgressIndicator(),
                    ),
                  const SizedBox(height: 26),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'O modelu',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            asset.description.isEmpty
                                ? 'Opis još nije dodat.'
                                : asset.description,
                            style: const TextStyle(color: muted, height: 1.6),
                          ),
                          if (asset.tags.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 7,
                              runSpacing: 7,
                              children: [
                                for (final tag in asset.tags)
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 250,
                                    ),
                                    child: Chip(
                                      label: Text(
                                        '#$tag',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 20),
                          Wrap(
                            spacing: 30,
                            runSpacing: 16,
                            children: [
                              _detail('KATEGORIJA', asset.category),
                              _detail('REVIZIJA', '${asset.revision}'),
                              _detail(
                                'PROJEKAT',
                                asset.projectId ?? 'Nedodeljen',
                              ),
                              _detail(
                                'VIDLJIVOST',
                                asset.lifecycle == AssetLifecycle.published
                                    ? 'Javno'
                                    : 'Privatno',
                              ),
                              _detail('FORMAT', 'GLB'),
                            ],
                          ),
                          if (asset.rejectionReason != null) ...[
                            const SizedBox(height: 20),
                            Text(
                              'Razlog odbijanja: ${asset.rejectionReason}',
                              style: const TextStyle(color: Color(0xffffa49e)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  GenerationHistory(asset: asset),
                  if (asset.lifecycle == AssetLifecycle.queued ||
                      asset.lifecycle == AssetLifecycle.generating)
                    Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          StudioConnection.maybeOf(context)?.client == null
                              ? 'KT1 čuva zahtev u lokalnoj memoriji. Serverski red i worker aktiviraju se u API režimu.'
                              : 'Posao se izvršava na serveru. Napuštanje stranice neće ga zaustaviti. Stanje se automatski osvežava.',
                          style: TextStyle(color: muted),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(color: muted, fontSize: 10, letterSpacing: 1.2),
      ),
      const SizedBox(height: 8),
      Text(value),
    ],
  );
  Future<void> _edit(BuildContext context, Asset asset) async {
    final title = TextEditingController(text: asset.title),
        description = TextEditingController(text: asset.description),
        tags = TextEditingController(text: asset.tags.join(', '));
    final offline = StudioConnection.maybeOf(context)?.offline;
    final canEditTags =
        offline == null || (offline.online && offline.pendingCount == 0);
    final key = GlobalKey<FormState>();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uredi model'),
        scrollable: true,
        content: SizedBox(
          width: 440,
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Naziv'),
                  maxLength: 60,
                  validator: (value) {
                    final r = validateTitle(value ?? '');
                    return r.isValid ? null : errorMessage(r.error!);
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: description,
                  decoration: const InputDecoration(labelText: 'Opis'),
                  maxLines: 3,
                  maxLength: 2000,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: const Key('edit-tags'),
                  controller: tags,
                  enabled: canEditTags,
                  validator: validateTagsField,
                  decoration: InputDecoration(
                    labelText: 'Oznake',
                    helperText: canEditTags
                        ? 'Odvoji oznake zarezom.'
                        : 'Oznake zahtevaju mrežu i sinhronizovan model.',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(context, true);
              }
            },
            child: const Text('Sačuvaj'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {
      context.read<AssetBloc>().add(
        UpdateAsset(
          asset.copyWith(
            title: title.text,
            description: description.text,
            tags: parseTags(tags.text),
          ),
          asset.revision,
        ),
      );
    }
    title.dispose();
    description.dispose();
    tags.dispose();
  }

  Future<void> _publish(BuildContext context, Asset asset) async {
    bool rights = false;
    bool allowDownload = true;
    AssetLicense license = AssetLicense.ccBy;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Predlog za javnu biblioteku'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Moderator proverava ovu verziju modela. Tek odobrena prijava postaje javna.',
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<AssetLicense>(
                initialValue: license,
                decoration: const InputDecoration(labelText: 'Licenca'),
                items: const [
                  DropdownMenuItem(
                    value: AssetLicense.ccBy,
                    child: Text('CC BY 4.0 · uz navođenje autora'),
                  ),
                  DropdownMenuItem(
                    value: AssetLicense.cc0,
                    child: Text('CC0 · javni domen'),
                  ),
                  DropdownMenuItem(
                    value: AssetLicense.allRightsReserved,
                    child: Text('Sva prava zadržana · samo pregled'),
                  ),
                ],
                onChanged: (value) => setState(() {
                  license = value ?? AssetLicense.ccBy;
                  if (license == AssetLicense.allRightsReserved) {
                    allowDownload = false;
                  }
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: allowDownload,
                onChanged: license == AssetLicense.allRightsReserved
                    ? null
                    : (value) => setState(() => allowDownload = value),
                title: const Text('Dozvoli javno preuzimanje'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: rights,
                onChanged: (v) => setState(() => rights = v ?? false),
                title: const Text('Imam pravo da podelim ulaz i model.'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Odustani'),
            ),
            FilledButton(
              onPressed: rights ? () => Navigator.pop(context, true) : null,
              child: const Text('Pošalji na proveru'),
            ),
          ],
        ),
      ),
    );
    if (result == true && context.mounted) {
      context.read<AssetBloc>().add(
        SubmitPublication(
          asset.id,
          baseRevision: asset.revision,
          license: license,
          allowDownload: allowDownload,
          confirmRights: rights,
          idempotencyKey: '${asset.id.value}-${asset.revision}-publication',
        ),
      );
    }
  }

  Future<void> _delete(BuildContext context, Asset asset) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Obrisati model?'),
        content: Text(
          '„${asset.title}“ će biti obrisan iz biblioteke. Ovu radnju nije moguće poništiti.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Obriši model'),
          ),
        ],
      ),
    );
    if (result == true && context.mounted) {
      context.read<AssetBloc>().add(DeleteAsset(asset.id, asset.revision));
      context.go('/');
    }
  }

  Future<void> _withdraw(BuildContext context, Asset asset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vrati model u privatnu biblioteku?'),
        content: const Text(
          'Javni prikaz ili prijava biće povučeni. Tvoj model i rezultat ostaju sačuvani u privatnoj biblioteci. Za novo objavljivanje šalje se nova prijava.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Odustani'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Povuci objavljivanje'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      context.read<AssetBloc>().add(
        TransitionAsset(
          asset.id,
          AssetLifecycle.ready,
          baseRevision: asset.revision,
          idempotencyKey: '${asset.id.value}-${asset.revision}-withdraw',
        ),
      );
    }
  }
}

class _DownloadButton extends StatefulWidget {
  const _DownloadButton({required this.asset});
  final Asset asset;
  @override
  State<_DownloadButton> createState() => _DownloadButtonState();
}

class _DownloadButtonState extends State<_DownloadButton> {
  bool busy = false;
  Future<void> download() async {
    final api = StudioConnection.maybeOf(context)!.client!;
    setState(() => busy = true);
    try {
      final bytes = await api.download(widget.asset);
      final name =
          '${widget.asset.title.replaceAll(RegExp(r'[^a-zA-Z0-9\u0400-\u04ff\u0100-\u017f_-]'), '_')}.glb';
      final file = XFile.fromData(
        bytes,
        mimeType: 'model/gltf-binary',
        name: name,
      );
      if (kIsWeb) {
        await file.saveTo(name);
      } else {
        await SharePlus.instance.share(
          ShareParams(
            files: [file],
            fileNameOverrides: [name],
            title: 'Sačuvaj 3D model',
          ),
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('GLB preuzet · ${bytes.length} bajtova.')),
        );
      }
    } on DomainException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(errorMessage(e.error))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fajl nije sačuvan. Pokušajte ponovo.')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: busy ? null : download,
    icon: busy
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.download),
    label: Text(busy ? 'Preuzimanje…' : 'Preuzmi GLB'),
  );
}
