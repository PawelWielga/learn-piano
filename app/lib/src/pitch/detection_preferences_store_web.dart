import 'dart:js_interop';

import 'detection_preferences.dart';
import 'detection_preferences_store.dart';

@JS('learnPianoDetection.read')
external JSString? _readPreferences();

@JS('learnPianoDetection.write')
external void _writePreferences(JSString value);

DetectionPreferencesStore createStore() => BrowserDetectionPreferencesStore();

class BrowserDetectionPreferencesStore implements DetectionPreferencesStore {
  @override
  DetectionPreferences? load() =>
      DetectionPreferences.decode(_readPreferences()?.toDart);

  @override
  void save(DetectionPreferences preferences) {
    _writePreferences(preferences.encode().toJS);
  }
}
