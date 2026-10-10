import 'dart:convert';
import 'dart:typed_data';

/// An unsupported or structurally invalid Standard MIDI File (SMF).
class MidiFormatException extends FormatException {
  const MidiFormatException(super.message);
}

/// A note with MIDI tick positions and real time derived from the tempo map.
class MidiNote {
  const MidiNote({
    required this.trackIndex,
    required this.channel,
    required this.midiNote,
    required this.velocity,
    required this.startTick,
    required this.endTick,
    required this.start,
    required this.duration,
  });

  final int trackIndex;
  final int channel; // Zero-based MIDI channel (9 = percussion).
  final int midiNote;
  final int velocity;
  final int startTick;
  final int endTick;
  final Duration start;
  final Duration duration;
}

class MidiTrack {
  const MidiTrack({
    required this.index,
    required this.name,
    required this.notes,
    required this.endTick,
  });

  final int index;
  final String? name;
  final List<MidiNote> notes;
  final int endTick;
}

class MidiTempoChange {
  const MidiTempoChange({
    required this.tick,
    required this.microsecondsPerBeat,
    required this.at,
  });

  final int tick;
  final int microsecondsPerBeat;
  final Duration at;
}

class MidiFile {
  const MidiFile({
    required this.format,
    required this.ticksPerQuarterNote,
    required this.tracks,
    required this.tempoChanges,
    required this.duration,
  });

  final int format;
  final int ticksPerQuarterNote;
  final List<MidiTrack> tracks;
  final List<MidiTempoChange> tempoChanges;
  final Duration duration;

  int get noteCount =>
      tracks.fold<int>(0, (count, track) => count + track.notes.length);
}

/// Small, dependency-free SMF type 0/1 parser usable in Flutter Web and tests.
///
/// Audio is never involved; the supplied bytes never leave the calling process.
/// SMPTE timing, type 2 files and unclosed note-on messages are rejected.
class MidiParser {
  const MidiParser({this.maxBytes = 2 * 1024 * 1024});

  final int maxBytes;

  MidiFile parse(Uint8List bytes) {
    if (bytes.length > maxBytes) {
      throw const MidiFormatException('Plik MIDI jest za duży (maks. 2 MB).');
    }
    final reader = _MidiReader(bytes);
    if (reader.readAscii(4) != 'MThd') {
      throw const MidiFormatException('Brak nagłówka MIDI (MThd).');
    }
    final headerLength = reader.readUint32();
    if (headerLength < 6 || headerLength > reader.remaining) {
      throw const MidiFormatException('Niepoprawna długość nagłówka MIDI.');
    }
    final format = reader.readUint16();
    final trackCount = reader.readUint16();
    final division = reader.readUint16();
    reader.skip(headerLength - 6);

    if (format != 0 && format != 1) {
      throw const MidiFormatException(
        'Obsługiwane są tylko pliki MIDI typu 0 i 1.',
      );
    }
    if (trackCount == 0 ||
        trackCount > 64 ||
        (format == 0 && trackCount != 1)) {
      throw const MidiFormatException('Niepoprawna liczba ścieżek MIDI.');
    }
    if (division == 0 || (division & 0x8000) != 0) {
      throw const MidiFormatException(
        'Obsługiwany jest tylko podział czasu PPQ, nie SMPTE.',
      );
    }

    final parsedTracks = <_RawTrack>[];
    final tempos = <_RawTempo>[];
    for (var i = 0; i < trackCount; i++) {
      if (reader.readAscii(4) != 'MTrk') {
        throw const MidiFormatException('Brak nagłówka ścieżki MIDI (MTrk).');
      }
      final trackLength = reader.readUint32();
      final trackReader = _MidiReader(reader.readBytes(trackLength));
      parsedTracks.add(_parseTrack(trackReader, i, tempos));
    }

    final tempoMap = _TempoMap(tempos, division);
    final tracks = <MidiTrack>[];
    var maximumEndTick = 0;
    for (final track in parsedTracks) {
      if (track.endTick > maximumEndTick) maximumEndTick = track.endTick;
      final notes = <MidiNote>[];
      for (final raw in track.notes) {
        final start = tempoMap.timeAt(raw.startTick);
        final end = tempoMap.timeAt(raw.endTick);
        notes.add(
          MidiNote(
            trackIndex: track.index,
            channel: raw.channel,
            midiNote: raw.note,
            velocity: raw.velocity,
            startTick: raw.startTick,
            endTick: raw.endTick,
            start: start,
            duration: end - start,
          ),
        );
      }
      notes.sort((a, b) {
        final byTick = a.startTick.compareTo(b.startTick);
        if (byTick != 0) return byTick;
        final byChannel = a.channel.compareTo(b.channel);
        return byChannel != 0 ? byChannel : a.midiNote.compareTo(b.midiNote);
      });
      tracks.add(
        MidiTrack(
          index: track.index,
          name: track.name,
          notes: List.unmodifiable(notes),
          endTick: track.endTick,
        ),
      );
    }

    return MidiFile(
      format: format,
      ticksPerQuarterNote: division,
      tracks: List.unmodifiable(tracks),
      tempoChanges: List.unmodifiable(tempoMap.changes),
      duration: tempoMap.timeAt(maximumEndTick),
    );
  }

