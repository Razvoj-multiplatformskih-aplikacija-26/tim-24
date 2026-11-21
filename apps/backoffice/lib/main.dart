import 'package:blocs/blocs.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'live_backoffice.dart';
import 'memory_moderation_repository.dart';
import 'moderation_screen.dart';
import 'moderation_workflows.dart';
import 'moderation_workflows_adapters.dart';
import 'moderation_workflows_scope.dart';
import 'studio_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const String.fromEnvironment('HEDRION_MODE', defaultValue: 'demo') == 'api'
        ? const LiveBackoffice()
        : const HedrionBackoffice(),
  );
}

class HedrionBackoffice extends StatefulWidget {
  const HedrionBackoffice({
    super.key,
    this.repository,
    this.api,
    this.workflows,
    this.onLogout,
  });
  final AssetRepository? repository;
  final HedrionApiClient? api;
  final ModerationWorkflows? workflows;
  final VoidCallback? onLogout;
  @override
  State<HedrionBackoffice> createState() => _HedrionBackofficeState();
}

class _HedrionBackofficeState extends State<HedrionBackoffice> {
  late final AssetRepository repository =
      widget.repository ??
      (widget.api == null
          ? MemoryModerationRepository()
          : ApiAssetRepository(widget.api!, moderator: true));
  late final ModerationWorkflows workflows =
      widget.workflows ??
      createModerationWorkflows(repository: repository, client: widget.api);
  late final AssetBloc bloc = AssetBloc(repository)..add(const LoadAssets());
  @override
  void dispose() {
    bloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BackofficeConnection(
    workflows: workflows,
    onLogout: widget.onLogout,
    child: RepositoryProvider<AssetRepository>.value(
      value: repository,
      child: BlocProvider.value(
        value: bloc,
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
