import 'package:flutter/material.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';
import 'studio_workflows.dart';

class StudioConnection extends InheritedWidget {
  const StudioConnection({
    super.key,
    required super.child,
    required this.workflows,
    this.client,
    this.offline,
    this.onLogout,
  });
  final HedrionApiClient? client;
  final StudioWorkflows workflows;
  Map<String, dynamic>? get user => client?.user;
  Future<void> verifySession() async {
    await client?.me();
  }

  final OfflineAssetRepository? offline;
  final VoidCallback? onLogout;
  static StudioConnection? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioConnection>();
  @override
  bool updateShouldNotify(StudioConnection oldWidget) =>
      client != oldWidget.client ||
      offline != oldWidget.offline ||
      workflows != oldWidget.workflows;
}
