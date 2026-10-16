import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/audio/audio_input.dart';
import 'package:learn_piano/src/instrument/instrument_range.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/pitch_detector.dart';
import 'package:learn_piano/src/pitch/polyphonic_note_tracker.dart';
import 'package:learn_piano/src/training/wait_for_note_engine.dart';

import '../midi/midi_fixtures.dart';

const rates = [44100, 48000];
Duration ms(int value) => Duration(milliseconds: value);

/// Original generated tones, not recordings or external music.
class TestTone {
  const TestTone(
    this.pitch,
    this.startMs,
    this.endMs, {
    this.gain = 0.25,
    this.second = 0,
    this.third = 0,
    this.cents = 0,
  });

  final int pitch;
  final int startMs;
  final int endMs;
  final double gain;
  final double second;
  final double third;
  final double cents;
}

/// Deterministic AudioWorklet-like packets with monotonic audio-clock time.
List<PcmFrame> packets(
  int sampleRate,
  int totalMs,
  List<TestTone> tones, {
  double noise = 0,
}) {
  final length = (sampleRate * totalMs / 1000).round();
  final signal = Float32List(length);
  for (final note in tones) {
    final first = (sampleRate * note.startMs / 1000).round();
    final last = math.min(length, (sampleRate * note.endMs / 1000).round());
    final frequency =
        440 * math.pow(2, (note.pitch - 69 + note.cents / 100) / 12);
    for (var i = first; i < last; i++) {
      final local = i - first;
      final phase = 2 * math.pi * frequency * local / sampleRate;
      final release = math.min(1.0, (last - i) / (sampleRate * 0.015));
      signal[i] +=
          note.gain *
          release *
          (math.sin(phase) +
              note.second * math.sin(2 * phase) +
              note.third * math.sin(3 * phase));
    }
  }
  if (noise > 0) {
    var seed = 31;
    for (var i = 0; i < signal.length; i++) {
      seed = (1664525 * seed + 1013904223) & 0xFFFFFFFF;
      signal[i] += noise * (2 * seed / 4294967295 - 1);
    }
  }
  final frames = <PcmFrame>[];
  for (var i = 0; i < length; i += 2048) {
    final end = math.min(length, i + 2048);
    final samples = Float32List(2048);
    samples.setRange(0, end - i, signal, i);
    frames.add(
      PcmFrame(
        samples: samples,
        sampleRate: sampleRate,
        capturedAt: Duration(
          microseconds: (end * 1000000 / sampleRate).round(),
        ),
      ),
    );
  }
  return frames;
}

/// Same 120ms cadence as mono training. Real detector and tracker.
List<NoteEvent> mono(List<PcmFrame> frames, {NoteEventTracker? tracker}) {
  const detector = PitchDetector();
  final state = tracker ?? NoteEventTracker();
  final events = <NoteEvent>[];
  Duration? last;
  for (final packet in frames) {
    if (last != null && packet.capturedAt - last < ms(120)) continue;
    last = packet.capturedAt;
    events.addAll(
      state
          .observe(
            detector.detect(packet.samples, packet.sampleRate),
            packet.capturedAt,
          )
          .events,
    );
  }
  return events;
}

List<NoteEvent> poly(List<PcmFrame> frames) {
  final tracker = PolyphonicNoteTracker();
  final events = <NoteEvent>[];
  for (final frame in frames) {
    events.addAll(
      tracker.observe(frame.samples, frame.sampleRate, frame.capturedAt),
    );
  }
  expect(tracker.activeNotes, isEmpty);
  return events;
}

List<NoteEvent> onsets(List<NoteEvent> events) =>
    events.where((event) => event.type == NoteEventType.noteOn).toList();

