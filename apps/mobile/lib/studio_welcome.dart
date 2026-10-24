import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'studio_theme.dart';

class StudioWelcome extends StatelessWidget {
  const StudioWelcome({super.key});
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 38, horizontal: 12),
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment.topCenter,
        radius: 1.1,
        colors: [Color(0xff202a1b), Color(0xff141614), background],
      ),
    ),
    child: Column(
      children: [
        const Text(
          'A LITTLE IMAGINATION. A NEW DIMENSION.',
          textAlign: TextAlign.center,
          style: TextStyle(color: accent, fontSize: 10, letterSpacing: 2.2),
        ),
        const SizedBox(height: 16),
        Text(
          'What will you create in 3D?',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w600,
            letterSpacing: -1,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your next character, prop or entire world starts here.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 13),
        ),
        const SizedBox(height: 24),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 650),
          child: InkWell(
            onTap: () => context.go('/workspace?flow=image-to-3d'),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xff151a14),
                border: Border.all(color: const Color(0xff5a6c3f)),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 28,
                    color: accent,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Drop an idea. Bring it to life.',
                    style: TextStyle(fontSize: 14),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Start with an image, or describe what’s on your mind',
                    style: TextStyle(fontSize: 11, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          alignment: WrapAlignment.center,
          children: [
            FilledButton.icon(
              onPressed: () => context.go('/workspace'),
              icon: const Icon(Icons.auto_awesome, size: 17),
              label: const Text('Novi model'),
            ),
            TextButton.icon(
              onPressed: () => context.go('/workspace?flow=text-to-image'),
              icon: const Icon(Icons.image_outlined, size: 17),
              label: const Text('Text to Image'),
            ),
            TextButton(
              onPressed: () => context.go('/draft'),
              child: const Text('Privatni nacrt ↗'),
            ),
          ],
        ),
      ],
    ),
  );
}
