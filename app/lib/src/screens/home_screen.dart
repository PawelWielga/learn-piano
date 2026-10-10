import 'package:flutter/material.dart';

import 'microphone_preview_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Learn Piano')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 24),
                Icon(
                  Icons.piano,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Ucz się na swoim pianinku',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  'Ćwicz grę na prawdziwym pianinie lub keyboardzie. '
                  'Bez konta i bez wysyłania dźwięku do serwera.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 36),
                FilledButton.icon(
                  key: const Key('open-microphone-preview'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MicrophonePreviewScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.mic),
                  label: const Text('Test mikrofonu'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Ekran przygotowawczy. Nasłuch dodamy w następnym etapie.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  key: const Key('training-coming-soon'),
                  onPressed: null,
                  icon: const Icon(Icons.music_note),
                  label: const Text('Trening z pliku MIDI (wkrótce)'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
