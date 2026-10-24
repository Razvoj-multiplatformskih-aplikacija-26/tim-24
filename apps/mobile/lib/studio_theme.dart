import 'mesh_scene.dart';
import 'model_viewport.dart';
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

const background = Color(0xff101110);
const panel = Color(0xff20211f);
const accent = Color(0xffc1f45c);
const studioLine = Color(0xff30322d);
const muted = Color(0xff969b91);

ThemeData studioTheme() => ThemeData(
  brightness: Brightness.dark,
  colorScheme: ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: panel,
    primary: accent,
  ),
  scaffoldBackgroundColor: background,
  useMaterial3: true,
  fontFamily: 'Segoe UI',
  dividerColor: studioLine,
  navigationBarTheme: const NavigationBarThemeData(
    backgroundColor: panel,
    indicatorColor: Color(0xff354322),
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 450),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: background,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xff191b18),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: accent, width: 2),
    ),
  ),
  cardTheme: CardThemeData(
    color: panel,
    elevation: 0,
    margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: Color(0xff30322d)),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
);

String lifecycleLabel(AssetLifecycle state) => switch (state) {
  AssetLifecycle.draft => 'Nacrt',
  AssetLifecycle.queued => 'U redu',
  AssetLifecycle.generating => 'Generisanje',
  AssetLifecycle.ready => 'Spreman',
  AssetLifecycle.pendingReview => 'Na proveri',
  AssetLifecycle.published => 'Objavljen',
  AssetLifecycle.failed => 'Neuspelo',
  AssetLifecycle.rejected => 'Odbijena prijava',
};

Color lifecycleColor(AssetLifecycle state) => switch (state) {
  AssetLifecycle.ready || AssetLifecycle.published => const Color(0xff74ddbe),
  AssetLifecycle.failed || AssetLifecycle.rejected => const Color(0xffffa49e),
  AssetLifecycle.generating || AssetLifecycle.queued => const Color(0xff9bbcff),
  _ => accent,
};

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key});
  final AssetLifecycle status;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: lifecycleColor(status).withValues(alpha: .12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      lifecycleLabel(status),
      style: TextStyle(
        color: lifecycleColor(status),
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

/// Local 3D sample artwork, explicitly labeled as a demo.
class AssetArtwork extends StatelessWidget {
  const AssetArtwork({super.key, required this.asset, this.height = 190});
  final Asset asset;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Demonstraciona ilustracija modela ${asset.title}',
    child: Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        gradient: const RadialGradient(
          colors: [Color(0xff353931), Color(0xff1b1d1a)],
          radius: .85,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ModelViewport(
              model: sampleForTitle(asset.title),
              interactive: false,
            ),
          ),
          const Positioned(
            left: 10,
            top: 10,
            child: Text(
              'SAMPLE',
              style: TextStyle(fontSize: 8, color: muted, letterSpacing: 1.4),
            ),
          ),
          Positioned(
            right: 10,
            top: 10,
            child: Icon(
              asset.lifecycle == AssetLifecycle.published
                  ? Icons.public
                  : Icons.lock_outline,
              size: 14,
              color: muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class MessageState extends StatelessWidget {
  const MessageState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });
  final IconData icon;
  final String title, description;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: accent),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 10),
          Text(
            description,
            textAlign: TextAlign.center,
            style: const TextStyle(color: muted),
          ),
          if (action != null) ...[const SizedBox(height: 22), action!],
        ],
      ),
    ),
  );
}
