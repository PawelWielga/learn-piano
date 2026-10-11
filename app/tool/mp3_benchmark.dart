import 'dart:io';
import 'dart:typed_data';

import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/recording/mp3_note_transcriber.dart';
import 'package:learn_piano/src/recording/note_recorder.dart';

/// Offline benchmark for the *real* Mp3NoteTranscriber.
///
/// Pass an 80-second, mono, 24000 Hz little-endian float32 PCM file produced
/// by ffmpeg, and the reference MIDI. Only the first audio-window notes are
/// evaluated; this is a diagnostic measurement, not a passing CI assertion.
Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/mp3_benchmark.dart '
      '<audio-24000hz-mono.f32> <reference.mid>',
    );
    exitCode = 64;
    return;
  }

  try {
    final bytes = await File(arguments[0]).readAsBytes();
    if (bytes.isEmpty || bytes.lengthInBytes % 4 != 0) {
      throw const FormatException('Invalid little-endian float32 PCM data.');
    }
    final view = ByteData.sublistView(bytes);
    final samples = Float32List(bytes.lengthInBytes ~/ 4);
    for (var i = 0; i < samples.length; i++) {
      samples[i] = view.getFloat32(i * 4, Endian.little);
    }

    final audio = DecodedAudioFile(
      name: 'benchmark.pcm',
      samples: samples,
      sampleRate: 24000,
    );
    if (audio.duration > const Duration(seconds: 90)) {
      throw const FormatException(
        'Benchmark audio must be at most 90 seconds.',
      );
    }

    final midi = const MidiParser().parse(
      await File(arguments[1]).readAsBytes(),
    );
    final transcription = await const Mp3NoteTranscriber().transcribe(
      audio,
      mode: Mp3TranscriptionMode.accurate,
    );

    // Discard notes cut short at the audio boundary from both sets. Never
    // score the rest of a 5-minute reference against an 80-second excerpt.
    final cutoff = audio.duration - const Duration(milliseconds: 350);
    final expected = midi.tracks
        .expand((track) => track.notes)
        .where(
          (note) =>
              note.start + note.duration <= cutoff &&
              note.channel != 9,
        )
        .toList();
    final actual = transcription.notes
        .where((note) => note.start + note.duration <= cutoff)
        .toList();

    final onset = _match(
      expected,
      actual,
      onsetTolerance: const Duration(milliseconds: 130),
    );
    final strict = _match(
      expected,
      actual,
      onsetTolerance: const Duration(milliseconds: 130),
      offsetTolerance: const Duration(milliseconds: 160),
    );

    stdout.writeln('MP3 → MIDI benchmark (diagnostic; no pass threshold)');
    stdout.writeln('Audio window: ${audio.duration.inMilliseconds} ms');
    stdout.writeln('Reference MIDI: ${midi.noteCount} total notes, '
        '${midi.duration.inMilliseconds} ms');
    stdout.writeln('Reference notes in window: ${expected.length}');
    stdout.writeln('Detected notes in window: ${actual.length}');
    _report('Exact pitch + onset (±130ms)', onset);
    _report('Exact pitch + onset (±130ms) + offset (±160ms)', strict);
    stdout.writeln('NOTE: Metrics assume source.mp3 and reference.mid have '
        'the same arrangement, timing and start position. Unverified '
        'alignment or a melody-only MIDI can make these scores misleading.');
    if (transcription.truncated) {
      stdout.writeln('WARNING: transcription hit its note limit.');
    }
  } catch (error) {
    stderr.writeln('Benchmark failed: $error');
    exitCode = 1;
  }
}

({int matched, int expected, int actual}) _match(
  List<MidiNote> reference,
  List<RecordedNote> detected, {
  required Duration onsetTolerance,
  Duration? offsetTolerance,
}) {
  final matchedIndices = <int>{};
  var hits = 0;
  for (final target in reference) {
    var nearestIndex = -1;
    var nearestError = onsetTolerance.inMicroseconds + 1;
    for (var i = 0; i < detected.length; i++) {
      if (matchedIndices.contains(i)) continue;
      final candidate = detected[i];
      if (candidate.midiNote != target.midiNote) continue;
      final onsetError = (candidate.start - target.start).inMicroseconds.abs();
      if (onsetError > onsetTolerance.inMicroseconds) continue;
      if (offsetTolerance != null) {
        final actualEnd = candidate.start + candidate.duration;
        final referenceEnd = target.start + target.duration;
        final offsetError = (actualEnd - referenceEnd).inMicroseconds.abs();
        if (offsetError > offsetTolerance.inMicroseconds) continue;
      }
      if (onsetError < nearestError) {
        nearestError = onsetError;
        nearestIndex = i;
      }
    }
    if (nearestIndex >= 0) {
      matchedIndices.add(nearestIndex);
      hits++;
    }
  }
  return (matched: hits, expected: reference.length, actual: detected.length);
}

void _report(
  String label,
  ({int matched, int expected, int actual}) result,
) {
  final precision = result.actual == 0
      ? (result.expected == 0 ? 1.0 : 0.0)
      : result.matched / result.actual;
  final recall = result.expected == 0
      ? 1.0
      : result.matched / result.expected;
  final denominator = precision + recall;
  final f1 = denominator == 0 ? 0.0 : 2 * precision * recall / denominator;
  stdout.writeln(
    '$label: matched ${result.matched}, '
    'precision ${precision.toStringAsFixed(3)}, '
    'recall ${recall.toStringAsFixed(3)}, '
    'F1 ${f1.toStringAsFixed(3)}',
  );
}
