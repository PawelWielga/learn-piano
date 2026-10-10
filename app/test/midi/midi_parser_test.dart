import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_piano/src/midi/midi_parser.dart';

import 'midi_fixtures.dart';

void main() {
  const parser = MidiParser();

  test('type 0: converts note-on/off, velocity and pause to real time', () {
    final file = parser.parse(midiFixture(format: 0, tracks: [
      trackBytes([
        trackName('Piano'),
        event(0, [0x90, 60, 99]),
        event(480, [0x80, 60, 0]),
        event(240, [0x90, 62, 80]),
        event(240, [0x90, 62, 0]),
        endOfTrack(),
      ]),
    ]));

    expect(file.format, 0);
    expect(file.ticksPerQuarterNote, 480);
    expect(file.tracks, hasLength(1));
    expect(file.tracks.single.name, 'Piano');
    expect(file.noteCount, 2);
    final notes = file.tracks.single.notes;
    expect(notes.map((n) => n.midiNote), [60, 62]);
    expect(notes.first.channel, 0);
    expect(notes.first.velocity, 99);
    expect(notes.first.start, Duration.zero);
    expect(notes.first.duration, const Duration(milliseconds: 500));
    expect(notes.last.start, const Duration(milliseconds: 750));
    expect(notes.last.duration, const Duration(milliseconds: 250));
    expect(file.duration, const Duration(seconds: 1));
  });

  test('type 1: global tempo map applies across tracks and note spans', () {
    final file = parser.parse(midiFixture(format: 1, tracks: [
      trackBytes([
        tempo(0, 500000),
        tempo(480, 1000000),
        endOfTrack(960),
      ]),
      trackBytes([
        trackName('Melody'),
        event(0, [0x90, 60, 90]),
        event(960, [0x80, 60, 0]),
        event(0, [0x90, 64, 100]),
        event(480, [0x80, 64, 0]),
        endOfTrack(),
      ]),
    ]));

    expect(file.format, 1);
    expect(file.tracks, hasLength(2));
    expect(file.tracks.first.notes, isEmpty);
    expect(file.tempoChanges, hasLength(2));
    expect(file.tempoChanges.last.tick, 480);
    expect(file.tempoChanges.last.at, const Duration(milliseconds: 500));
    final notes = file.tracks.last.notes;
    expect(notes.first.duration, const Duration(milliseconds: 1500));
    expect(notes.last.start, const Duration(milliseconds: 1500));
    expect(notes.last.duration, const Duration(seconds: 1));
    expect(file.duration, const Duration(milliseconds: 2500));
  });

  test('supports running status, program change, SysEx and multi-channel notes', () {
    final file = parser.parse(midiFixture(format: 0, tracks: [
      trackBytes([
        event(0, [0xC0, 5]),
        event(0, [0xF0, 2, 0x7D, 0x00]),
        event(0, [0x90, 60, 75]),
        event(0, [60, 0]),
        event(0, [0x91, 60, 88]),
        event(240, [60, 0]),
        endOfTrack(),
      ]),
    ]));
    expect(file.noteCount, 2);
    expect(file.tracks.single.notes.map((n) => n.channel), [0, 1]);
    expect(file.tracks.single.notes.first.duration, Duration.zero);
    expect(file.tracks.single.notes.last.duration,
        const Duration(milliseconds: 250));
  });

  test('overlapping identical notes use FIFO note-off pairing', () {
    final file = parser.parse(midiFixture(format: 0, tracks: [
      trackBytes([
        event(0, [0x90, 60, 90]),
        event(120, [0x90, 60, 91]),
        event(120, [0x80, 60, 0]),
        event(120, [0x80, 60, 0]),
        endOfTrack(),
      ]),
    ]));
    final notes = file.tracks.single.notes;
    expect(notes, hasLength(2));
    expect(notes.first.startTick, 0);
    expect(notes.first.endTick, 240);
    expect(notes.last.startTick, 120);
    expect(notes.last.endTick, 360);
  });

  test('uses default 120 BPM and honors non-default PPQ', () {
    final file = parser.parse(midiFixture(format: 0, ppq: 96, tracks: [
      trackBytes([
        event(0, [0x90, 69, 75]),
        event(96, [0x80, 69, 0]),
        endOfTrack(96),
      ]),
    ]));
    expect(file.tempoChanges, isEmpty);
    expect(file.tracks.single.notes.single.duration,
        const Duration(milliseconds: 500));
    expect(file.duration, const Duration(seconds: 1));
  });

  test('tempo at the same tick uses the final event deterministically', () {
    final file = parser.parse(midiFixture(format: 1, tracks: [
      trackBytes([tempo(0, 600000), tempo(0, 1000000), endOfTrack()]),
      trackBytes([
        event(0, [0x90, 60, 100]),
        event(480, [0x80, 60, 0]),
        endOfTrack(),
      ]),
    ]));
    expect(file.tempoChanges, hasLength(1));
    expect(file.tempoChanges.single.microsecondsPerBeat, 1000000);
    expect(file.tracks.last.notes.single.duration, const Duration(seconds: 1));
  });

  test('truncated and unsupported data fails with controlled errors', () {
    final valid = midiFixture(format: 0, tracks: [
      trackBytes([event(0, [0x90, 60, 90]), event(480, [0x80, 60, 0]), endOfTrack()]),
    ]);
    final truncated = Uint8List.sublistView(valid, 0, valid.length - 2);
    expect(() => parser.parse(truncated), throwsA(isA<MidiFormatException>()));
    expect(() => parser.parse(Uint8List(0)),
        throwsA(isA<MidiFormatException>()));

    expect(() => parser.parse(midiFixture(format: 2, tracks: [
      trackBytes([endOfTrack()]),
    ])), throwsA(isA<MidiFormatException>()));
    expect(() => parser.parse(midiFixture(format: 0, ppq: 0xE728, tracks: [
      trackBytes([endOfTrack()]),
    ])), throwsA(isA<MidiFormatException>()));
    expect(() => parser.parse(midiFixture(format: 0, tracks: [
      trackBytes([event(0, [0x90, 60, 90]), endOfTrack()]),
    ])), throwsA(isA<MidiFormatException>()));
    expect(() => parser.parse(midiFixture(format: 0, tracks: [
      trackBytes([event(0, [0xFF, 0x51, 2, 0, 100]), endOfTrack()]),
    ])), throwsA(isA<MidiFormatException>()));
    expect(() => const MidiParser(maxBytes: 20).parse(valid),
        throwsA(isA<MidiFormatException>()));
  });

  test('rejects malformed running status, data bytes and VLQ', () {
    for (final invalidTrack in [
      trackBytes([event(0, [60, 64]), endOfTrack()]),
      trackBytes([event(0, [0x90, 60, 0x90]), endOfTrack()]),
      trackBytes([event(0, [0xF1, 0x01]), endOfTrack()]),
      trackBytes([[0x81, 0x81, 0x81, 0x81, 0x00]]),
    ]) {
      final midi = midiFixture(format: 0, tracks: [invalidTrack]);
      expect(() => parser.parse(midi), throwsA(isA<MidiFormatException>()));
    }
  });
}
