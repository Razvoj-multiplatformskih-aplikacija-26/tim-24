import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'app_connection.dart';
import 'memory_asset_repository.dart';
import 'studio_theme.dart';
import 'sync_panel.dart';

class HedrionBrand extends StatelessWidget {
  const HedrionBrand({super.key, this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.view_in_ar_rounded, color: accent, size: 29),
      if (!compact) ...[
        const SizedBox(width: 8),
        const Text(
          'hedrion',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.3,
            color: accent,
          ),
        ),
      ],
    ],
  );
}

class StudioShell extends StatelessWidget {
  const StudioShell({
    super.key,
    required this.child,
    this.title = 'Moj studio',
    this.activeTool,
  });
  final Widget child;
  final String title;
  final String? activeTool;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final wide = constraints.maxWidth >= 1000;
      final path = GoRouterState.of(context).uri.path;
      final workspace = path == '/workspace' || path == '/create';
      final imageTool =
          activeTool == 'image' ||
          (activeTool == null &&
              GoRouterState.of(context).uri.queryParameters['flow'] ==
                  'text-to-image');
      final repository = context.read<AssetRepository>();
      final live = StudioConnection.maybeOf(context)?.client != null;
      return Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: SafeArea(
            bottom: false,
            child: Container(
              height: 64,
              padding: EdgeInsets.symmetric(horizontal: wide ? 22 : 16),
              decoration: const BoxDecoration(
                color: Color(0xff111211),
                border: Border(bottom: BorderSide(color: studioLine)),
              ),
              child: Row(
                children: [
                  InkWell(
                    onTap: () => context.go('/'),
                    child: HedrionBrand(compact: !wide),
                  ),
                  if (constraints.maxWidth >= 1180) ...[
                    const SizedBox(width: 26),
                    const SizedBox(
                      height: 22,
                      child: VerticalDivider(color: studioLine),
                    ),
                    const SizedBox(width: 14),
                    _topLink(
                      context,
                      'Workspace',
                      '/workspace',
                      workspace,
                      icon: Icons.grid_view_rounded,
                    ),
                    const SizedBox(width: 12),
                    _topLink(context, 'My Assets', '/', path == '/'),
                    const SizedBox(width: 12),
                    _topLink(
                      context,
                      'Projects',
                      '/projects',
                      path == '/projects',
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xff23251e),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          live
                              ? Icons.cloud_done_outlined
                              : Icons.science_outlined,
                          size: 15,
                          color: accent,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          live ? 'Connected' : 'Demo studio',
                          style: const TextStyle(fontSize: 11, color: accent),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Osveži biblioteku',
                    onPressed: () =>
                        context.read<AssetBloc>().add(const LoadAssets()),
                    icon: const Icon(Icons.refresh_rounded, size: 19),
                  ),
                  if (wide)
                    IconButton(
                      tooltip: 'Pomoć za studio',
                      onPressed: () => showDialog<void>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Your ideas. Another dimension.'),
                          content: const Text(
                            'Izaberi Text to 3D, Image to 3D ili Text to Image.\n\nPrevuci model za rotaciju, skroluj za zum i dvaput klikni za početni pogled.\n\nDemo prikazuje lokalne primere. AI provider i Modal se povezuju u sledećoj fazi.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Razumem'),
                            ),
                          ],
                        ),
                      ),
                      icon: const Icon(Icons.help_outline_rounded, size: 19),
                    ),
                  _demoMenu(context, repository),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () => context.go('/profile'),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 33,
                      height: 33,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xff293020),
                        border: Border.all(color: const Color(0xff5c6b3f)),
                      ),
                      child: const Text(
                        'H',
                        style: TextStyle(
                          color: accent,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: Row(
          children: [
            if (wide)
              Container(
                width: 76,
                decoration: const BoxDecoration(
                  color: Color(0xff151615),
                  border: Border(right: BorderSide(color: studioLine)),
                ),
                child: ListView(
                  children: [
                    const SizedBox(height: 20),
                    _rail(
                      context,
                      Icons.grid_view_outlined,
                      'Assets',
                      '/',
                      path == '/',
                    ),
                    _rail(
                      context,
                      Icons.view_in_ar_outlined,
                      'Model',
                      '/workspace?flow=text-to-3d',
                      workspace && !imageTool,
                    ),
                    _rail(
                      context,
                      Icons.auto_awesome_outlined,
                      'Image',
                      '/workspace?flow=text-to-image',
                      workspace && imageTool,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 23,
                        vertical: 12,
                      ),
                      child: Divider(color: studioLine),
                    ),
                    _rail(
                      context,
                      Icons.folder_outlined,
                      'Projects',
                      '/projects',
                      path == '/projects',
                    ),
                    _rail(
                      context,
                      Icons.public_outlined,
                      'Published',
                      '/submissions',
                      path == '/submissions',
                    ),
                    _rail(
                      context,
                      Icons.tune_rounded,
                      'Settings',
                      '/profile',
                      path == '/profile',
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                children: [
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
                height: 66,
                selectedIndex: workspace
                    ? 1
                    : path == '/projects'
                    ? 2
                    : path == '/profile'
                    ? 3
                    : 0,
                onDestinationSelected: (i) =>
                    context.go(['/', '/workspace', '/projects', '/profile'][i]),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    label: 'Assets',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.view_in_ar_outlined),
                    label: 'Create',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.folder_outlined),
                    label: 'Projects',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    label: 'Profile',
                  ),
                ],
              ),
      );
    },
  );

  Widget _topLink(
    BuildContext context,
    String text,
    String route,
    bool active, {
    IconData? icon,
  }) => TextButton(
    onPressed: () => context.go(route),
    style: TextButton.styleFrom(
      foregroundColor: active ? accent : const Color(0xffdfdfdc),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 17), const SizedBox(width: 8)],
        Text(
          text,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );

  Widget _rail(
    BuildContext context,
    IconData icon,
    String label,
    String path,
    bool active,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 7),
    child: Tooltip(
      message: label,
      child: InkWell(
        onTap: () => context.go(path),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 62,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? accent.withValues(alpha: .07) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 23, color: active ? accent : muted),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(fontSize: 10, color: active ? accent : muted),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _demoMenu(BuildContext context, AssetRepository repository) =>
      repository is! MemoryAssetRepository
      ? IconButton(
          tooltip: 'Odjavi se',
          onPressed: StudioConnection.maybeOf(context)?.onLogout,
          icon: const Icon(Icons.logout, size: 19),
        )
      : PopupMenuButton<String>(
          tooltip: 'Demonstracione komande',
          icon: const Icon(Icons.more_horiz, size: 19),
          onSelected: (value) {
            try {
              switch (value) {
                case 'fail':
                  repository.failNext = true;
                  context.read<AssetBloc>().add(const LoadAssets());
                case 'quota':
                  repository.exhaustQuota();
                case 'reset':
                  repository.reset();
                  context.read<AssetBloc>().add(const LoadAssets());
                case 'transfer':
                  repository.demonstrateTransferQuota();
                case 'storage':
                  repository.demonstrateStorageQuota();
                case 'draft':
                  context.go('/draft');
              }
            } on DomainException catch (e) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(errorMessage(e.error))));
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'draft',
              child: Text('Detaljni privatni nacrt'),
            ),
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
