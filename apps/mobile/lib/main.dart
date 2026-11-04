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
import 'workspace_screen.dart';
import 'generation_setup.dart';

void main() {
  //Priprema veze izmedju flutter koda i platforme(android)
  WidgetsFlutterBinding.ensureInitialized();

  //runApp je Flutter funkcija kojoj dajemo pocetni widget aplikacija
  //Widget je kao react komponenta.
  runApp(
    //Provera da li je hedrion_mode env demo ili api, demo je bez backend za prvu Kt
    const String.fromEnvironment('HEDRION_MODE', defaultValue: 'demo') == 'api'
        ? const LiveStudio()
        : const HedrionStudio(), //Demo
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
  // Ako repository nije prosledjen napravi novi memoryAssetRepository(),
  // u nasem demo slucaju zove bira se memoryassetrepo
  // zove se reset()

  //On se tkaodje dole u build prosledjuej , pravi objekat nase klase AssetBloc sa nasim repositoryjem

  //Uloga AssetBloc da cita podatke preko repositoryja
  late final AssetBloc bloc = AssetBloc(repository)..add(const LoadAssets());

  //Ruter za rute za frontend
  late final router = GoRouter(
    initialLocation: widget.initialLocation,
    overridePlatformDefaultLocation: widget.initialLocation != null,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const LibraryScreen()),
      GoRoute(
        path: '/create',
        builder: (context, state) => WorkspaceScreen(
          flow: GenerationFlow.fromRoute(state.uri.queryParameters['flow']),
        ),
      ),
      GoRoute(
        path: '/workspace',
        builder: (context, state) => WorkspaceScreen(
          flow: GenerationFlow.fromRoute(state.uri.queryParameters['flow']),
        ),
      ),
      GoRoute(path: '/draft', redirect: (context, state) => '/workspace'),
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

  ///Ovo se zove posle init, pravimo ekran
  @override
  Widget build(BuildContext context) => StudioConnection(
    client: widget.api, // veza ka apiu
    offline:
        widget.offline, // repozitorijum za rad i sinhrnizaciju kad ema mreze
    onLogout:
        widget.onLogout, //Funkcija koja se pozove kada korisnik izabere odjavu
    child: RepositoryProvider<AssetRepository>.value(
      value: repository, // postavljamo repo sa nasi fejk asseti
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
