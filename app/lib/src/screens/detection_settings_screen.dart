import 'package:flutter/material.dart';

import '../pitch/detection_preferences.dart';
import '../pitch/detection_preferences_store.dart';
import '../pitch/detection_preferences_store_factory.dart';

/// Adjusts the acoustic detector for the microphone tester and training.
class DetectionSettingsScreen extends StatefulWidget {
  const DetectionSettingsScreen({super.key, this.store});

  final DetectionPreferencesStore? store;

  @override
  State<DetectionSettingsScreen> createState() =>
      _DetectionSettingsScreenState();
}

class _DetectionSettingsScreenState extends State<DetectionSettingsScreen> {
  late final DetectionPreferencesStore _store;
  DetectionPreferences _preferences = const DetectionPreferences();
  String? _storageWarning;

  @override
  void initState() {
    super.initState();
    _store = widget.store ?? createDetectionPreferencesStore();
    try {
      _preferences = _store.load() ?? const DetectionPreferences();
    } catch (_) {
      _storageWarning = 'Nie można odczytać ustawień tej przeglądarki.';
    }
  }

  void _update(DetectionPreferences preferences) {
    setState(() {
      _preferences = preferences;
      _storageWarning = null;
    });
    try {
      _store.save(preferences);
    } catch (_) {
      setState(() {
        _storageWarning =
            'Zapis w przeglądarce jest zablokowany. '
            'Ustawienia działają w tej karcie, ale mogą zniknąć po jej zamknięciu.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia mikrofonu')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Rozpoznawanie dźwięków',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Ustawienia dotyczą rozpoznawania przez mikrofon '
                  'w teście, treningu i nagrywaniu. Nie wpływają na '
                  'klawiaturę ekranową ani odtwarzanie MIDI.'
                ),
                const SizedBox(height: 20),
                if (_storageWarning != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _storageWarning!,
                    key: const Key('detection-settings-storage-warning'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                SwitchListTile.adaptive(
                  key: const Key('detection-increased-sensitivity'),
                  title: const Text('Zwiększona czułość mikrofonu'),
                  subtitle: const Text(
                    'Wykrywaj cichsze nuty. Obniża próg sygnału '
                    'z 0,015 do 0,005 RMS.',
                  ),
                  value: _preferences.increasedSensitivity,
                  onChanged: (value) => _update(
                    DetectionPreferences(
                      increasedSensitivity: value,
                      widerTuningTolerance: _preferences.widerTuningTolerance,
                    ),
                  ),
                ),
                SwitchListTile.adaptive(
                  key: const Key('detection-wider-tolerance'),
                  title: const Text('Większa tolerancja strojenia'),
                  subtitle: const Text(
                    'Zaliczaj lekko rozstrojone dźwięki. '
                    'Poszerza tolerancję z ±35 do ±45 centów '
                    '(półton to 100 centów).',
                  ),
                  value: _preferences.widerTuningTolerance,
                  onChanged: (value) => _update(
                    DetectionPreferences(
                      increasedSensitivity: _preferences.increasedSensitivity,
                      widerTuningTolerance: value,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Aktualny próg: ${_preferences.minimumRms.toStringAsFixed(3)} RMS. '
                  'Tolerancja: ±${_preferences.maximumCentsDeviation.toStringAsFixed(0)} centów.',
                  key: const Key('detection-settings-summary'),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Wyższa czułość może częściej wykrywać szum i wybrzmiewanie. '
                  'Rozszerzona tolerancja nie zmienia wysokości rozpoznanej nuty '
                  'i nie obejmuje sąsiedniego półtonu. Jeśli pojawiają się '
                  'fałszywe trafienia, wyłącz odpowiednią opcję.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
