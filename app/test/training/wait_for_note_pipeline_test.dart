import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/pitch_detector.dart';
import 'package:learn_piano/src/training/wait_for_note_engine.dart';

import '../midi/midi_fixtures.dart';

void main() {
  test('parsed MIDI and stable tracker move only on distinct NoteOn events', () {
    final midi = const MidiParser().parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x90, 60, 100]),
            event(480, [0x80, 60, 0]),
            event(480, [0x90, 60, 100]),
            event(480, [0x80, 60, 0]),
            event(240, [0x90, 64, 100]),
            event(480, [0x80, 64, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final part = const MelodyPartAnalyzer().analyze(midi).single;
    expect(part.canPractice, isTrue);
    final engine = WaitForNoteEngine(
      MelodySelection(part),
      instrumentRange: const InstrumentRange(48, 72),
    )..start();
    final tracker = NoteEventTracker();
    final scoring = <TrainingAttempt>[];

    void feed(int? midiNote, int milliseconds) {
      final pitch = midiNote == null
          ? null
          : PitchEstimate(
              frequencyHz: 440,
              midiNote: midiNote,
              confidence: 0.99,
              centsFromNote: 0,
            );
      final update = tracker.observe(
        pitch,
        Duration(milliseconds: milliseconds),
      );
      for (final noteEvent in update.events) {
        scoring.add(engine.onNoteEvent(noteEvent).attempt);
      }
    }

    for (final t in [0, 120, 240, 360]) {
      feed(60, t);
    }
    expect(engine.snapshot.currentIndex, 1);
    for (final t in [480, 600, 720]) {
      feed(null, t);
    }
    for (final t in [840, 960, 1080, 1200]) {
      feed(60, t);
    }
    expect(engine.snapshot.currentIndex, 2);
    for (final t in [1320, 1440, 1560]) {
      feed(null, t);
    }
    for (final t in [1680, 1800, 1920, 2040]) {
      feed(64, t);
    }
    expect(engine.snapshot.isCompleted, isTrue);
    expect(scoring.where((result) => result == TrainingAttempt.correct), hasLength(3));
    expect(scoring.where((result) => result == TrainingAttempt.incorrect), isEmpty);
  });
}
