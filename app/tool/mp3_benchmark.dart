import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/recording/mp3_note_transcriber.dart';

import 'note_matching.dart';

/// Runs the real transcriber against a time-aligned 24kHz mono PCM/MIDI pair.
///
/// Unverified pairs must not be used to make quality claims. The CI runner
/// validates synchronized fixtures against generator manifest SHA-256 hashes.
Future<void> main(List<String> arguments) async {
  if (arguments.length < 2) {
    _usage();
    return;
  }
  final audioPath = arguments[0];
  final referencePath = arguments[1];
  var requireFullReference = false;
  String? outputPath;

  for (var i = 2; i < arguments.length; i++) {
    switch (arguments[i]) {
      case '--require-full-reference':
        requireFullReference = true;
      case '--json-output':
        if (i + 1 >= arguments.length || outputPath != null) {
          _usage();
          return;
        }
        outputPath = arguments[++i];
      default:
        _usage();
        return;
    }
  }

  try {
    final bytes = await File(audioPath).readAsBytes();
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
      await File(referencePath).readAsBytes(),
    );
    final reference = midi.tracks
        .expand((track) => track.notes)
        .where((note) => note.channel != 9)
        .toList();

    // Trim only genuinely truncated notes. Every generated fixture has
    // 200 ms of trailing silence, so all reference notes must participate.
    final cutoff = audio.duration - const Duration(milliseconds: 50);
    final expected = reference
        .where((note) => note.start + note.duration <= cutoff)
        .map(
          (note) => BenchmarkNote(
            pitch: note.midiNote,
            onsetUs: note.start.inMicroseconds,
            offsetUs: (note.start + note.duration).inMicroseconds,
          ),
        )
        .toList();
    if (expected.isEmpty) {
      throw const FormatException('No reference notes in the audio window.');
    }
    if (requireFullReference && expected.length != reference.length) {
      throw const FormatException(
        'A reference note lies outside the comparable audio window.',
      );
    }

    final transcription = await const Mp3NoteTranscriber().transcribe(
      audio,
      mode: Mp3TranscriptionMode.accurate,
    );
    if (transcription.truncated && requireFullReference) {
      throw const FormatException('Transcription hit its note limit.');
    }
    final actual = transcription.notes
        .where((note) => note.start + note.duration <= cutoff)
        .map(
          (note) => BenchmarkNote(
            pitch: note.midiNote,
            onsetUs: note.start.inMicroseconds,
            offsetUs: (note.start + note.duration).inMicroseconds,
          ),
        )
        .toList();

    final comparison = compareNotes(expected, actual);
    final result = <String, Object>{
      'methodology': 'maximum-cardinality-v1',
      'onsetToleranceMs': 130,
      'offsetToleranceMs': 160,
      'audioWindowMs': audio.duration.inMilliseconds,
      'referenceExcluded': reference.length - expected.length,
      'truncated': transcription.truncated,
      ...comparison.toJson(),
    };
    stdout.writeln('PCM → MIDI benchmark (aligned sources required)');
    stdout.writeln('Reference ${expected.length}, detected ${actual.length}');
    _printScore('Pitch + onset', comparison.onset);
    _printScore('Pitch + onset + offset', comparison.strict);
    stdout.writeln('Octave confusions: ${comparison.octaveConfusions.length}');
    if (outputPath != null) {
      await File(outputPath).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(result)}\n',
      );
    }
  } catch (error) {
    stderr.writeln('Benchmark failed: $error');
    exitCode = 1;
  }
}

void _usage() {
  stderr.writeln(
    'Usage: dart run tool/mp3_benchmark.dart '
    '<mono-24000hz.f32> <aligned-reference.mid> '
    '[--require-full-reference] [--json-output report.json]',
  );
  exitCode = 64;
}

void _printScore(String label, MatchScore score) {
  stdout.writeln(
    '$label: matched ${score.truePositives}, FP ${score.falsePositives}, '
    'FN ${score.falseNegatives}, '
    'precision ${score.precision.toStringAsFixed(3)}, '
    'recall ${score.recall.toStringAsFixed(3)}, '
    'F1 ${score.f1.toStringAsFixed(3)}',
  );
}
