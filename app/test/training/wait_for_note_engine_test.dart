import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/training/wait_for_note_engine.dart';

MidiNote midiNote(int pitch, int start, int end) => MidiNote(
  trackIndex: 0,
  channel: 0,
  midiNote: pitch,
  velocity: 100,
  startTick: start,
  endTick: end,
  start: Duration(milliseconds: start),
  duration: Duration(milliseconds: end - start),
);

MelodySelection melody(
  List<MidiNote> notes, {
  int channel = 0,
  int overlapCount = 0,
}) {
  final pitches = notes.map((n) => n.midiNote).toList()..sort();
  return MelodySelection(
    MelodyPart(
      trackIndex: 0,
      trackName: 'Test',
      channel: channel,
      notes: List.unmodifiable(notes),
      overlapCount: overlapCount,
      minMidiNote: pitches.isEmpty ? 0 : pitches.first,
      maxMidiNote: pitches.isEmpty ? 0 : pitches.last,
      start: notes.isEmpty ? Duration.zero : notes.first.start,
      duration: notes.isEmpty
          ? Duration.zero
          : notes.last.start + notes.last.duration - notes.first.start,
    ),
  );
}

WaitForNoteEngine engineFor(List<MidiNote> notes) => WaitForNoteEngine(
  melody(notes),
  instrumentRange: const InstrumentRange(36, 96),
);

NoteEvent on(int pitch, [int millis = 0]) => NoteEvent(
  type: NoteEventType.noteOn,
  midiNote: pitch,
  at: Duration(milliseconds: millis),
);

NoteEvent off(int pitch, [int millis = 0]) => NoteEvent(
  type: NoteEventType.noteOff,
  midiNote: pitch,
  at: Duration(milliseconds: millis),
);

