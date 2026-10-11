import 'package:flutter/material.dart';

import 'microphone_preview_screen.dart';
import 'detection_settings_screen.dart';
import 'recording_screen.dart';
import 'mp3_import_screen.dart';
import 'midi_import_screen.dart';
import 'instrument_range_screen.dart';
import '../instrument/instrument_range.dart';

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
                Icon(Icons.piano, size: 72, color: theme.colorScheme.primary),
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
                  'Sprawdź zgodę na mikrofon i poziom dźwięku.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const Key('open-midi-import'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MidiImportScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.upload_file),
                  label: const Text('Importuj plik MIDI'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Wczytaj melodię i podejrzyj nuty oraz ścieżki.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  key: const Key('open-instrument-range'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<InstrumentRange>(
                        builder: (_) => const InstrumentRangeScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.tune),
                  label: const Text('Ustaw zakres klawiatury'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const Key('open-detection-settings'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const DetectionSettingsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.settings_input_component),
                  label: const Text('Ustawienia mikrofonu'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 28),
                OutlinedButton.icon(
                  key: const Key('training-start-from-home'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MidiImportScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.music_note),
                  label: const Text('Ćwicz z plikiem MIDI'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  key: const Key('open-note-recording'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const RecordingScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.fiber_manual_record),
                  label: const Text('Nagraj własną melodię'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Graj przez mikrofon lub na ekranie, a potem zapisz plik MIDI.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  key: const Key('open-mp3-import'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Mp3ImportScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.audio_file),
                  label: const Text('Odczytaj nuty z MP3'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Wczytaj krótkie nagranie pojedynczej melodii '
                  'i zapisz rozpoznane nuty jako MIDI.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
