import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_file_picker.dart';
import 'package:learn_piano/src/recording/anti_alias_decimator.dart';
import 'package:learn_piano/src/recording/mp3_note_transcriber.dart';
import 'package:learn_piano/src/recording/note_recorder.dart';

Float32List sine(int sampleRate, double hertz, {double seconds = 0.2}) {
  final length = (seconds * sampleRate).round();
  return Float32List.fromList(
    List<double>.generate(
      length,
      (i) => 0.6 * math.sin(2 * math.pi * hertz * i / sampleRate),
    ),
  );
}

double rms(Float32List samples, {int trim = 128}) {
  var sum = 0.0;
  final count = samples.length - 2 * trim;
  for (var i = trim; i < samples.length - trim; i++) {
    sum += samples[i] * samples[i];
  }
  return math.sqrt(sum / count);
}

RecordedNote note(int pitch, int startMs, int endMs) => RecordedNote(
  midiNote: pitch,
  start: Duration(milliseconds: startMs),
  duration: Duration(milliseconds: endMs - startMs),
);

DecodedAudioFile harmonicFixture(int rate, List<RecordedNote> notes) {
  final samples = Float32List((rate * 1.7).round());
  for (final note in notes) {
    final start = (note.start.inMicroseconds * rate / 1e6).round();
    final stop = ((note.start + note.duration).inMicroseconds * rate / 1e6)
        .round();
    final hertz = 440 * math.pow(2, (note.midiNote - 69) / 12);
    for (var i = start; i < stop; i++) {
      final elapsed = (i - start) / rate;
      final remaining = (stop - i) / rate;
      final envelope = math.min(1.0, math.min(elapsed / 0.012, remaining / 0.018));
      final phase = 2 * math.pi * hertz * elapsed;
      samples[i] += 0.25 * envelope *
          (math.sin(phase) + 0.18 * math.sin(2 * phase) +
              0.08 * math.sin(3 * phase));
    }
  }
  return DecodedAudioFile(name: 'synthetic.wav', samples: samples, sampleRate: rate);
}

void main() {
  for (final rate in <int>[44100, 48000]) {
    test('downsampling at $rate Hz suppresses folded high-frequency aliases', () {
      // Above the new Nyquist frequency; naive stride-2 would fold it down.
      final input = sine(rate, rate == 44100 ? 15000 : 16000);
      final naive = Float32List.fromList(
        List<double>.generate(
          AntiAliasDecimator.outputLength(input.length),
          (i) => input[2 * i],
        ),
      );
      final filtered = AntiAliasDecimator.decimate(input);
      final unfilteredRms = rms(naive);
      final filteredRms = rms(filtered);
      expect(unfilteredRms, greaterThan(0.40));
      expect(
        filteredRms / unfilteredRms,
        lessThan(0.02),
        reason: 'Aliases must be attenuated by more than 34 dB.',
      );
    });

    test('downsampling at $rate Hz preserves piano frequencies', () {
      for (final hz in <double>[65.406, 261.626, 1046.502, 2093.005]) {
        final input = sine(rate, hz);
        final output = AntiAliasDecimator.decimate(input);
        expect(
          rms(output) / rms(input),
          closeTo(1, 0.03),
          reason: 'Unexpected passband loss at $hz Hz',
        );
      }
    });

    test('MP3 analyzer at $rate Hz detects C2 and C6 with harmonics', () async {
      final reference = [note(36, 150, 740), note(84, 940, 1460)];
      final result = await const Mp3NoteTranscriber().transcribe(
        harmonicFixture(rate, reference),
      );
      for (final expected in reference) {
        expect(
          result.notes.any(
            (actual) => actual.midiNote == expected.midiNote &&
                (actual.start - expected.start).inMilliseconds.abs() <= 130 &&
                ((actual.start + actual.duration) -
                        (expected.start + expected.duration))
                    .inMilliseconds.abs() <= 160,
          ),
          isTrue,
          reason: 'Missing MIDI ${expected.midiNote} at $rate Hz',
        );
      }
    });
  }

  test('chunked decimation matches a single pass and does not modify PCM', () {
    final input = sine(48000, 440, seconds: 0.21);
    final original = Float32List.fromList(input);
    final expected = AntiAliasDecimator.decimate(input);
    final chunked = Float32List(AntiAliasDecimator.outputLength(input.length));
    for (var from = 0; from < chunked.length; from += 997) {
      AntiAliasDecimator.processRange(
        input, chunked, from, math.min(chunked.length, from + 997),
      );
    }
    expect(chunked, orderedEquals(expected));
    expect(input, orderedEquals(original));
    expect(
      () => AntiAliasDecimator.processRange(input, chunked, 2, chunked.length + 1),
      throwsRangeError,
    );
  });
}
