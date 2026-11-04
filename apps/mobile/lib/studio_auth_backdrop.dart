import 'package:flutter/material.dart';
import 'studio_chrome.dart';
import 'studio_theme.dart';

class StudioAuthBackdrop extends StatelessWidget {
  const StudioAuthBackdrop({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(.1, -.7),
        radius: 1.3,
        colors: [Color(0xff26351c), Color(0xff141a12), background],
      ),
    ),
    child: Stack(
      children: [
        Positioned.fill(child: child),
        const Positioned(
          top: 24,
          left: 28,
          child: IgnorePointer(child: HedrionBrand()),
        ),
        if (MediaQuery.sizeOf(context).height > 780)
          const Positioned(
            left: 20,
            right: 20,
            bottom: 25,
            child: IgnorePointer(
              child: Text(
                'YOUR IDEAS. ANOTHER DIMENSION.',
                textAlign: TextAlign.center,
                style: TextStyle(color: muted, fontSize: 9, letterSpacing: 2.4),
              ),
            ),
          ),
      ],
    ),
  );
}
