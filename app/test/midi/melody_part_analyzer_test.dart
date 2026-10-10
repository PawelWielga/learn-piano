import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/midi/melody_part_analyzer.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';

import 'midi_fixtures.dart';

void main() {
  const parser = MidiParser();
  const analyzer = MelodyPartAnalyzer();

  test(
    'type 1: recognizes separate melodic tracks and ignores empty track',
    () {
      final midi = parser.parse(
        midiFixture(
          format: 1,
          tracks: [
            trackBytes([trackName('Metadata'), endOfTrack()]),
            trackBytes([
              trackName('Lead'),
              event(0, [0x90, 60, 100]),
              event(480, [0x80, 60, 0]),
              event(240, [0x90, 64, 100]),
              event(240, [0x80, 64, 0]),
              endOfTrack(),
            ]),
            trackBytes([
              trackName('Bass'),
              event(0, [0x90, 48, 100]),
              event(960, [0x80, 48, 0]),
              endOfTrack(),
            ]),
          ],
        ),
      );
      final parts = analyzer.analyze(midi);
      expect(parts, hasLength(2));
      final lead = analyzer.select(parts, trackIndex: 1, channel: 0);
      expect(lead, isNotNull);
      expect(lead!.notes.map((n) => n.midiNote), [60, 64]);
      expect(lead.part.trackName, 'Lead');
      expect(lead.part.start, Duration.zero);
      expect(lead.part.duration, const Duration(seconds: 1));
      expect(lead.part.minMidiNote, 60);
      expect(lead.part.maxMidiNote, 64);
      expect(lead.part.overlapCount, 0);
      expect(analyzer.select(parts, trackIndex: 0, channel: 0), isNull);
      expect(analyzer.select(parts, trackIndex: 2, channel: 0), isNotNull);
    },
  );

  test('type 0: channel separation avoids false polyphony', () {
    final midi = parser.parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x90, 60, 80]),
            event(0, [0x91, 48, 80]),
            event(480, [0x80, 60, 0]),
            event(0, [0x81, 48, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final parts = analyzer.analyze(midi);
    expect(parts.map((p) => p.channel), [0, 1]);
    expect(parts.every((p) => p.canPractice), isTrue);
    expect(parts.every((p) => p.overlapCount == 0), isTrue);
    expect(
      analyzer.select(parts, trackIndex: 0, channel: 1)!.notes.single.midiNote,
      48,
    );
  });

  test('simultaneous notes are chords even with zero-length first note', () {
    final midi = parser.parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x90, 60, 90]),
            event(0, [0x80, 60, 0]),
            event(0, [0x90, 64, 90]),
            event(0, [0x90, 67, 90]),
            event(120, [0x80, 64, 0]),
            event(0, [0x80, 67, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final parts = analyzer.analyze(midi);
    expect(parts.single.isMonophonic, isFalse);
    expect(parts.single.overlapCount, 2);
    expect(parts.single.canPractice, isFalse);
    expect(analyzer.select(parts, trackIndex: 0, channel: 0), isNull);
  });

  test('overlapping notes on same pitch are rejected', () {
    final midi = parser.parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x90, 60, 100]),
            event(120, [0x90, 60, 90]),
            event(120, [0x80, 60, 0]),
            event(120, [0x80, 60, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final part = analyzer.analyze(midi).single;
    expect(part.overlapCount, 1);
    expect(part.canPractice, isFalse);
  });

  test('adjacent notes and rhythmic rests stay monophonic', () {
    final midi = parser.parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x90, 60, 100]),
            event(120, [0x80, 60, 0]),
            event(0, [0x90, 60, 100]),
            event(120, [0x80, 60, 0]),
            event(480, [0x90, 62, 100]),
            event(240, [0x80, 62, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final part = analyzer.analyze(midi).single;
    expect(part.isMonophonic, isTrue);
    expect(part.canPractice, isTrue);
    expect(part.notes.map((n) => n.startTick), [0, 120, 720]);
    expect(part.duration, const Duration(milliseconds: 1000));
  });

  test('percussion channel 10 cannot be selected, melody channel can', () {
    final midi = parser.parse(
      midiFixture(
        format: 0,
        tracks: [
          trackBytes([
            event(0, [0x99, 36, 100]),
            event(0, [0x90, 60, 80]),
            event(480, [0x89, 36, 0]),
            event(0, [0x80, 60, 0]),
            endOfTrack(),
          ]),
        ],
      ),
    );
    final parts = analyzer.analyze(midi);
    expect(parts, hasLength(2));
    expect(parts.first.canPractice, isTrue);
    expect(parts.last.channel, 9);
    expect(parts.last.isPercussion, isTrue);
    expect(parts.last.canPractice, isFalse);
    expect(analyzer.select(parts, trackIndex: 0, channel: 9), isNull);
    expect(analyzer.select(parts, trackIndex: 0, channel: 0), isNotNull);
  });

  test('entirely empty file has no selectable parts', () {
    final midi = parser.parse(
      midiFixture(
        format: 1,
        tracks: [
          trackBytes([trackName('Header'), endOfTrack()]),
          trackBytes([endOfTrack()]),
        ],
      ),
    );
    final parts = analyzer.analyze(midi);
    expect(parts, isEmpty);
    expect(analyzer.select(parts, trackIndex: 0, channel: 0), isNull);
  });
}
