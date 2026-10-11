import 'midi_parser.dart';

/// A single (track, channel) candidate for melodic or chord practice.
///
/// Channel selection matters for SMF type 0 and type 1 tracks that contain
/// several instruments. Notes from different tracks are never merged.
class MelodyPart {
  const MelodyPart({
    required this.trackIndex,
    required this.trackName,
    required this.channel,
    required this.notes,
    required this.overlapCount,
    required this.minMidiNote,
    required this.maxMidiNote,
    required this.start,
    required this.duration,
  });

  final int trackIndex;
  final String? trackName;

  /// MIDI channels are zero-based. Channel 9 is percussion.
  final int channel;
  final List<MidiNote> notes;
  final int overlapCount;
  final int minMidiNote;
  final int maxMidiNote;
  final Duration start;
  final Duration duration;

  bool get isPercussion => channel == 9;
  bool get isMonophonic => overlapCount == 0;
  // Two overlapping copies of the *same pitch* cannot be separately
  // represented by real pressed-key state; do not silently count both.
  bool get hasUnplayableRepeat {
    final lastEndByPitch = <int, int>{};
    for (final note in notes) {
      final previousEnd = lastEndByPitch[note.midiNote] ?? -1;
      if (previousEnd > note.startTick) return true;
      if (note.endTick > previousEnd) {
        lastEndByPitch[note.midiNote] = note.endTick;
      }
    }
    return false;
  }

  bool get canPractice =>
      !isPercussion && notes.isNotEmpty && !hasUnplayableRepeat;

  String get displayName => trackName?.trim().isNotEmpty == true
      ? trackName!.trim()
      : 'Ścieżka ${trackIndex + 1}';
}

class MelodySelection {
  const MelodySelection(this.part);

  final MelodyPart part;

  /// Chronologically sorted, immutable notes for future Wait for Note logic.
  List<MidiNote> get notes => part.notes;
}

/// Validates each MIDI track/channel separately. Works without Flutter/Web.
class MelodyPartAnalyzer {
  const MelodyPartAnalyzer();

  List<MelodyPart> analyze(MidiFile midi) {
    final candidates = <MelodyPart>[];
    for (final track in midi.tracks) {
      final channels = <int, List<MidiNote>>{};
      for (final note in track.notes) {
        (channels[note.channel] ??= []).add(note);
      }
      final sortedChannels = channels.keys.toList()..sort();
      for (final channel in sortedChannels) {
        final notes = List<MidiNote>.of(channels[channel]!);
        notes.sort((a, b) {
          final byStart = a.startTick.compareTo(b.startTick);
          if (byStart != 0) return byStart;
          final byEnd = a.endTick.compareTo(b.endTick);
          if (byEnd != 0) return byEnd;
          return a.midiNote.compareTo(b.midiNote);
        });

        var overlapCount = 0;
        var lastStartTick = -1;
        var latestEndTick = -1;
        var firstPitch = 127;
        var lastPitch = 0;
        var latestTime = Duration.zero;

        for (final note in notes) {
          // Equal note-ons are simultaneous even if either note is zero-length.
          if (note.startTick == lastStartTick ||
              note.startTick < latestEndTick) {
            overlapCount++;
          }
          lastStartTick = note.startTick;
          if (note.endTick > latestEndTick) {
            latestEndTick = note.endTick;
          }
          if (note.midiNote < firstPitch) firstPitch = note.midiNote;
          if (note.midiNote > lastPitch) lastPitch = note.midiNote;
          final end = note.start + note.duration;
          if (end > latestTime) latestTime = end;
        }

        final firstTime = notes.first.start;
        candidates.add(
          MelodyPart(
            trackIndex: track.index,
            trackName: track.name,
            channel: channel,
            notes: List.unmodifiable(notes),
            overlapCount: overlapCount,
            minMidiNote: firstPitch,
            maxMidiNote: lastPitch,
            start: firstTime,
            duration: latestTime - firstTime,
          ),
        );
      }
    }
    return List.unmodifiable(candidates);
  }

  /// Returns null only for missing, empty, or percussion candidates.
  MelodySelection? select(
    List<MelodyPart> parts, {
    required int trackIndex,
    required int channel,
  }) {
    for (final part in parts) {
      if (part.trackIndex == trackIndex && part.channel == channel) {
        return part.canPractice ? MelodySelection(part) : null;
      }
    }
    return null;
  }
}
