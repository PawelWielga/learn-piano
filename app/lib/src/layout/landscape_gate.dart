import 'package:flutter/material.dart';

import '../orientation/orientation_lock.dart';

/// A regular browser tab cannot reliably lock screen orientation.
///
/// Keep the Navigator mounted in portrait so returning to landscape preserves
/// MIDI selection and training progress. Individual audio screens suspend
/// capture when the viewport becomes portrait.
bool isPortraitViewport(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.height > size.width;
}

class LandscapeGate extends StatefulWidget {
  const LandscapeGate({super.key, required this.child});

  final Widget child;

  @override
  State<LandscapeGate> createState() => _LandscapeGateState();
}

class _LandscapeGateState extends State<LandscapeGate> {
  bool _requestingLock = false;
  bool _lockUnavailable = false;

  Future<void> _tryLockLandscape() async {
    if (_requestingLock) return;
    setState(() {
      _requestingLock = true;
      _lockUnavailable = false;
    });

    final succeeded = await requestLandscapeOrientation();
    if (!mounted) return;
    setState(() {
      _requestingLock = false;
      _lockUnavailable = !succeeded;
    });
  }

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
            child: IgnorePointer(ignoring: portrait, child: widget.child),
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
                          const SizedBox(height: 20),
                          FilledButton.icon(
                            key: const Key('request-landscape-lock'),
                            onPressed: _requestingLock ? null : _tryLockLandscape,
                            icon: const Icon(Icons.screen_lock_rotation),
                            label: Text(
                              _requestingLock
                                  ? 'Przełączanie...'
                                  : 'Włącz poziomy ekran',
                            ),
                          ),
                          if (_lockUnavailable) ...[
                            const SizedBox(height: 16),
                            const Text(
                              'Przeglądarka nie pozwala obrócić ekranu '
                              'automatycznie. Wyłącz blokadę obrotu '
                              'w urządzeniu i obróć je ręcznie.',
                              key: Key('landscape-lock-unavailable'),
                              textAlign: TextAlign.center,
                            ),
                          ],
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
