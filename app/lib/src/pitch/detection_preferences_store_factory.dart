import 'detection_preferences_store.dart';
import 'detection_preferences_store_stub.dart'
    if (dart.library.js_interop) 'detection_preferences_store_web.dart'
    as platform;

DetectionPreferencesStore createDetectionPreferencesStore() =>
    platform.createStore();
