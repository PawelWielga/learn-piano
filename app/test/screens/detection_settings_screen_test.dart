import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/pitch/detection_preferences.dart';
import 'package:learn_piano/src/pitch/detection_preferences_store.dart';
import 'package:learn_piano/src/screens/detection_settings_screen.dart';

class FakeDetectionStore implements DetectionPreferencesStore {
  DetectionPreferences? saved;
  bool failSave = false;

  @override
  DetectionPreferences? load() => saved;

  @override
  void save(DetectionPreferences preferences) {
    saved = preferences;
    if (failSave) throw StateError('storage unavailable');
  }
}

void main() {
  testWidgets('independent switches persist and survive reopening settings', (
    tester,
  ) async {
    final store = FakeDetectionStore();

    Future<void> openSettings() async {
      await tester.pumpWidget(
        MaterialApp(home: DetectionSettingsScreen(store: store)),
      );
    }

    await openSettings();
    await tester.tap(find.byKey(const Key('detection-increased-sensitivity')));
    await tester.pump();
    expect(store.saved?.increasedSensitivity, isTrue);
    expect(store.saved?.widerTuningTolerance, isFalse);

    await tester.tap(find.byKey(const Key('detection-wider-tolerance')));
    await tester.pump();
    expect(store.saved?.increasedSensitivity, isTrue);
    expect(store.saved?.widerTuningTolerance, isTrue);
    expect(find.textContaining('±45 centów.'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await openSettings();
    final first = tester.widget<SwitchListTile>(
      find.byKey(const Key('detection-increased-sensitivity')),
    );
    final second = tester.widget<SwitchListTile>(
      find.byKey(const Key('detection-wider-tolerance')),
    );
    expect(first.value, isTrue);
    expect(second.value, isTrue);
  });

  testWidgets('blocked storage shows a warning without changing the switch', (
    tester,
  ) async {
    final store = FakeDetectionStore()..failSave = true;
    await tester.pumpWidget(
      MaterialApp(home: DetectionSettingsScreen(store: store)),
    );
    await tester.tap(find.byKey(const Key('detection-increased-sensitivity')));
    await tester.pump();
    expect(
      find.byKey(const Key('detection-settings-storage-warning')),
      findsOneWidget,
    );
    expect(store.saved?.increasedSensitivity, isTrue);
  });
}
