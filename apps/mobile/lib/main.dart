import 'dart:async';
import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'app_connection.dart';
import 'live_studio.dart';
import 'memory_asset_repository.dart';
import 'studio_theme.dart';
import 'studio_screens.dart';
import 'projects_screen.dart';
import 'profile_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const String.fromEnvironment('HEDRION_MODE', defaultValue: 'demo') == 'api'
        ? const LiveStudio()
        : const HedrionStudio(),
  );
}

class HedrionStudio extends StatefulWidget {
  const HedrionStudio({
    super.key,
    this.repository,
    this.api,
    this.offline,
    this.onLogout,
    this.initialLocation,
  });
  final AssetRepository? repository;
  final HedrionApiClient? api;
  final OfflineAssetRepository? offline;
  final VoidCallback? onLogout;
  final String? initialLocation;
  @override
  State<HedrionStudio> createState() => _HedrionStudioState();
}

class _HedrionStudioState extends State<HedrionStudio> {
  Timer? timer;
  bool syncing = false;
  @override
  void initState() {
    super.initState();
    if (widget.api != null) {
      timer = Timer.periodic(const Duration(seconds: 8), (_) => synchronize());
    }
  }

  Future<void> synchronize() async {
    if (syncing || bloc.state.busy) {
      return;
    }
    syncing = true;
    try {
      await widget.api!.me();
      final offline = widget.offline;
      if (offline != null) {
        offline.online = true;
        await offline.sync();
      }
      bloc.add(const LoadAssets());
    } on DomainException catch (e) {
      if (e.error.code == ErrorCode.unauthenticated) {
        widget.onLogout?.call();
      } else if (e.error.code == ErrorCode.unavailable &&
          widget.offline?.online == true) {
        widget.offline!.online = false;
        if (!bloc.isClosed) {
          bloc.add(const LoadAssets());
        }
      }
    } catch (_) {
      /* Durable outbox remains for the next retry. */
    } finally {
      syncing = false;
    }
  }

  late final AssetRepository repository =
      widget.repository ?? MemoryAssetRepository();
  late final AssetBloc bloc = AssetBloc(repository)..add(const LoadAssets());
  late final router = GoRouter(
    initialLocation: widget.initialLocation,
    overridePlatformDefaultLocation: widget.initialLocation != null,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LibraryScreen()),
      GoRoute(
        path: '/create',
        builder: (context, state) => const CreateAssetScreen(),
      ),
      GoRoute(
        path: '/assets/:id',
        builder: (context, state) =>
            AssetDetailScreen(id: AssetId(state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/projects',
        builder: (context, state) => const ProjectsScreen(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfileScreen(),
      ),
      GoRoute(
        path: '/submissions',
        builder: (context, state) => const LibraryScreen(submissionsOnly: true),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Hedrion')),
      body: MessageState(
        icon: Icons.link_off,
        title: 'Stranica ne postoji',
        description: 'Vratite se u svoju biblioteku.',
        action: FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Moj studio'),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    timer?.cancel();
    router.dispose();
    bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => StudioConnection(
    client: widget.api,
    offline: widget.offline,
    onLogout: widget.onLogout,
    child: RepositoryProvider<AssetRepository>.value(
      value: repository,
      child: BlocProvider.value(
        value: bloc,
        child: MaterialApp.router(
          title: 'Hedrion • Moj studio',
          debugShowCheckedModeBanner: false,
          theme: studioTheme(),
          routerConfig: router,
        ),
      ),
    ),
  );
}
