import 'package:flutter/material.dart';

/// A regular browser tab cannot reliably lock screen orientation.
///
/// Keep the Navigator mounted in portrait so returning to landscape preserves
/// MIDI selection and training progress. Individual audio screens suspend
/// capture when the viewport becomes portrait.
bool isPortraitViewport(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.height > size.width;
}

class LandscapeGate extends StatelessWidget {
  const LandscapeGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final portrait = isPortraitViewport(context);
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: ExcludeSemantics(
            excluding: portrait,
            child: IgnorePointer(ignoring: portrait, child: child),
          ),
        ),
        if (portrait)
          Positioned.fill(
            child: Material(
              color: scheme.surface,
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.screen_rotation,
                            size: 72,
                            color: scheme.primary,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Obróć urządzenie poziomo',
                            key: const Key('landscape-required'),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'Learn Piano działa w układzie poziomym. '
                            'Obróć telefon lub tablet, albo poszerz okno '
                            'przeglądarki, aby kontynuować.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Jeśli trwał nasłuch, mikrofon został wyłączony. '
                            'Po obróceniu wznów go ręcznie.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