  _RawTrack _parseTrack(_MidiReader reader, int index, List<_RawTempo> tempos) {
    var tick = 0;
    int? runningStatus;
    String? name;
    final notes = <_RawNote>[];
    final active = <int, List<_NoteStart>>{};
    var eventIndex = 0;

    void noteOff(int channel, int pitch) {
      final key = channel * 128 + pitch;
      final starts = active[key];
      if (starts == null || starts.isEmpty) return;
      final start = starts.removeAt(0);
      if (starts.isEmpty) active.remove(key);
      notes.add(
        _RawNote(
          channel: channel,
          note: pitch,
          velocity: start.velocity,
          startTick: start.tick,
          endTick: tick,
        ),
      );
    }

    while (reader.remaining > 0) {
      final delta = reader.readVariableLength();
      tick += delta;
      if (tick > 0x1FFFFFFFFFFFFF) {
        throw const MidiFormatException('Zbyt długi czas ścieżki MIDI.');
      }
      final first = reader.readByte();
      final status = first >= 0x80 ? first : runningStatus;
      if (status == null) {
        throw const MidiFormatException('Brak statusu zdarzenia MIDI.');
      }
      if (status >= 0x80 && status <= 0xEF) {
        if (first >= 0x80) runningStatus = status;
        final type = status & 0xF0;
        final channel = status & 0x0F;
        final data1 = first < 0x80 ? first : reader.readDataByte();
        final data2 = type == 0xC0 || type == 0xD0
            ? null
            : reader.readDataByte();
        if (data1 >= 0x80) {
          throw const MidiFormatException('Niepoprawne dane zdarzenia MIDI.');
        }
        if (type == 0x90 && data2! > 0) {
          final key = channel * 128 + data1;
          (active[key] ??= []).add(_NoteStart(tick, data2));
        } else if (type == 0x80 || (type == 0x90 && data2 == 0)) {
          noteOff(channel, data1);
        }
      } else if (status == 0xFF && first == 0xFF) {
        runningStatus = null;
        final metaType = reader.readByte();
        final length = reader.readVariableLength();
        final payload = reader.readBytes(length);
        if (metaType == 0x03 && name == null) {
          name = utf8.decode(payload, allowMalformed: true).trim();
        } else if (metaType == 0x51) {
          if (length != 3) {
            throw const MidiFormatException(
              'Niepoprawne zdarzenie tempa MIDI.',
            );
          }
          final tempo = (payload[0] << 16) | (payload[1] << 8) | payload[2];
          if (tempo == 0) {
            throw const MidiFormatException(
              'Tempo MIDI nie może wynosić zero.',
            );
          }
          tempos.add(_RawTempo(tick, tempo, index, eventIndex));
        } else if (metaType == 0x2F) {
          if (length != 0) {
            throw const MidiFormatException('Niepoprawny koniec ścieżki MIDI.');
          }
          break;
        }
      } else if ((status == 0xF0 || status == 0xF7) && first == status) {
        runningStatus = null;
        reader.skip(reader.readVariableLength());
      } else {
        throw const MidiFormatException(
          'Nieobsługiwany status zdarzenia MIDI.',
        );
      }
      eventIndex++;
    }

    if (active.isNotEmpty) {
      throw const MidiFormatException('Plik zawiera nuty bez zdarzeń NoteOff.');
    }
    return _RawTrack(index, name, notes, tick);
  }
}

