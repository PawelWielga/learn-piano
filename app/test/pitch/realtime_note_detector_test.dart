import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/realtime_note_detector.dart';

import 'realtime_pcm_replay_test.dart' as fixtures;

void main() {
  test('mono adapter emits one real onset, releases, resets', () {
    final frames = fixtures.packets(48000, 2000, [
      const fixtures.TestTone(60, 300, 1200),
    ]);
    final detector = YinRealtimeDetector();
    final events = <NoteEvent>[];
    for (final frame in frames) {
      final result = detector.observe(frame);
      expect(result.source, RealtimeDetectorSource.yin);
      expect(result.evidence, RealtimeEvidence.periodicity);
      expect(result.hasCalibratedNoteProbabilities, false);
      events.addAll(result.events);
    }
    expect(
      events
          .where((e) => e.type == NoteEventType.noteOn)
          .map((e) => e.midiNote),
      [60],
    );
    expect(
      events
          .where((e) => e.type == NoteEventType.noteOff)
          .map((e) => e.midiNote),
      [60],
    );
    detector.reset();
    final second = <NoteEvent>[];
    for (final frame in frames) {
      second.addAll(detector.observe(frame).events);
    }
    expect(second.where((e) => e.type == NoteEventType.noteOn), hasLength(1));
  });

  test('FFT adapter exposes missing confidence rather than fabricating it', () {
    final frames = fixtures.packets(48000, 2600, [
      const fixtures.TestTone(48, 400, 1750, gain: 0.23, second: 0.08),
      const fixtures.TestTone(60, 400, 1750, gain: 0.12, second: 0.08),
    ]);
    final detector = FftRealtimeDetector();
    final events = <NoteEvent>[];
    for (final frame in frames) {
      final result = detector.observe(frame);
      expect(result.source, RealtimeDetectorSource.legacyPolyphonicFft);
      expect(result.evidence, RealtimeEvidence.uncalibratedPolyphony);
      expect(result.periodicityConfidence, isNull);
      expect(result.hasCalibratedNoteProbabilities, false);
      events.addAll(result.events);
    }
    final pitches = events
        .where((e) => e.type == NoteEventType.noteOn)
        .map((e) => e.midiNote)
        .toSet();
    expect(pitches, contains(48));
    // Known C3/C4 masking must remain observable, but a later fix
    // must not fail the test simply because it detects C4 correctly.
    expect(pitches.difference({48, 60}).length, lessThanOrEqualTo(2));
    detector.reset();
    expect(detector.observe(frames.first).activeNotes, isEmpty);
  });

  test('silence emits no NoteOn with either implementation', () {
    for (final rate in fixtures.rates) {
      for (final detector in [YinRealtimeDetector(), FftRealtimeDetector()]) {
        final events = <NoteEvent>[];
        for (final frame in fixtures.packets(rate, 1500, [])) {
          events.addAll(detector.observe(frame).events);
        }
        expect(events.where((e) => e.type == NoteEventType.noteOn), isEmpty);
      }
    }
  });
}