void main() {
  test('right note advances exactly once; wrong pitch and octave do not', () {
    final engine = engineFor([
      midiNote(60, 0, 480),
      midiNote(64, 960, 1920),
      midiNote(67, 3840, 4320),
    ]);

    expect(engine.snapshot.phase, TrainingPhase.ready);
    expect(engine.snapshot.expectedMidiNote, 60);
    expect(engine.snapshot.progress, 0);
    engine.start();
    expect(engine.onNoteEvent(on(72)).attempt, TrainingAttempt.incorrect);
    expect(engine.snapshot.currentIndex, 0);
    expect(engine.snapshot.lastPlayedMidiNote, 72);
    expect(engine.onNoteEvent(on(62)).attempt, TrainingAttempt.incorrect);
    expect(engine.snapshot.expectedMidiNote, 60);

    final correct = engine.onNoteEvent(on(60));
    expect(correct.attempt, TrainingAttempt.correct);
    expect(correct.snapshot.currentIndex, 1);
    expect(correct.snapshot.expectedMidiNote, 64);
    expect(correct.snapshot.progress, closeTo(1 / 3, 0.00001));
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    expect(engine.snapshot.currentIndex, 1);

    // Timing gaps and note durations from MIDI never advance the cursor.
    expect(engine.snapshot.expectedMidiNote, 64);
    engine.onNoteEvent(off(60));
    expect(engine.onNoteEvent(on(64)).attempt, TrainingAttempt.correct);
    engine.onNoteEvent(off(64));
    expect(engine.onNoteEvent(on(67)).attempt, TrainingAttempt.correct);
    expect(engine.snapshot.phase, TrainingPhase.completed);
    expect(engine.snapshot.expectedMidiNote, isNull);
    expect(engine.snapshot.completedNotes, 3);
    expect(engine.snapshot.progress, 1);
    expect(engine.onNoteEvent(on(72)).attempt, TrainingAttempt.ignored);
    expect(engine.snapshot.currentIndex, 3);
  });

  test('C4 C4 C4 takes three separate NoteOn after releases', () {
    final engine = engineFor([
      midiNote(60, 0, 200),
      midiNote(60, 200, 400),
      midiNote(60, 400, 600),
    ])..start();

    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.correct);
    for (var i = 0; i < 5; i++) {
      expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    }
    expect(engine.snapshot.currentIndex, 1);
    engine.onNoteEvent(off(60));
    expect(engine.onNoteEvent(on(60)).snapshot.currentIndex, 2);
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    engine.onNoteEvent(off(60));
    expect(engine.onNoteEvent(on(60)).snapshot.phase, TrainingPhase.completed);
    expect(engine.snapshot.currentIndex, 3);
  });

  test('ready/paused events are ignored but still gate held keys on resume', () {
    final engine = engineFor([
      midiNote(60, 0, 100),
      midiNote(62, 200, 300),
    ]);
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    engine.start();
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    engine.onNoteEvent(off(60));
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.correct);
    expect(engine.pause().phase, TrainingPhase.paused);
    expect(engine.pause().phase, TrainingPhase.paused);
    expect(engine.onNoteEvent(on(62)).attempt, TrainingAttempt.ignored);
    expect(engine.snapshot.currentIndex, 1);
    expect(engine.resume().phase, TrainingPhase.running);
    expect(engine.onNoteEvent(on(62)).attempt, TrainingAttempt.ignored);
    expect(engine.snapshot.currentIndex, 1);
    engine.onNoteEvent(off(62));
    expect(engine.onNoteEvent(on(62)).attempt, TrainingAttempt.correct);
    expect(engine.snapshot.phase, TrainingPhase.completed);
    expect(engine.resume().phase, TrainingPhase.completed);
  });

  test('reset preserves held keys and clears feedback/progress safely', () {
    final engine = engineFor([
      midiNote(60, 0, 100),
      midiNote(60, 100, 200),
    ])..start();
    engine.onNoteEvent(on(60));
    expect(engine.snapshot.lastAttempt, TrainingAttempt.correct);
    expect(engine.reset().phase, TrainingPhase.ready);
    expect(engine.snapshot.currentIndex, 0);
    expect(engine.snapshot.lastPlayedMidiNote, isNull);
    expect(engine.snapshot.lastAttempt, TrainingAttempt.ignored);

    engine.start();
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    engine.onNoteEvent(off(60));
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.correct);
    expect(engine.snapshot.currentIndex, 1);
    engine.reset();
    expect(engine.snapshot.phase, TrainingPhase.ready);
    engine.start();
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    engine.onNoteEvent(off(60));
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.correct);
  });

  test('wrong events do not count twice until a new release and onset', () {
    final engine = engineFor([midiNote(62, 0, 100)])..start();
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.incorrect);
    expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
    expect(engine.snapshot.lastAttempt, TrainingAttempt.incorrect);
    expect(engine.snapshot.currentIndex, 0);
    engine.onNoteEvent(off(60));
    expect(engine.onNoteEvent(on(62)).attempt, TrainingAttempt.correct);
  });

  test('invalid pitch is ignored and cannot score an invalid key', () {
    final engine = engineFor([midiNote(60, 0, 100)])..start();
    expect(engine.onNoteEvent(on(-1)).attempt, TrainingAttempt.ignored);
    expect(engine.onNoteEvent(on(128)).attempt, TrainingAttempt.ignored);
    expect(engine.snapshot.currentIndex, 0);
  });

  test('invalid or out-of-range selections remain in error state', () {
    final selections = [
      melody([]),
      melody([midiNote(60, 0, 100)], channel: 9),
      melody([
        midiNote(60, 0, 200),
        midiNote(64, 100, 300),
      ], overlapCount: 1),
      melody([
        midiNote(60, 0, 200),
        midiNote(64, 100, 300),
      ]), // Malformed manually supplied part cannot bypass validation.
      melody([midiNote(24, 0, 100)]),
    ];
    for (final selection in selections) {
      final engine = WaitForNoteEngine(
        selection,
        instrumentRange: const InstrumentRange(36, 96),
      );
      expect(engine.snapshot.phase, TrainingPhase.error);
      expect(engine.snapshot.errorMessage, isNotEmpty);
      expect(engine.start().phase, TrainingPhase.error);
      expect(engine.onNoteEvent(on(60)).attempt, TrainingAttempt.ignored);
      expect(engine.reset().phase, TrainingPhase.error);
    }
  });
}
