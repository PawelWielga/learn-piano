import 'dart:convert';
import 'dart:typed_data';

import 'note_recorder.dart';

/// Standard MIDI File: type 0, 120 BPM, 480 PPQ. Compatible with MidiParser.
class MidiRecordingWriter {
  const MidiRecordingWriter();

  static const ticksPerBeat = 480;
  static const microsecondsPerBeat = 500000;

  Uint8List write(List<RecordedNote> notes) {
    final events = <_TimedEvent>[];
    for (final note in notes) {
      if (note.midiNote < 0 ||
          note.midiNote > 127 ||
          note.velocity < 1 ||
          note.velocity > 127 ||
          note.start.isNegative ||
          note.duration.isNegative) {
        throw const FormatException('Niepoprawne dane nagranej nuty.');
      }
      final begin = _toTicks(note.start);
      final end = _toTicks(note.start + note.duration);
      events.add(_TimedEvent(begin, 1, [0x90, note.midiNote, note.velocity]));
      events.add(
        _TimedEvent(end > begin ? end : begin + 1, 0, [0x80, note.midiNote, 0]),
      );
    }
    events.sort((a, b) {
      final tick = a.tick.compareTo(b.tick);
      return tick != 0 ? tick : a.priority.compareTo(b.priority);
    });

    final track = <int>[
      0, 0xFF, 0x51, 3, 7, 0xA1, 0x20, // 120 BPM
      0, 0xC0, 0, // Acoustic Grand Piano, channel 1
    ];
    var previousTick = 0;
    for (final event in events) {
      _writeVariableLength(track, event.tick - previousTick);
      track.addAll(event.bytes);
      previousTick = event.tick;
    }
    track.addAll([0, 0xFF, 0x2F, 0]);

    final bytes = <int>[
      ...ascii.encode('MThd'),
      0, 0, 0, 6,
      0, 0, // type 0
      0, 1, // one track
      1, 0xE0, // 480 PPQ
      ...ascii.encode('MTrk'),
    ];
    _writeUint32(bytes, track.length);
    bytes.addAll(track);
    return Uint8List.fromList(bytes);
  }

  int _toTicks(Duration duration) =>
      (duration.inMicroseconds * ticksPerBeat + microsecondsPerBeat ~/ 2) ~/
      microsecondsPerBeat;

  void _writeUint32(List<int> bytes, int value) {
    bytes.addAll([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }

  void _writeVariableLength(List<int> bytes, int value) {
    if (value < 0 || value > 0x0FFFFFFF) {
      throw const FormatException('Nagranie jest za długie dla formatu MIDI.');
    }
    final pending = <int>[value & 0x7F];
    var remaining = value >> 7;
    while (remaining > 0) {
      pending.add((remaining & 0x7F) | 0x80);
      remaining >>= 7;
    }
    bytes.addAll(pending.reversed);
  }
}

class _TimedEvent {
  const _TimedEvent(this.tick, this.priority, this.bytes);
  final int tick;
  final int priority;
  final List<int> bytes;
}
