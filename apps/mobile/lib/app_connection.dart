import 'package:flutter/material.dart';
import 'package:hedrion_api_client/hedrion_api_client.dart';

class StudioConnection extends InheritedWidget {
  const StudioConnection({
    super.key,
    required super.child,
    this.client,
    this.offline,
    this.onLogout,
  });
  final HedrionApiClient? client;
  final OfflineAssetRepository? offline;
  final VoidCallback? onLogout;
  static StudioConnection? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioConnection>();
  @override
  bool updateShouldNotify(StudioConnection oldWidget) =>
      client != oldWidget.client || offline != oldWidget.offline;
}
