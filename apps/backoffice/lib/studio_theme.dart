import 'dart:math' as math;
import 'package:domain/domain.dart';
import 'package:flutter/material.dart';

const background = Color(0xff0c101b);
const panel = Color(0xff151b2b);
const accent = Color(0xffaa91ff);
const muted = Color(0xff98a2b8);

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
  appBarTheme: const AppBarTheme(
    backgroundColor: background,
    centerTitle: false,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: const Color(0xff101623),
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
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: Color(0xff263047)),
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

/// A deliberately labeled local illustration, not a claimed AI result.
class AssetArtwork extends StatelessWidget {
  const AssetArtwork({super.key, required this.asset, this.height = 170});
  final Asset asset;
  final double height;
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Demonstraciona ilustracija modela ${asset.title}',
    child: Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const RadialGradient(
          colors: [Color(0xff2a2848), Color(0xff131a2a)],
          radius: .95,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _MeshPainter(asset.id.value.hashCode)),
          ),
          const Positioned(
            left: 12,
            bottom: 10,
            child: Text(
              'DEMO PREVIEW',
              style: TextStyle(color: muted, fontSize: 9, letterSpacing: 1.6),
            ),
          ),
          Positioned(
            right: 12,
            top: 12,
            child: Icon(
              asset.lifecycle == AssetLifecycle.published
                  ? Icons.public
                  : Icons.lock_outline,
              color: muted,
              size: 16,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MeshPainter extends CustomPainter {
  _MeshPainter(this.seed);
  final int seed;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 - 5);
    final r = math.min(size.width, size.height) * .29;
    final grid = Paint()
      ..color = const Color(0xff41445f).withValues(alpha: .3)
      ..strokeWidth = .6;
    for (int i = -4; i <= 4; i++) {
      canvas.drawLine(
        center + Offset(-r * 2, r + i * 12),
        center + Offset(r * 2, r + i * 12),
        grid,
      );
      canvas.drawLine(
        center + Offset(i * 30, -r),
        center + Offset(i * 60, r * 2),
        grid,
      );
    }
    final p = [
      center + Offset(0, -r),
      center + Offset(r, -r * .4),
      center + Offset(0, r * .2),
      center + Offset(-r, -r * .4),
      center + Offset(r, r * .65),
      center + Offset(0, r * 1.25),
      center + Offset(-r, r * .65),
    ];
    final hue = 235.0 + seed.abs() % 70;
    void face(List<int> indices, double lightness) {
      final path = Path()..moveTo(p[indices.first].dx, p[indices.first].dy);
      for (final i in indices.skip(1)) {
        path.lineTo(p[i].dx, p[i].dy);
      }
      path.close();
      canvas.drawPath(
        path,
        Paint()..color = HSLColor.fromAHSL(1, hue, .35, lightness).toColor(),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xffb5b7ff).withValues(alpha: .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1,
      );
    }

    face([0, 1, 2, 3], .63);
    face([3, 2, 5, 6], .36);
    face([2, 1, 4, 5], .46);
    canvas.drawLine(
      p[0],
      p[5],
      grid..color = const Color(0xffd8d4ff).withValues(alpha: .4),
    );
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.seed != seed;
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