class _NoteStart {
  const _NoteStart(this.tick, this.velocity);
  final int tick;
  final int velocity;
}

class _RawNote {
  const _RawNote({
    required this.channel,
    required this.note,
    required this.velocity,
    required this.startTick,
    required this.endTick,
  });
  final int channel;
  final int note;
  final int velocity;
  final int startTick;
  final int endTick;
}

class _RawTrack {
  const _RawTrack(this.index, this.name, this.notes, this.endTick);
  final int index;
  final String? name;
  final List<_RawNote> notes;
  final int endTick;
}

class _RawTempo {
  const _RawTempo(this.tick, this.usPerBeat, this.track, this.order);
  final int tick;
  final int usPerBeat;
  final int track;
  final int order;
}

class _TempoPoint {
  const _TempoPoint(this.tick, this.micros, this.tempo);
  final int tick;
  final double micros;
  final int tempo;
}

class _TempoMap {
  _TempoMap(List<_RawTempo> raw, this.ppq) {
    raw.sort((a, b) {
      final tickOrder = a.tick.compareTo(b.tick);
      if (tickOrder != 0) return tickOrder;
      final trackOrder = a.track.compareTo(b.track);
      return trackOrder != 0 ? trackOrder : a.order.compareTo(b.order);
    });
    var currentTick = 0;
    var micros = 0.0;
    var currentTempo = 500000;
    final normalized = <MidiTempoChange>[];
    for (final event in raw) {
      micros += (event.tick - currentTick) * currentTempo / ppq;
      currentTick = event.tick;
      currentTempo = event.usPerBeat;
      if (_points.last.tick == event.tick) {
        _points.removeLast();
      }
      _points.add(_TempoPoint(event.tick, micros, currentTempo));
      final change = MidiTempoChange(
        tick: currentTick,
        microsecondsPerBeat: currentTempo,
        at: Duration(microseconds: micros.round()),
      );
      if (normalized.isNotEmpty && normalized.last.tick == currentTick) {
        normalized.removeLast();
      }
      normalized.add(change);
    }
    changes = normalized;
  }

  final int ppq;
  final List<_TempoPoint> _points = [_TempoPoint(0, 0, 500000)];
  late final List<MidiTempoChange> changes;

  Duration timeAt(int tick) {
    var low = 0;
    var high = _points.length - 1;
    while (low < high) {
      final middle = (low + high + 1) ~/ 2;
      if (_points[middle].tick <= tick) {
        low = middle;
      } else {
        high = middle - 1;
      }
    }
    final point = _points[low];
    final micros = point.micros + (tick - point.tick) * point.tempo / ppq;
    return Duration(microseconds: micros.round());
  }
}

class _MidiReader {
  _MidiReader(this.bytes);

  final Uint8List bytes;
  int offset = 0;
  int get remaining => bytes.length - offset;

  int readByte() {
    if (remaining < 1) throw const MidiFormatException('Ucięty plik MIDI.');
    return bytes[offset++];
  }

  int readDataByte() {
    final value = readByte();
    if (value >= 0x80) {
      throw const MidiFormatException('Niepoprawny bajt danych MIDI.');
    }
    return value;
  }

  int readUint16() => (readByte() << 8) | readByte();

  int readUint32() =>
      (readByte() << 24) | (readByte() << 16) | (readByte() << 8) | readByte();

  String readAscii(int length) => String.fromCharCodes(readBytes(length));

  Uint8List readBytes(int length) {
    if (length < 0 || length > remaining) {
      throw const MidiFormatException('Ucięty lub niepoprawny plik MIDI.');
    }
    final result = Uint8List.sublistView(bytes, offset, offset + length);
    offset += length;
    return result;
  }

  void skip(int length) {
    readBytes(length);
  }

  int readVariableLength() {
    var value = 0;
    for (var i = 0; i < 4; i++) {
      final byte = readByte();
      value = (value << 7) | (byte & 0x7F);
      if ((byte & 0x80) == 0) return value;
    }
    throw const MidiFormatException(
      'Niepoprawna liczba zmiennej długości MIDI.',
    );
  }
}
