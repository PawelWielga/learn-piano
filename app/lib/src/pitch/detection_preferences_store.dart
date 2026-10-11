import 'detection_preferences.dart';

/// Persists only detection thresholds, never sound samples or MIDI files.
abstract class DetectionPreferencesStore {
  DetectionPreferences? load();
  void save(DetectionPreferences preferences);
}
