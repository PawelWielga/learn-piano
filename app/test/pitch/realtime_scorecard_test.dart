import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/pitch/note_event_tracker.dart';
import 'package:learn_piano/src/pitch/realtime_note_detector.dart';

import '../../tool/note_matching.dart' as matching;
import 'realtime_pcm_replay_test.dart' as fixtures;

class _Scenario {
  const _Scenario(this.name, this.source, this.rate, this.tones, {this.lengthMs = 2600});
  final String name;
  final RealtimeDetectorSource source;
  final int rate;
  final List<fixtures.TestTone> tones;
  final int lengthMs;
}

const _scenarios = <_Scenario>[
  _Scenario('mono_c2_44100', RealtimeDetectorSource.yin, 44100,
    [fixtures.TestTone(36, 400, 1550)]),
  _Scenario('mono_c2_48000', RealtimeDetectorSource.yin, 48000,
    [fixtures.TestTone(36, 400, 1550)]),
  _Scenario('mono_c6_48000', RealtimeDetectorSource.yin, 48000,
    [fixtures.TestTone(84, 400, 1550)]),
  _Scenario('mono_repeated_c4', RealtimeDetectorSource.yin, 48000, [
    fixtures.TestTone(60, 400, 1100),
    fixtures.TestTone(60, 1550, 2250),
  ], lengthMs: 3100),
  _Scenario('mono_silence', RealtimeDetectorSource.yin, 48000, []),
  _Scenario('poly_dyad_44100', RealtimeDetectorSource.legacyPolyphonicFft,
    44100, [fixtures.TestTone(60, 400, 1650),
    fixtures.TestTone(64, 400, 1650)]),
  _Scenario('poly_bass_dyad_48000', RealtimeDetectorSource.legacyPolyphonicFft,
    48000, [fixtures.TestTone(48, 400, 1750, gain: 0.23, second: 0.08),
    fixtures.TestTone(62, 400, 1750, gain: 0.12, second: 0.08)]),
  _Scenario('poly_triad_48000', RealtimeDetectorSource.legacyPolyphonicFft,
    48000, [fixtures.TestTone(48, 400, 1750, gain: 0.23, second: 0.08),
    fixtures.TestTone(62, 400, 1750, gain: 0.12, second: 0.08),
    fixtures.TestTone(65, 400, 1750, gain: 0.12, second: 0.08)]),
  _Scenario('poly_four_48000', RealtimeDetectorSource.legacyPolyphonicFft,
    48000, [fixtures.TestTone(48, 400, 1750, gain: 0.23, second: 0.08),
    fixtures.TestTone(62, 400, 1750, gain: 0.12, second: 0.08),
    fixtures.TestTone(65, 400, 1750, gain: 0.12, second: 0.08),
    fixtures.TestTone(69, 400, 1750, gain: 0.12, second: 0.08)]),
  _Scenario('poly_octave_overlap_48000',
    RealtimeDetectorSource.legacyPolyphonicFft, 48000,
    [fixtures.TestTone(48, 400, 1750, gain: 0.23, second: 0.08),
    fixtures.TestTone(60, 400, 1750, gain: 0.12, second: 0.08)]),
];

List<matching.BenchmarkNote> _eventsToNotes(
    List<NoteEvent> events, int lastAtUs) {
  final active = <int, int>{};
  final notes = <matching.BenchmarkNote>[];
  for (final event in events) {
    final microseconds = event.at.inMicroseconds;
    if (event.type == NoteEventType.noteOn) {
      // Do not collapse a duplicated onset into a false perfect match:
      // previous ongoing key remains a separate event in the scorecard.
      final prior = active[event.midiNote];
      if (prior != null) {
        notes.add(matching.BenchmarkNote(
          pitch: event.midiNote, onsetUs: prior, offsetUs: microseconds));
      }
      active[event.midiNote] = microseconds;
    } else {
      final start = active.remove(event.midiNote);
      if (start != null) {
        notes.add(matching.BenchmarkNote(
          pitch: event.midiNote, onsetUs: start, offsetUs: microseconds));
      }
    }
  }
  for (final entry in active.entries) {
    notes.add(matching.BenchmarkNote(
      pitch: entry.key, onsetUs: entry.value, offsetUs: lastAtUs));
  }
  return notes;
}

