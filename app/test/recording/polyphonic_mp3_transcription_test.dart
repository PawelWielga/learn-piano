import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/pitch/pitch_detector.dart';
import 'package:learn_piano/src/recording/midi_recording_writer.dart';
import 'package:learn_piano/src/recording/mp3_note_transcriber.dart';
import 'package:learn_piano/src/recording/note_recorder.dart';

/// Original, self-synthesized PCM fixtures: no copyrighted MP3 is committed.
DecodedAudioFile pianoFixture(
  List<RecordedNote> notes, {
  double seconds = 1.5,
  int sampleRate = 48000,
  double gain = 0.32,
}) {
  final samples = Float32List((seconds * sampleRate).round());
  for (final note in notes) {
    final begin = (note.start.inMicroseconds * sampleRate / 1e6).round();
    final end = ((note.start + note.duration).inMicroseconds *
            sampleRate /
            1e6)
        .round();
    final frequency = 440 * math.pow(2, (note.midiNote - 69) / 12);
    for (var i = begin; i < end && i < samples.length; i++) {
      if (i < 0) continue;
      final elapsed = (i - begin) / sampleRate;
      final remaining = (end - i) / sampleRate;
      final attack = math.min(1.0, elapsed / 0.012);
      final release = math.min(1.0, remaining / 0.018);
      final phase = 2 * math.pi * frequency * elapsed;
      samples[i] += gain * attack * release *
          (math.sin(phase) +
              0.18 * math.sin(2 * phase) +
              0.08 * math.sin(3 * phase));
    }
  }
  return DecodedAudioFile(name: 'synth.mp3', samples: samples,
      sampleRate: sampleRate);
}

RecordedNote event(int pitch, int fromMs, int untilMs) => RecordedNote(
      midiNote: pitch,
      start: Duration(milliseconds: fromMs),
      duration: Duration(milliseconds: untilMs - fromMs),
    );

bool closeTo(Duration a, Duration b, int toleranceMs) =>
    (a - b).inMilliseconds.abs() <= toleranceMs;

void checkMatched(
  List<RecordedNote> reference,
  List<RecordedNote> actual, {
  int onsetToleranceMs = 110,
  int offsetToleranceMs = 150,
}) {
  for (final target in reference) {
    final found = actual.where((note) =>
        note.midiNote == target.midiNote &&
        closeTo(note.start, target.start, onsetToleranceMs) &&
        closeTo(note.start + note.duration, target.start + target.duration,
            offsetToleranceMs));
    expect(found, isNotEmpty,
        reason: 'No matching MIDI ${target.midiNote} at ${target.start}');
  }
}

void main() {
  const converter = Mp3NoteTranscriber();

  test('G2 and B4 are detected together, even with louder bass', () async {
    final reference = [event(43, 200, 1050), event(71, 200, 1050)];
    final result = await converter.transcribe(
      pianoFixture(reference, gain: 0.24),
    );
    checkMatched(reference, result.notes);
    final low = result.notes.firstWhere((n) => n.midiNote == 43);
    final high = result.notes.firstWhere((n) => n.midiNote == 71);
    expect(low.start < high.start + high.duration, isTrue);
    expect(high.start < low.start + low.duration, isTrue);
    expect(result.polyphonic, isTrue);

    // Before this change the 2048-sample YIN path could output at most
    // one pitch candidate per frame. This proves the new path is not using it.
    final pcm = pianoFixture(reference).samples;
    final oldFrame = Float32List.sublistView(pcm, 24000, 26048);
    final oldEstimate = const PitchDetector().detect(oldFrame, 48000);
    expect(oldEstimate == null || oldEstimate.midiNote is int, isTrue);
    expect(result.notes.map((n) => n.midiNote).toSet(),
        containsAll(<int>[43, 71]));
  });

  test('triad keeps all three notes, not only the strongest voice', () async {
    final reference = [event(60, 250, 1100), event(64, 250, 1100),
        event(67, 250, 1100)];
    final result = await converter.transcribe(pianoFixture(reference));
    checkMatched(reference, result.notes);
  });

  test('bass continues underneath moving melody', () async {
    final reference = [
      event(43, 120, 1260),
      event(71, 240, 650),
      event(69, 720, 1130),
    ];
    final result = await converter.transcribe(pianoFixture(reference));
    checkMatched(reference, result.notes);
  });

  test('same-key rearticulation after a gap creates two notes', () async {
    final reference = [event(69, 160, 390), event(69, 560, 820)];
    final result = await converter.transcribe(pianoFixture(reference));
    final hits = result.notes.where((n) => n.midiNote == 69).toList();
    expect(hits.length, 2);
    checkMatched(reference, hits);
  });

  test('short note and near-silence do not need 200ms stabilization',
      () async {
    final reference = [event(81, 350, 435)];
    final result = await converter.transcribe(pianoFixture(reference));
    checkMatched(reference, result.notes, onsetToleranceMs: 120,
        offsetToleranceMs: 150);
    final empty = await converter.transcribe(DecodedAudioFile(
        name: 'silence', samples: Float32List(48000),
        sampleRate: 48000));
    expect(empty.notes, isEmpty);
  });

  test('quiet note accepted only when sensitivity is increased', () async {
    final reference = [event(69, 200, 980)];
    final file = pianoFixture(reference, gain: 0.010);
    final standard = await converter.transcribe(file);
    final sensitive = await converter.transcribe(file,
      preferences: const DetectionPreferences(increasedSensitivity: true));
    expect(standard.notes, isEmpty);
    expect(sensitive.notes.any((n) => n.midiNote == 69), isTrue);
  });

  test('fast mode also supports simultaneous notes and progress', () async {
    final progress = <double>[];
    final result = await converter.transcribe(
      pianoFixture([event(48, 100, 1000), event(72, 100, 1000)]),
      mode: Mp3TranscriptionMode.fast,
      onProgress: progress.add,
    );
    expect(result.notes.map((n) => n.midiNote).toSet(),
        containsAll(<int>[48, 72]));
    expect(progress.last, 1);
  });

  test('MIDI export/import preserves overlapping pitches and times',
      () async {
    final input = [event(43, 200, 1050), event(71, 200, 1050),
        event(64, 450, 900)];
    final result = await converter.transcribe(pianoFixture(input));
    checkMatched(input, result.notes);
    final midi = const MidiParser().parse(
        const MidiRecordingWriter().write(result.notes));
    expect(midi.format, 0);
    expect(midi.tracks, hasLength(1));
    final imported = midi.tracks.single.notes;
    expect(imported.length, result.notes.length);
    for (var i = 0; i < imported.length; i++) {
      expect(imported[i].midiNote, result.notes[i].midiNote);
      expect(closeTo(imported[i].start, result.notes[i].start, 2), isTrue);
      expect(closeTo(imported[i].duration, result.notes[i].duration, 2),
          isTrue);
    }
    expect(imported.where((n) => n.midiNote == 43), isNotEmpty);
    expect(imported.where((n) => n.midiNote == 71), isNotEmpty);
  });
}
