import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/pitch/detection_preferences.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/pitch_detector.dart';

void main() {
  test('defaults and both switches round-trip safely', () {
    const defaults = DetectionPreferences();
    expect(defaults.minimumRms, 0.015);
    expect(defaults.maximumCentsDeviation, 35);
    expect(DetectionPreferences.decode(defaults.encode())?.encode(), 'v1:0:0');

    for (final sensitive in [false, true]) {
      for (final tolerant in [false, true]) {
        final preferences = DetectionPreferences(
          increasedSensitivity: sensitive,
          widerTuningTolerance: tolerant,
        );
        final decoded = DetectionPreferences.decode(preferences.encode());
        expect(decoded?.increasedSensitivity, sensitive);
        expect(decoded?.widerTuningTolerance, tolerant);
      }
    }
    for (final invalid in ['', 'v0:1:0', 'v1:2:0', 'v1:0:1:extra']) {
      expect(DetectionPreferences.decode(invalid), isNull);
    }
    expect(DetectionPreferences.decode(null), isNull);
  });

  test('sensitivity accepts quiet periodic notes, not silence or noise', () {
    final samples = Float32List.fromList(
      List<double>.generate(
        2048,
        (i) => 0.01 * math.sin(2 * math.pi * 440 * i / 48000),
      ),
    );
    const defaults = DetectionPreferences();
    const sensitive = DetectionPreferences(increasedSensitivity: true);
    expect(defaults.createDetector().detect(samples, 48000), isNull);
    expect(sensitive.createDetector().detect(samples, 48000)?.midiNote, 69);
    expect(sensitive.createDetector().detect(Float32List(2048), 48000), isNull);
  });

  test('tolerance accepts 42 cents but still rejects near-semitone edge', () {
    const normal = DetectionPreferences();
    const tolerant = DetectionPreferences(widerTuningTolerance: true);

    List<NoteEvent> observe(NoteEventTracker tracker, double cents) {
      final events = <NoteEvent>[];
      for (final time in [0, 120, 240]) {
        events.addAll(
          tracker
              .observe(
                PitchEstimate(
                  frequencyHz: 440,
                  midiNote: 69,
                  confidence: 0.99,
                  centsFromNote: cents,
                ),
                Duration(milliseconds: time),
              )
              .events,
        );
      }
      return events;
    }

    expect(observe(normal.createTracker(), 42), isEmpty);
    expect(
      observe(
        tolerant.createTracker(),
        42,
      ).where((event) => event.type == NoteEventType.noteOn).single.midiNote,
      69,
    );
    expect(observe(tolerant.createTracker(), 49), isEmpty);
    expect(observe(tolerant.createTracker(), -44), hasLength(1));
  });
}