void main() {
  test(
    'PCM replay supplies 2048 packets and monotonic 44.1/48k timestamps',
    () {
      for (final rate in rates) {
        final frames = packets(rate, 1000, []);
        for (var i = 0; i < frames.length; i++) {
          expect(frames[i].samples.length, 2048);
          expect(frames[i].sampleRate, rate);
          if (i > 0) {
            expect(frames[i].capturedAt, greaterThan(frames[i - 1].capturedAt));
          }
        }
        expect(
          (frames.last.capturedAt.inMicroseconds - 1000000).abs(),
          lessThan(30),
        );
      }
    },
  );

  test('YIN detects each C2-C6 semitone at both microphone sample rates', () {
    const detector = PitchDetector();
    for (final rate in rates) {
      for (var pitch = 36; pitch <= 84; pitch++) {
        final frame = packets(rate, 150, [TestTone(pitch, 0, 150)]).first;
        final candidate = detector.detect(frame.samples, rate);
        expect(
          candidate?.midiNote,
          pitch,
          reason: 'pitch $pitch at $rate',
        );
      }
    }
  });

  test(
    'C2 and neighboring bass pitches resist strong overtone octave errors',
    () {
      const detector = PitchDetector();
      for (final rate in rates) {
        for (final pitch in [36, 37, 40, 41, 48]) {
          final frame = packets(rate, 150, [
            TestTone(pitch, 0, 150, gain: 0.12, second: 4.58, third: 2.17),
          ]).first;
          expect(detector.detect(frame.samples, rate)?.midiNote, pitch);
        }
      }
    },
  );

  test('silence and deterministic weak noise cannot trigger NoteOn', () {
    for (final rate in rates) {
      for (final noise in [0.0, 0.003]) {
        expect(onsets(mono(packets(rate, 1800, [], noise: noise))), isEmpty);
      }
    }
  });

  test(
    'sustained detuned C2 has one onset, one release and bounded latency',
    () {
      for (final rate in rates) {
        for (final cents in [-30.0, 0.0, 30.0]) {
          final events = mono(
            packets(rate, 2500, [
              TestTone(36, 420, 1780, cents: cents),
            ], noise: 0.001),
          );
          expect(onsets(events).map((e) => e.midiNote), [36]);
          expect(
            events.where((e) => e.type == NoteEventType.noteOff),
            hasLength(1),
          );
          final delay = (onsets(events).single.at - ms(420)).inMilliseconds;
          expect(delay, inInclusiveRange(200, 650));
          // ignore: avoid_print
          print('C2 rate=$rate cents=$cents onsetLatencyMs=$delay');
        }
      }
    },
  );

  test('WaitForNote rejects held C4; advances on three distinct strikes', () {
    final midi = const MidiParser().parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x90, 60, 100]),
            event(480, [0x80, 60, 0]),
            event(480, [0x90, 60, 100]),
            event(480, [0x80, 60, 0]),
            event(480, [0x90, 60, 100]),
            event(480, [0x80, 60, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final selection = MelodySelection(
      const MelodyPartAnalyzer().analyze(midi).single,
    );
    for (final rate in rates) {
      WaitForNoteEngine engine() => WaitForNoteEngine(
        selection,
        instrumentRange: const InstrumentRange(36, 84),
      )..start();

      final held = mono(packets(rate, 2500, [const TestTone(60, 350, 1850)]));
      final heldEngine = engine();
      for (final event in held) {
        heldEngine.onNoteEvent(event);
      }
      expect(onsets(held), hasLength(1));
      expect(heldEngine.snapshot.currentIndex, 1);
      expect(heldEngine.snapshot.isCompleted, isFalse);

      final events = mono(
        packets(rate, 5200, [
          const TestTone(60, 400, 1250),
          const TestTone(60, 1850, 2700),
          const TestTone(60, 3300, 4150),
        ]),
      );
      final session = engine();
      var correct = 0;
      for (final event in events) {
        if (session.onNoteEvent(event).attempt == TrainingAttempt.correct) {
          correct++;
        }
      }
      expect(onsets(events).map((e) => e.midiNote), [60, 60, 60]);
      expect(correct, 3);
      expect(session.snapshot.isCompleted, isTrue);
    }
  });

  test('octave jump generates two real onsets, without extra notes', () {
    for (final rate in rates) {
      final events = mono(
        packets(rate, 3000, [
          const TestTone(48, 350, 1200),
          const TestTone(60, 1600, 2500),
        ]),
      );
      expect(onsets(events).map((e) => e.midiNote), [48, 60]);
    }
  });

  test('interrupted session reset allows new first note, no stale state', () {
    for (final rate in rates) {
      final frames = packets(rate, 1700, [const TestTone(69, 200, 1200)]);
      final tracker = NoteEventTracker();
      expect(onsets(mono(frames, tracker: tracker)).map((e) => e.midiNote), [
        69,
      ]);
      tracker.reset();
      expect(onsets(mono(frames, tracker: tracker)).map((e) => e.midiNote), [
        69,
      ]);
    }
  });

  test('2-4 voices with louder bass are reported and checked', () {
    for (final voices in [2, 3, 4]) {
      final pitches = <int>[48, 60, 64, 67].take(voices).toList();
      final events = poly(
        packets(48000, 2600, [
          for (final pitch in pitches)
            TestTone(
              pitch,
              400,
              1750,
              gain: pitch == 48 ? 0.23 : 0.12,
              second: 0.08,
            ),
        ]),
      );
      final detected = onsets(events).map((e) => e.midiNote).toSet();
      final missed = pitches.toSet().difference(detected);
      final ghosts = detected.difference(pitches.toSet());
      // ignore: avoid_print
      print('Poly voices=$voices detected=$detected missing=$missed ghost=$ghosts');
      expect(missed, isEmpty);
      expect(ghosts.length, lessThanOrEqualTo(2));
    }
  });

  test('polyphonic 44.1k dyad releases both acoustic pitches', () {
    final events = poly(
      packets(44100, 2600, [
        const TestTone(60, 400, 1650, gain: 0.18),
        const TestTone(64, 400, 1650, gain: 0.18),
      ]),
    );
    expect(
      onsets(events).map((e) => e.midiNote).toSet(),
      containsAll([60, 64]),
    );
    expect(
      events
          .where((e) => e.type == NoteEventType.noteOff)
          .map((e) => e.midiNote)
          .toSet(),
      containsAll([60, 64]),
    );
  });
}
