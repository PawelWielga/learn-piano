import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/pitch/detection_preferences.dart';
import 'package:learn_piano/src/recording/midi_recording_writer.dart';
import 'package:learn_piano/src/recording/mp3_note_transcriber.dart';

DecodedAudioFile melody({int sampleRate = 48000, double gain = 0.35}) {
  // Two monophonic notes separated by a real silence.
  final samples = Float32List(sampleRate * 3);
  for (var i = 0; i < sampleRate; i++) {
    samples[i] = gain * math.sin(2 * math.pi * 440 * i / sampleRate);
  }
  for (var i = sampleRate * 3 ~/ 2; i < sampleRate * 5 ~/ 2; i++) {
    final local = i - sampleRate * 3 ~/ 2;
    samples[i] = gain * math.sin(2 * math.pi * 261.6256 * local / sampleRate);
  }
  return DecodedAudioFile(
    name: 'piano.mp3',
    samples: samples,
    sampleRate: sampleRate,
  );
}

void main() {
  test('extracts monophonic notes at real PCM sample rates and exports MIDI', () async {
    for (final sampleRate in [44100, 48000]) {
      final progress = <double>[];
      final result = await const Mp3NoteTranscriber().transcribe(
        melody(sampleRate: sampleRate),
        onProgress: progress.add,
      );
      expect(result.notes.map((note) => note.midiNote).toList(), [69, 60]);
      expect(result.notes.first.duration, greaterThan(const Duration(milliseconds: 500)));
      expect(result.notes.last.start, greaterThan(const Duration(milliseconds: 1300)));
      expect(progress.last, 1);
      expect(result.truncated, isFalse);
      final midi = const MidiParser().parse(
        const MidiRecordingWriter().write(result.notes),
      );
      expect(midi.noteCount, 2);
      expect(midi.tracks.single.notes.map((n) => n.midiNote).toList(), [69, 60]);
    }
  });

  test('quiet recording requires sensitivity switch', () async {
    final normal = await const Mp3NoteTranscriber().transcribe(
      melody(gain: 0.01),
    );
    final sensitive = await const Mp3NoteTranscriber().transcribe(
      melody(gain: 0.01),
      preferences: const DetectionPreferences(increasedSensitivity: true),
    );
    expect(normal.notes, isEmpty);
    expect(sensitive.notes.map((n) => n.midiNote), [69, 60]);
  });

  test('silence creates no phantom notes', () async {
    final result = await const Mp3NoteTranscriber().transcribe(
      DecodedAudioFile(
        name: 'silent.mp3',
        samples: Float32List(48000),
        sampleRate: 48000,
      ),
    );
    expect(result.notes, isEmpty);
  });

  test('rejects invalid PCM and honors cancellation', () async {
    await expectLater(
      const Mp3NoteTranscriber().transcribe(
        DecodedAudioFile(
          name: 'invalid.mp3',
          samples: Float32List(128),
          sampleRate: 48000,
        ),
      ),
      throwsFormatException,
    );

    var cancel = false;
    await expectLater(
      const Mp3NoteTranscriber().transcribe(
        melody(),
        isCancelled: () => cancel,
        onProgress: (_) => cancel = true,
      ),
      throwsA(isA<Mp3TranscriptionCancelled>()),
    );
  });
}
