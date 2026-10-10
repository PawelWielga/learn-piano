import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/pitch/pitch_detector.dart';

Float32List tone(
  double frequencyHz, {
  int sampleRate = 48000,
  int length = 2048,
  double gain = 0.35,
  double secondHarmonic = 0,
  double thirdHarmonic = 0,
}) {
  return Float32List.fromList(
    List<double>.generate(length, (index) {
      final phase = 2 * math.pi * frequencyHz * index / sampleRate;
      return gain * math.sin(phase) +
          secondHarmonic * math.sin(2 * phase) +
          thirdHarmonic * math.sin(3 * phase);
    }),
  );
}

void main() {
  const detector = PitchDetector();

  test('recognizes MIDI pitch and octave at 44.1 and 48 kHz', () {
    for (final sampleRate in [44100, 48000]) {
      final expected = <int, double>{
        36: 65.4064, // C2 - lowest supported instrument note
        37: 69.2957, // C#2
        38: 73.4162, // D2
        39: 77.7817, // D#2
        40: 82.4069, // E2
        41: 87.3071, // F2
        42: 92.4986, // F#2
        45: 110.0, // A2
        48: 130.8128, // C3
        60: 261.6256, // C4
        61: 277.1826, // C#4
        69: 440.0, // A4
        79: 783.9909, // G5
        84: 1046.5023, // C6
      };
      for (final entry in expected.entries) {
        final result = detector.detect(
          tone(entry.value, sampleRate: sampleRate),
          sampleRate,
        );
        expect(result, isNotNull, reason: '${entry.key} at $sampleRate Hz');
        expect(result!.midiNote, entry.key);
        expect(result.frequencyHz, closeTo(entry.value, entry.value * 0.005));
        expect(result.confidence, greaterThan(0.93));
      }
    }
  });

  test('names notes using MIDI 60 = C4 convention', () {
    final c4 = detector.detect(tone(261.6256), 48000)!;
    expect(c4.noteName, 'C4');
    expect(c4.centsFromNote.abs(), lessThan(5));

    final sharp = detector.detect(tone(277.1826), 48000)!;
    expect(sharp.noteName, 'C#4');
    expect(detector.detect(tone(440), 48000)!.noteName, 'A4');
  });

  test('handles piano timbre with strong overtones', () {
    final result = detector.detect(
      tone(220, gain: 0.12, secondHarmonic: 0.55, thirdHarmonic: 0.26),
      48000,
    );
    expect(result, isNotNull);
    expect(result!.midiNote, 57); // A3, not A4/A5.
    expect(result.frequencyHz, closeTo(220, 1));
  });

  test('C2 through F2 survive piano-style overtones at both sample rates', () {
    for (final sampleRate in [44100, 48000]) {
      for (final midiNote in [36, 37, 38, 39, 40, 41]) {
        final frequency = 440 * math.pow(2, (midiNote - 69) / 12);
        final result = detector.detect(
          tone(
            frequency.toDouble(),
            sampleRate: sampleRate,
            gain: 0.12,
            secondHarmonic: 0.55,
            thirdHarmonic: 0.26,
          ),
          sampleRate,
        );
        expect(
          result,
          isNotNull,
          reason: 'Missing low piano note $midiNote at $sampleRate Hz',
        );
        expect(result!.midiNote, midiNote);
        expect(result.frequencyHz, closeTo(frequency, frequency * 0.005));
      }
    }
  });

  test('rejects silence, very quiet sound and short buffers', () {
    expect(detector.detect(Float32List(2048), 48000), isNull);
    expect(detector.detect(tone(440, gain: 0.001), 48000), isNull);
    expect(detector.detect(tone(440, length: 256), 48000), isNull);
  });

  test('rejects unsupported ranges and invalid samples', () {
    expect(detector.detect(tone(55), 48000), isNull);
    expect(detector.detect(tone(58.2705), 48000), isNull);
    expect(detector.detect(tone(440), 0), isNull);
    final corrupt = tone(440)..[8] = double.nan;
    expect(detector.detect(corrupt, 48000), isNull);
  });

  test('rejects broadband noise', () {
    final random = math.Random(31);
    final noise = Float32List.fromList(
      List<double>.generate(2048, (_) => random.nextDouble() - 0.5),
    );
    expect(detector.detect(noise, 48000), isNull);
  });

  test('rejects closely competing pitches rather than inventing a note', () {
    final first = tone(440, gain: 0.35);
    final second = tone(493.8833, gain: 0.35);
    final mixed = Float32List.fromList(
      List<double>.generate(2048, (i) => first[i] + second[i]),
    );
    expect(detector.detect(mixed, 48000), isNull);
  });

  test('thresholds can be configured for a quieter instrument', () {
    const quietDetector = PitchDetector(minRms: 0.0001);
    expect(quietDetector.detect(tone(440, gain: 0.002), 48000)?.midiNote, 69);
  });
}