Map<String, Object?> _run(_Scenario scenario) {
  final frames = fixtures.packets(
    scenario.rate, scenario.lengthMs, scenario.tones,
  );
  final detector = scenario.source == RealtimeDetectorSource.yin
      ? YinRealtimeDetector()
      : FftRealtimeDetector();
  final events = <NoteEvent>[];
  final beforeRss = ProcessInfo.currentRss;
  final watch = Stopwatch()..start();
  for (final frame in frames) {
    events.addAll(detector.observe(frame).events);
  }
  watch.stop();
  final rssAfter = ProcessInfo.currentRss;
  final expected = scenario.tones.map((tone) =>
    matching.BenchmarkNote(pitch: tone.pitch,
      onsetUs: tone.startMs * 1000, offsetUs: tone.endMs * 1000),
  ).toList();
  final detected = _eventsToNotes(
    events, scenario.lengthMs * 1000,
  );
  // Stable onset state machines impose >200ms of detector latency.
  // Compare policies use 650ms onset / 700ms offset. This is NOT the
  // stricter offline transcription tolerance from issue #56.
  final comparison = matching.compareNotes(
    expected, detected,
    onsetToleranceUs: 650000,
    offsetToleranceUs: 700000,
  );
  final misses = comparison.falseNegativeNotes.map((n) => n.pitch).toList();
  final ghosts = comparison.falsePositiveNotes.map((n) => n.pitch).toList();
  return {
    'name': scenario.name,
    'source': scenario.source.name,
    'sampleRate': scenario.rate,
    'windowLengthSamples': 2048,
    'expectedPitches': expected.map((n) => n.pitch).toList(),
    'detectedPitches': detected.map((n) => n.pitch).toList(),
    'missedPitches': misses,
    'ghostPitches': ghosts,
    'onset': comparison.onset.toJson(),
    'strict': comparison.strict.toJson(),
    'octaveConfusions': comparison.octaveConfusions,
    'algorithmicLatencyMs': [
      for (final p in comparison.onset.pairs)
        p.onsetErrorUs / 1000,
    ],
    'processedPackets': frames.length,
    'computeWallMs': watch.elapsedMicroseconds / 1000,
    'computePerPacketMs': watch.elapsedMicroseconds / 1000 / frames.length,
    'processRssStartBytes': beforeRss,
    'processRssEndBytes': rssAfter,
    'processRssDeltaBytes': rssAfter - beforeRss,
    'limitation': scenario.source == RealtimeDetectorSource.yin
        ? 'YIN periodicity score is not a calibrated probability.'
        : 'FFT per-key confidence is unavailable; no model tested.',
  };
}

void main() {
  test('deterministic synthetic realtime scorecard, no fake model results', () {
    final results = <Map<String, Object?>>[];
    for (final scenario in _scenarios) {
      final result = _run(scenario);
      results.add(result);
      final score = result['onset']! as Map<String, Object>;
      // ignore: avoid_print
      print('REALTIME ${scenario.name}'
        ' TP=${score['matched']}'
        ' FP=${score['falsePositives']}'
        ' FN=${score['falseNegatives']}'
        ' computeMs=${result['computeWallMs']}');
    }
    expect(results.length, _scenarios.length);
    final silent = results.firstWhere((r) => r['name'] == 'mono_silence');
    expect((silent['onset'] as Map<String, Object>)['falsePositives'], 0);
    final c3c4 = results.firstWhere((r) =>
      r['name'] == 'poly_octave_overlap_48000');
    expect((c3c4['missedPitches'] as List<int>), contains(60));

    // An optional CI-only JSON artifact. No PCM is serialized.
    final target = Platform.environment['REALTIME_SCORECARD_JSON'];
    if (target != null && target.isNotEmpty) {
      final path = File(target);
      path.parent.createSync(recursive: true);
      path.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'scope': 'Synthetic PCM only, no physical piano or Android device',
          'modelStatus': 'Not evaluated (no verified weights/runtime)',
          'onsetToleranceMs': 650,
          'offsetToleranceMs': 700,
          'computeTiming': 'Stopwatch VM wall time for detector.observe only',
          'memoryTiming': 'Process RSS before/after each case, NOT peak heap',
          'cases': results,
        }) + '\n',
      );
    }
  });
}
