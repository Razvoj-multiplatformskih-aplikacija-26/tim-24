import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'live_backoffice.dart';
import 'memory_moderation_repository.dart';
import 'moderation_screen.dart';
import 'studio_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const String.fromEnvironment('HEDRION_MODE', defaultValue: 'demo') == 'api'
        ? const LiveBackoffice()
        : const HedrionBackoffice(),
  );
}

class HedrionBackoffice extends StatelessWidget {
  const HedrionBackoffice({
    super.key,
    this.repository,
    this.api,
    this.onLogout,
  });
  final AssetRepository? repository;
  final HedrionApiClient? api;
  final VoidCallback? onLogout;
  @override
  Widget build(BuildContext context) => BackofficeConnection(
    api: api,
    onLogout: onLogout,
    child: RepositoryProvider<AssetRepository>(
      create: (_) => repository ?? MemoryModerationRepository(),
      child: BlocProvider(
        create: (context) =>
            AssetBloc(context.read<AssetRepository>())..add(const LoadAssets()),
        child: MaterialApp(
          title: 'Hedrion • Moderacija',
          debugShowCheckedModeBanner: false,
          theme: studioTheme(),
          home: const ModerationScreen(),
        ),
      ),
    ),
  );
}
