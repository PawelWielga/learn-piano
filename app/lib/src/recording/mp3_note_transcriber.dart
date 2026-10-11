import 'dart:math' as math;
import 'dart:typed_data';

import '../audio/audio_file_picker.dart';
import '../pitch/detection_preferences.dart';
import 'note_recorder.dart';
import 'polyphonic_frame_analyzer.dart';

enum Mp3TranscriptionMode { fast, accurate }

/// Local polyphonic file transcription. Microphone YIN and NoteEventTracker are
/// intentionally NOT used or changed: those still implement Wait for Note.
class Mp3NoteTranscriber {
  const Mp3NoteTranscriber();

  Future<Mp3Transcription> transcribe(
    DecodedAudioFile audio, {
    DetectionPreferences preferences = const DetectionPreferences(),
    Mp3TranscriptionMode mode = Mp3TranscriptionMode.accurate,
    bool Function()? isCancelled,
    void Function(double)? onProgress,
  }) async {
    final sampleRate = audio.sampleRate;
    if (sampleRate < 8000 ||
        sampleRate > 96000 ||
        audio.samples.length < 1024 ||
        audio.duration > const Duration(seconds: 90)) {
      throw const FormatException('Nieobsługiwany czas lub próbkowanie MP3.');
    }

    final analyzer = PolyphonicFrameAnalyzer(
      sampleRate,
      sensitivity: mode == Mp3TranscriptionMode.accurate ? 0.17 : 0.24,
      maxVoices: mode == Mp3TranscriptionMode.accurate ? 8 : 5,
    );
    // 23ms (accurate) / 46ms (fast), instead of the previous 130ms.
    final hop = math.max(
      1,
      (sampleRate * (mode == Mp3TranscriptionMode.accurate ? 0.023 : 0.046))
          .round(),
    );
    final gate = preferences.minimumRms;
    final noteFloor = preferences.increasedSensitivity ? 0.003 : 0.006;
    final attack = mode == Mp3TranscriptionMode.accurate
        ? const Duration(milliseconds: 20)
        : Duration.zero;
    const release = Duration(milliseconds: 75);
    // Reject FFT transients (often a semitone below long bass notes). A
    // legitimate 85ms staccato note must still survive accurate mode.
    final minNoteDuration = mode == Mp3TranscriptionMode.accurate
        ? const Duration(milliseconds: 70)
        : const Duration(milliseconds: 85);
    const minRetrigger = Duration(milliseconds: 110);
    const maxNotes = 8192;
    final tracks = List<_FileNoteState>.generate(
      analyzer.maxMidi - analyzer.minMidi + 1,
      (_) => _FileNoteState(),
    );
    final notes = <RecordedNote>[];
    final rmsHalfWindow = math.max(1, (sampleRate * 0.011).round());
    final lastCenter = audio.samples.length - 1;
    var truncated = false;

    Duration timeAt(int center) =>
        Duration(microseconds: (center * 1000000 / sampleRate).round());

    void close(int pitch, _FileNoteState state, Duration end) {
      final start = state.started;
      if (start != null && notes.length < maxNotes) {
        final clipped = end > audio.duration ? audio.duration : end;
        if (clipped - start >= minNoteDuration) {
          notes.add(
            RecordedNote(
              midiNote: pitch,
              start: start,
              duration: clipped - start,
            ),
          );
        }
      }
      state.started = null;
      state.tentative = null;
      state.lastHeard = null;
    }

    for (var center = 0; center <= lastCenter; center += hop) {
      if (isCancelled?.call() ?? false) {
        throw const Mp3TranscriptionCancelled();
      }
      final at = timeAt(center);
      // A short energy gate avoids the long FFT window smearing onsets,
      // and keeps the microphone's sensitivity setting meaningful for MP3.
      var energy = 0.0;
      var count = 0;
      final from = math.max(0, center - rmsHalfWindow);
      final to = math.min(audio.samples.length, center + rmsHalfWindow);
      for (var i = from; i < to; i += 2) {
        final sample = audio.samples[i];
        if (!sample.isFinite) {
          throw const FormatException('Niepoprawne próbki audio.');
        }
        energy += sample * sample;
        count++;
      }
      final audible = count > 0 && math.sqrt(energy / count) >= gate;
      final levels = audible
          ? analyzer.analyze(audio.samples, center)
          : Float64List(tracks.length);

      for (var i = 0; i < tracks.length; i++) {
        final state = tracks[i];
        final level = levels[i];
        final present = audible && level >= noteFloor;
        if (present) {
          state.tentative ??= at;
          if (state.started == null && at - state.tentative! >= attack) {
            state.started = state.tentative;
          }
          if (state.started != null) {
            final sinceOnset = at - state.started!;
            // A new attack of an already ringing pitch can indicate a repeat.
            // Avoid triggering on the initial envelope's natural growth.
            if (sinceOnset >= minRetrigger &&
                state.previousLevel > noteFloor &&
                level > state.previousLevel * 1.85 &&
                level - state.previousLevel > 0.015) {
              close(analyzer.minMidi + i, state, at);
              state.started = at;
              state.tentative = at;
            }
            state.lastHeard = at;
          }
          state.previousLevel = level;
        } else {
          state.tentative = null;
          if (state.started != null &&
              state.lastHeard != null &&
              at - state.lastHeard! >= release) {
            close(
              analyzer.minMidi + i,
              state,
              state.lastHeard! +
                  Duration(microseconds: (hop * 500000 / sampleRate).round()),
            );
          }
          // Retain a small amount of envelope history for re-articulation;
          // never keep an old spike through a real silent passage.
          state.previousLevel *= 0.5;
        }
      }
      if (notes.length >= maxNotes) {
        truncated = true;
        break;
      }
      if (center ~/ hop % 6 == 0) {
        onProgress?.call((center / lastCenter).clamp(0.0, 1.0));
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (isCancelled?.call() ?? false) {
      throw const Mp3TranscriptionCancelled();
    }
    for (var i = 0; i < tracks.length; i++) {
      final state = tracks[i];
      if (state.started != null && notes.length < maxNotes) {
        close(analyzer.minMidi + i, state, audio.duration);
      }
    }
    notes.sort((a, b) {
      final byStart = a.start.compareTo(b.start);
      return byStart != 0 ? byStart : a.midiNote.compareTo(b.midiNote);
    });
    onProgress?.call(1);
    return Mp3Transcription(
      notes: List.unmodifiable(notes),
      duration: audio.duration,
      truncated: truncated,
    );
  }
}

class _FileNoteState {
  Duration? tentative;
  Duration? started;
  Duration? lastHeard;
  double previousLevel = 0;
}

class Mp3Transcription {
  const Mp3Transcription({
    required this.notes,
    required this.duration,
    required this.truncated,
  });

  final List<RecordedNote> notes;
  final Duration duration;
  final bool truncated;
  bool get polyphonic => true;
}

class Mp3TranscriptionCancelled implements Exception {
  const Mp3TranscriptionCancelled();
}
