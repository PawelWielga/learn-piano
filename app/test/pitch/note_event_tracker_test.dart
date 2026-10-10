import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/pitch_detector.dart';

PitchEstimate pitch(int midi, {double confidence = 0.99, double cents = 0}) =>
    PitchEstimate(
      frequencyHz: 440,
      midiNote: midi,
      confidence: confidence,
      centsFromNote: cents,
    );

Duration ms(int time) => Duration(milliseconds: time);

void main() {
  test('stable pitch produces exactly one NoteOn during a long hold', () {
    final tracker = NoteEventTracker();
    final onsets = <NoteEvent>[];
    for (final time in [0, 120, 240, 360, 480, 600, 720]) {
      final update = tracker.observe(pitch(60), ms(time));
      onsets.addAll(update.events);
    }

    expect(onsets, hasLength(1));
    expect(onsets.single.type, NoteEventType.noteOn);
    expect(onsets.single.midiNote, 60);
    expect(onsets.single.at, ms(240));
    expect(tracker.phase, NoteDetectionPhase.stable);
    expect(tracker.stableNote, 60);
  });

  test('C4 C4 C4 needs releases between distinct NoteOn events', () {
    final tracker = NoteEventTracker();
    final allEvents = <NoteEvent>[];
    void feed(int? note, int time) {
      allEvents.addAll(
        tracker.observe(note == null ? null : pitch(note), ms(time)).events,
      );
    }

    for (final time in [0, 120, 240, 360]) {
      feed(60, time);
    }
    for (final time in [480, 600, 720]) {
      feed(null, time);
    }
    for (final time in [840, 960, 1080, 1200]) {
      feed(60, time);
    }
    for (final time in [1320, 1440, 1560]) {
      feed(null, time);
    }
    for (final time in [1680, 1800, 1920, 2040]) {
      feed(60, time);
    }
    expect(allEvents.map((event) => event.type).toList(), [
      NoteEventType.noteOn,
      NoteEventType.noteOff,
      NoteEventType.noteOn,
      NoteEventType.noteOff,
      NoteEventType.noteOn,
    ]);
    expect(allEvents.map((event) => event.midiNote).toSet(), {60});
  });

  test('brief silence and single-semitone flicker preserve held note', () {
    final tracker = NoteEventTracker();
    tracker.observe(pitch(60), ms(0));
    tracker.observe(pitch(60), ms(120));
    expect(
      tracker.observe(pitch(60), ms(240)).events.single.type,
      NoteEventType.noteOn,
    );

    expect(tracker.observe(null, ms(360)).phase, NoteDetectionPhase.releasing);
    expect(tracker.observe(pitch(60), ms(480)).events, isEmpty);
    expect(
      tracker.observe(pitch(61), ms(600)).phase,
      NoteDetectionPhase.candidate,
    );
    expect(tracker.observe(pitch(60), ms(720)).events, isEmpty);
    expect(tracker.stableNote, 60);
    expect(tracker.phase, NoteDetectionPhase.stable);
  });

  test('sustained different pitch causes old NoteOff then new NoteOn', () {
    final tracker = NoteEventTracker();
    tracker.observe(pitch(60), ms(0));
    tracker.observe(pitch(60), ms(120));
    tracker.observe(pitch(60), ms(240));

    expect(tracker.observe(pitch(64), ms(360)).events, isEmpty);
    expect(tracker.observe(pitch(64), ms(480)).events, isEmpty);
    final events = tracker.observe(pitch(64), ms(600)).events;
    expect(events.map((event) => event.type), [
      NoteEventType.noteOff,
      NoteEventType.noteOn,
    ]);
    expect(events.map((event) => event.midiNote), [60, 64]);
    expect(tracker.stableNote, 64);
  });

  test('low confidence and out-of-tune estimates do not trigger', () {
    final tracker = NoteEventTracker();
    for (final time in [0, 120, 240, 360, 480]) {
      expect(
        tracker.observe(pitch(60, confidence: 0.6), ms(time)).events,
        isEmpty,
      );
    }
    for (final time in [600, 720, 840]) {
      expect(tracker.observe(pitch(60, cents: 42), ms(time)).events, isEmpty);
    }
    expect(tracker.phase, NoteDetectionPhase.silent);
  });

  test('candidate resets after observation gap and stale timestamps', () {
    final tracker = NoteEventTracker();
    tracker.observe(pitch(69), ms(0));
    tracker.observe(pitch(69), ms(120));
    expect(tracker.observe(pitch(69), ms(700)).events, isEmpty);
    expect(tracker.observe(pitch(69), ms(690)).events, isEmpty);
    expect(tracker.observe(pitch(69), ms(700)).events, isEmpty);
    expect(tracker.observe(pitch(69), ms(820)).events, isEmpty);
    expect(
      tracker.observe(pitch(69), ms(940)).events.single.type,
      NoteEventType.noteOn,
    );
  });

  test('short noise gaps cannot create repeated NoteOn', () {
    final tracker = NoteEventTracker(
      minStableDuration: const Duration(milliseconds: 100),
      minReleaseDuration: const Duration(milliseconds: 300),
    );
    final events = <NoteEvent>[];
    for (final time in [0, 120, 240, 360, 480, 600, 720, 840]) {
      final note = (time == 240 || time == 600) ? null : pitch(57);
      events.addAll(tracker.observe(note, ms(time)).events);
    }
    expect(events.where((e) => e.type == NoteEventType.noteOn), hasLength(1));
    expect(events.where((e) => e.type == NoteEventType.noteOff), isEmpty);
  });

  test('reset discards old notes and permits a fresh first NoteOn', () {
    final tracker = NoteEventTracker();
    for (final time in [0, 120, 240]) {
      tracker.observe(pitch(60), ms(time));
    }
    tracker.reset();
    expect(tracker.stableNote, isNull);
    expect(tracker.phase, NoteDetectionPhase.silent);

    tracker.observe(pitch(60), ms(0));
    tracker.observe(pitch(60), ms(120));
    expect(
      tracker.observe(pitch(60), ms(240)).events.single.type,
      NoteEventType.noteOn,
    );
  });
}
