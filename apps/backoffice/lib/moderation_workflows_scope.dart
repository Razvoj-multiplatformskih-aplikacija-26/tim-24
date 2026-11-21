import 'package:flutter/widgets.dart';
import 'moderation_workflows.dart';

class BackofficeConnection extends InheritedWidget {
  const BackofficeConnection({
    super.key,
    required super.child,
    required this.workflows,
    this.onLogout,
  });
  final ModerationWorkflows workflows;
  final VoidCallback? onLogout;
  static BackofficeConnection of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackofficeConnection>()!;
  @override
  bool updateShouldNotify(BackofficeConnection oldWidget) =>
      oldWidget.workflows != workflows || oldWidget.onLogout != onLogout;
}
