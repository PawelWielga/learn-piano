import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/pitch_detector.dart';
import 'package:learn_piano/src/training/wait_for_note_engine.dart';

import '../midi/midi_fixtures.dart';

void main() {
  test(
    'parsed MIDI and stable tracker move only on distinct NoteOn events',
    () {
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
      expect(
        scoring.where((result) => result == TrainingAttempt.correct),
        hasLength(3),
      );
      expect(
        scoring.where((result) => result == TrainingAttempt.incorrect),
        isEmpty,
      );
    },
  );

  test(
    'type 1 multi-track MIDI with tempo changes scores only selected melody',
    () {
      final midi = const MidiParser().parse(
        midiFixture(
          format: 1,
          tracks: [
            trackBytes([
              trackName('Tempo'),
              tempo(0, 500000),
              tempo(960, 1000000),
              endOfTrack(),
            ]),
            trackBytes([
              trackName('Lead'),
              event(0, [0x90, 60, 100]),
              event(480, [0x80, 60, 0]),
              event(240, [0x90, 60, 100]),
              event(240, [0x80, 60, 0]),
              event(480, [0x90, 64, 100]),
              event(480, [0x80, 64, 0]),
              endOfTrack(),
            ]),
            trackBytes([
              trackName('Chords'),
              event(0, [0x90, 67, 90]),
              event(0, [0x90, 71, 90]),
              event(480, [0x80, 67, 0]),
              event(0, [0x80, 71, 0]),
              endOfTrack(),
            ]),
            trackBytes([
              trackName('Out of range'),
              event(0, [0x91, 36, 90]),
              event(480, [0x81, 36, 0]),
              endOfTrack(),
            ]),
          ],
        ),
      );
      final analyzer = const MelodyPartAnalyzer();
      final parts = analyzer.analyze(midi);
      const range = InstrumentRange(48, 72);
      expect(parts, hasLength(3));
      final selected = analyzer.select(parts, trackIndex: 1, channel: 0);
      expect(selected, isNotNull);
      expect(selected!.notes.map((note) => note.midiNote), [60, 60, 64]);
      expect(selected.notes.map((note) => note.start), [
        Duration.zero,
        const Duration(milliseconds: 750),
        const Duration(seconds: 2),
      ]);
      expect(
        range.checkNotes(selected.notes.map((n) => n.midiNote)).canPractice,
        isTrue,
      );

      // Chord tracks remain intact and can be trained as a group.
      final chord = analyzer.select(parts, trackIndex: 2, channel: 0);
      expect(chord, isNotNull);
      expect(chord!.notes.map((note) => note.midiNote), [67, 71]);
      final bass = analyzer.select(parts, trackIndex: 3, channel: 1);
      expect(bass, isNotNull);
      expect(
        range.checkNotes(bass!.notes.map((note) => note.midiNote)).outsideCount,
        1,
      );
      expect(
        WaitForNoteEngine(bass, instrumentRange: range).snapshot.phase,
        TrainingPhase.error,
      );

      final engine = WaitForNoteEngine(selected, instrumentRange: range)
        ..start();
      final tracker = NoteEventTracker();
      final attempts = <TrainingAttempt>[];

      void observe(int? note, int milliseconds) {
        final estimate = note == null
            ? null
            : PitchEstimate(
                frequencyHz: 440,
                midiNote: note,
                confidence: 0.99,
                centsFromNote: 0,
              );
        final update = tracker.observe(
          estimate,
          Duration(milliseconds: milliseconds),
        );
        for (final event in update.events) {
          final outcome = engine.onNoteEvent(event);
          if (event.type == NoteEventType.noteOn) {
            attempts.add(outcome.attempt);
          }
        }
      }

      void hold(int? note, int startMs) {
        for (final offset in [0, 130, 260, 390]) {
          observe(note, startMs + offset);
        }
      }

      hold(62, 0); // Wrong note.
      expect(engine.snapshot.currentIndex, 0);
      hold(null, 520);
      hold(60, 1040);
      expect(engine.snapshot.currentIndex, 1);
      hold(60, 1560); // Continuous sound is not a second strike.
      expect(engine.snapshot.currentIndex, 1);
      hold(null, 2080);
      hold(60, 2600);
      expect(engine.snapshot.currentIndex, 2);
      hold(null, 3120);
      hold(64, 3640);
      expect(attempts, [
        TrainingAttempt.incorrect,
        TrainingAttempt.correct,
        TrainingAttempt.correct,
        TrainingAttempt.correct,
      ]);
      expect(engine.snapshot.phase, TrainingPhase.completed);
      expect(engine.snapshot.progress, 1);
    },
  );

  test('malformed MIDI fails while chord-only MIDI trains intact', () {
    expect(
      () => const MidiParser().parse(Uint8List.fromList([0, 1, 2, 3])),
      throwsA(isA<MidiFormatException>()),
    );
    final midi = const MidiParser().parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x90, 60, 100]),
            event(0, [0x90, 64, 100]),
            event(480, [0x80, 60, 0]),
            event(0, [0x80, 64, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final analyzer = const MelodyPartAnalyzer();
    final parts = analyzer.analyze(midi);
    expect(parts.single.overlapCount, 1);
    expect(parts.single.canPractice, isTrue);
    final selection = analyzer.select(parts, trackIndex: 0, channel: 0);
    expect(selection, isNotNull);
    final engine = WaitForNoteEngine(
      selection!,
      instrumentRange: const InstrumentRange(48, 72),
    )..start();
    expect(engine.snapshot.expectedMidiNotes, {60, 64});
    expect(
      engine.onNoteEvent(
        const NoteEvent(
          type: NoteEventType.noteOn,
          midiNote: 60,
          at: Duration.zero,
        ),
      ).attempt,
      TrainingAttempt.ignored,
    );
    expect(
      engine.onNoteEvent(
        const NoteEvent(
          type: NoteEventType.noteOn,
          midiNote: 64,
          at: Duration.zero,
        ),
      ).attempt,
      TrainingAttempt.correct,
    );
    expect(engine.snapshot.isCompleted, isTrue);
  });
}
