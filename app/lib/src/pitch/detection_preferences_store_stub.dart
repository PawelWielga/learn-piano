import 'detection_preferences.dart';
import 'detection_preferences_store.dart';

DetectionPreferencesStore createStore() => _SessionDetectionPreferencesStore();

class _SessionDetectionPreferencesStore implements DetectionPreferencesStore {
  static DetectionPreferences? _saved;

  @override
  DetectionPreferences? load() => _saved;

  @override
  void save(DetectionPreferences preferences) {
    _saved = preferences;
  }
}
