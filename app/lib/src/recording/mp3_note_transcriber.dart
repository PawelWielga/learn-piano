import 'dart:typed_data';

import '../audio/audio_file_picker.dart';
import '../pitch/detection_preferences.dart';
import '../pitch/note_event_tracker.dart';
import 'note_recorder.dart';

/// Approximates a *single* melodic line from already decoded MP3 PCM.
///
/// Uses the same YIN and stability thresholds as microphone recording.
/// It is intentionally not a polyphonic instrument separator or a beat tracker.
class Mp3NoteTranscriber {
  const Mp3NoteTranscriber();

  static const _frameSize = 2048;

  Future<Mp3Transcription> transcribe(
    DecodedAudioFile audio, {
    DetectionPreferences preferences = const DetectionPreferences(),
    bool Function()? isCancelled,
    void Function(double)? onProgress,
  }) async {
    final sampleRate = audio.sampleRate;
    if (sampleRate < 4000 ||
        sampleRate > 96000 ||
        audio.samples.length < _frameSize ||
        audio.duration > const Duration(seconds: 90)) {
      throw const FormatException('Nieobsługiwany czas lub próbkowanie MP3.');
    }

    final detector = preferences.createDetector();
    final tracker = preferences.createTracker();
    final recorder = NoteRecorder();
    recorder.start();
    final hop = (sampleRate * 0.13).round();
    final lastStart = audio.samples.length - _frameSize;
    var processed = 0;
    var truncated = false;

    for (var start = 0; start <= lastStart; start += hop) {
      if (isCancelled?.call() ?? false) {
        throw const Mp3TranscriptionCancelled();
      }

      // Copy just one analysis window instead of holding another copy of
      // the entire decoded file. The picker owns the full array transiently.
      final frame = Float32List.sublistView(
        audio.samples,
        start,
        start + _frameSize,
      );
      final at = Duration(
        microseconds: (start * 1000000 / sampleRate).round(),
      );
      final update = tracker.observe(detector.detect(frame, sampleRate), at);
      for (final event in update.events) {
        if (event.type == NoteEventType.noteOn) {
          recorder.noteOn(event.midiNote, event.at);
        } else {
          recorder.noteOff(event.midiNote, event.at);
        }
      }

      processed++;
      if (recorder.isFull) {
        truncated = true;
        break;
      }
      if (processed % 6 == 0) {
        onProgress?.call((start / lastStart).clamp(0.0, 1.0));
        // Yield to Flutter so scrolling, progress and navigation remain usable.
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (isCancelled?.call() ?? false) {
      throw const Mp3TranscriptionCancelled();
    }
    recorder.stop(audio.duration);
    onProgress?.call(1);
    return Mp3Transcription(
      notes: recorder.notes,
      duration: audio.duration,
      truncated: truncated,
    );
  }
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
}

class Mp3TranscriptionCancelled implements Exception {
  const Mp3TranscriptionCancelled();
}
