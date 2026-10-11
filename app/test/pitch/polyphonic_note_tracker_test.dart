import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/polyphonic_note_tracker.dart';

void main() {
  test('two simultaneous acoustic tones generate separate stable onsets', () {
    const sampleRate = 48000;
    const totalSamples = sampleRate * 2;
    final samples = Float32List(totalSamples);
    for (var i = 0; i < totalSamples; i++) {
      final time = i / sampleRate;
      if (time < 0.25 || time > 1.10) continue;
      final attack = math.min(1.0, (time - 0.25) / 0.015);
      final release = math.min(1.0, (1.10 - time) / 0.02);
      for (final midi in <int>[60, 64]) {
        final frequency = 440 * math.pow(2, (midi - 69) / 12);
        samples[i] += 0.20 * attack * release *
            math.sin(2 * math.pi * frequency * (time - 0.25));
      }
    }

    final tracker = PolyphonicNoteTracker();
    final events = <NoteEvent>[];
    for (var start = 0; start < samples.length; start += 2048) {
      final end = math.min(start + 2048, samples.length);
      final packet = Float32List.sublistView(samples, start, end);
      final time = Duration(
        microseconds: ((end / sampleRate) * 1000000).round(),
      );
      events.addAll(tracker.observe(packet, sampleRate, time));
    }

    final onsets = events
        .where((e) => e.type == NoteEventType.noteOn)
        .map((e) => e.midiNote)
        .toSet();
    final releases = events
        .where((e) => e.type == NoteEventType.noteOff)
        .map((e) => e.midiNote)
        .toSet();
    expect(onsets, containsAll(<int>[60, 64]));
    expect(releases, containsAll(<int>[60, 64]));
    expect(tracker.activeNotes, isEmpty);
  });

  test('reset discards buffered samples and previously held notes', () {
    final tracker = PolyphonicNoteTracker();
    final data = Float32List(2048);
    expect(
      tracker.observe(data, 48000, const Duration(milliseconds: 44)),
      isEmpty,
    );
    tracker.reset();
    expect(tracker.activeNotes, isEmpty);
    expect(
      tracker.observe(data, 48000, const Duration(milliseconds: 88)),
      isEmpty,
    );
  });
}
