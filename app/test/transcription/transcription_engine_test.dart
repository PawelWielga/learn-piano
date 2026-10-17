import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/recording/midi_recording_writer.dart';
import 'package:learn_piano/src/transcription/legacy_dsp_transcription_engine.dart';
import 'package:learn_piano/src/transcription/transcription_engine.dart';

TranscribedNote note(
  int pitch,
  int fromMs,
  int toMs, {
  double? confidence,
  List<NotePitchBend> bends = const [],
}) => TranscribedNote(
  midiNote: pitch,
  start: Duration(milliseconds: fromMs),
  end: Duration(milliseconds: toMs),
  confidence: confidence,
  pitchBends: bends,
);

TranscriptionResult result(List<TranscribedNote> notes) => TranscriptionResult(
  engineId: 'fake-model-v1',
  duration: const Duration(seconds: 2),
  notes: notes,
);

void main() {
  test('normalizes simultaneous notes and round-trips through MIDI', () {
    final input = result([
      note(72, 400, 1200, confidence: 0.8),
      note(60, 200, 1000, confidence: 0.6),
      note(64, 200, 900),
      note(60, 1200, 1500),
    ]);
    final normalized = input.toRecordedNotes();
    expect(normalized.map((n) => n.midiNote), [60, 64, 72, 60]);
    expect(normalized[0].start, normalized[1].start);
    expect(normalized[0].duration, const Duration(milliseconds: 800));
    expect(
      () => normalized.add(normalized.first),
      throwsUnsupportedError,
    );

    final midi = const MidiParser().parse(
      const MidiRecordingWriter().write(normalized),
    );
    expect(midi.noteCount, 4);
    final notes = midi.tracks.single.notes;
    expect(notes.map((n) => n.midiNote), [60, 64, 72, 60]);
    expect(
      (notes[0].start - normalized[0].start).inMilliseconds.abs(),
      lessThanOrEqualTo(2),
    );
  });

  test('rejects invalid model data before MIDI export', () {
    final invalid = [
      note(-1, 100, 200),
      note(128, 100, 200),
      note(60, -10, 200),
      note(60, 200, 100),
      note(60, 200, 200),
      note(60, 100, 2400),
      note(60, 100, 200, confidence: double.nan),
      note(60, 100, 200, confidence: -0.1),
      note(60, 100, 200, confidence: 1.1),
      note(60, 100, 200, bends: [
        const NotePitchBend(at: Duration(milliseconds: 120), cents: 20),
      ]),
      note(60, 100, 200, bends: [
        const NotePitchBend(at: Duration.zero, cents: double.infinity),
      ]),
    ];
    for (final bad in invalid) {
      expect(
        () => result([bad]).toRecordedNotes(),
        throwsFormatException,
      );
    }
    expect(
      () => const TranscriptionResult(
        engineId: '',
        duration: Duration(seconds: 1),
        notes: [],
      ).toRecordedNotes(),
      throwsFormatException,
    );
    expect(
      () => const TranscriptionResult(
        engineId: 'fake',
        duration: Duration(microseconds: -1),
        notes: [],
      ).toRecordedNotes(),
      throwsFormatException,
    );
  });

  test('keeps pitch bends as normalized metadata, not invented confidence', () {
    final bend = note(
      69,
      100,
      500,
      bends: [
        const NotePitchBend(at: Duration.zero, cents: -15),
        const NotePitchBend(at: Duration(milliseconds: 300), cents: 20),
      ],
    );
    final output = result([bend]);
    expect(output.hasPitchBends, isTrue);
    expect(output.notes.single.confidence, isNull);
    expect(output.toRecordedNotes().single.midiNote, 69);
  });

  test('legacy adapter preserves DSP output without calibration claims', () async {
    const rate = 24000;
    final audio = DecodedAudioFile(
      name: 'silence.wav',
      samples: Float32List(rate),
      sampleRate: rate,
    );
    const engine = LegacyDspTranscriptionEngine();
    final progress = <double>[];
    final outcome = await engine.transcribe(audio, onProgress: progress.add);
    expect(outcome.engineId, engine.engineId);
    expect(outcome.notes, isEmpty);
    expect(outcome.toRecordedNotes(), isEmpty);
    expect(outcome.limitations, isNotEmpty);
    expect(progress.last, 1);
    expect(
      () => outcome.notes.add(note(60, 1, 2)),
      throwsUnsupportedError,
    );
  });

  test('legacy adapter translates cancellation to the common exception', () async {
    final audio = DecodedAudioFile(
      name: 'cancel.wav',
      samples: Float32List(24000),
      sampleRate: 24000,
    );
    await expectLater(
      const LegacyDspTranscriptionEngine().transcribe(
        audio,
        isCancelled: () => true,
      ),
      throwsA(isA<TranscriptionCancelled>()),
    );
  });
}
