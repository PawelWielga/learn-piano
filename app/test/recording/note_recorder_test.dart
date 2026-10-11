import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/recording/midi_recording_writer.dart';
import 'package:learn_piano/src/recording/note_recorder.dart';

void main() {
  test('pairs separate presses of the same note with accurate durations', () {
    final recorder = NoteRecorder()..start();
    recorder.noteOn(60, const Duration(milliseconds: 100));
    recorder.noteOn(60, const Duration(milliseconds: 150));
    recorder.noteOff(60, const Duration(milliseconds: 440));
    recorder.noteOn(60, const Duration(milliseconds: 540));
    recorder.noteOff(60, const Duration(milliseconds: 690));
    recorder.stop(const Duration(milliseconds: 800));

    expect(recorder.noteCount, 2);
    expect(recorder.notes.map((note) => note.start), [
      const Duration(milliseconds: 100),
      const Duration(milliseconds: 540),
    ]);
    expect(recorder.notes.map((note) => note.duration), [
      const Duration(milliseconds: 340),
      const Duration(milliseconds: 150),
    ]);
  });

  test('simultaneous notes and held notes are completed at stop', () {
    final recorder = NoteRecorder()..start();
    recorder.noteOn(67, const Duration(milliseconds: 40));
    recorder.noteOn(60, const Duration(milliseconds: 50));
    recorder.noteOff(67, const Duration(milliseconds: 150));
    recorder.stop(const Duration(milliseconds: 280));
    recorder.noteOn(72, const Duration(milliseconds: 300));

    expect(recorder.noteCount, 2);
    expect(recorder.activeCount, 0);
    expect(recorder.notes.map((note) => note.midiNote), [67, 60]);
    expect(recorder.notes.last.duration, const Duration(milliseconds: 230));
  });

  test('rejects invalid notes and respects note limit', () {
    final recorder = NoteRecorder(maxNotes: 1)..start();
    recorder.noteOn(-1, Duration.zero);
    recorder.noteOn(60, Duration.zero);
    recorder.noteOn(62, Duration.zero);
    expect(recorder.noteCount, 1);
    expect(recorder.isFull, isTrue);
    recorder.stop(const Duration(milliseconds: 100));
    expect(recorder.notes.single.midiNote, 60);
    recorder.start();
    expect(recorder.notes, isEmpty);
    expect(recorder.isFull, isFalse);
  });

  test('generated MIDI round-trips through the existing importer', () {
    final recorder = NoteRecorder()..start();
    recorder.noteOn(60, const Duration(milliseconds: 100));
    recorder.noteOn(64, const Duration(milliseconds: 100));
    recorder.noteOff(60, const Duration(milliseconds: 900));
    recorder.noteOff(64, const Duration(milliseconds: 910));
    recorder.noteOn(60, const Duration(milliseconds: 910));
    recorder.noteOff(60, const Duration(milliseconds: 1210));
    recorder.stop(const Duration(milliseconds: 1210));

    final midiBytes = const MidiRecordingWriter().write(recorder.notes);
    final file = const MidiParser().parse(midiBytes);
    expect(file.format, 0);
    expect(file.ticksPerQuarterNote, 480);
    expect(file.tracks, hasLength(1));
    expect(file.noteCount, 3);
    final notes = file.tracks.single.notes;
    expect(notes.map((n) => n.midiNote), [60, 64, 60]);
    expect(notes[0].start.inMilliseconds, closeTo(100, 2));
    expect(notes[0].duration.inMilliseconds, closeTo(800, 2));
    expect(notes[1].duration.inMilliseconds, closeTo(810, 2));
    expect(notes[2].start.inMilliseconds, closeTo(910, 2));
  });

  test('very short notes are still valid NoteOn/NoteOff MIDI pairs', () {
    final bytes = const MidiRecordingWriter().write([
      const RecordedNote(
        midiNote: 60,
        start: Duration.zero,
        duration: Duration.zero,
      ),
    ]);
    final file = const MidiParser().parse(bytes);
    expect(file.noteCount, 1);
    expect(
      file.tracks.single.notes.single.duration,
      greaterThan(Duration.zero),
    );
  });
}
