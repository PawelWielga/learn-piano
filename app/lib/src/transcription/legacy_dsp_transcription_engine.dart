import '../audio/audio_file_picker.dart';
import '../recording/mp3_note_transcriber.dart';
import 'transcription_engine.dart';

/// Keeps the existing spectral estimator operational while the ONNX prototype
/// is evaluated. No browser/Android interop escapes into the domain contract.
class LegacyDspTranscriptionEngine implements TranscriptionEngine {
  const LegacyDspTranscriptionEngine({
    this.transcriber = const Mp3NoteTranscriber(),
  });

  final Mp3NoteTranscriber transcriber;

  @override
  String get engineId => 'legacy-spectral-dsp-v1';

  @override
  Future<TranscriptionResult> transcribe(
    DecodedAudioFile audio, {
    TranscriptionOptions options = const TranscriptionOptions(),
    bool Function()? isCancelled,
    void Function(double)? onProgress,
  }) async {
    try {
      final result = await transcriber.transcribe(
        audio,
        preferences: options.preferences,
        mode: options.mode == TranscriptionMode.fast
            ? Mp3TranscriptionMode.fast
            : Mp3TranscriptionMode.accurate,
        isCancelled: isCancelled,
        onProgress: onProgress,
      );
      if (isCancelled?.call() ?? false) {
        throw const TranscriptionCancelled();
      }
      return TranscriptionResult(
        engineId: engineId,
        duration: result.duration,
        truncated: result.truncated,
        limitations: const [
          'Eksperymentalna analiza widma: harmoniczne, pogłos i gęste '
              'akordy mogą powodować błędne nuty.',
        ],
        notes: List<TranscribedNote>.unmodifiable(
          result.notes.map(
            (note) => TranscribedNote(
              midiNote: note.midiNote,
              start: note.start,
              end: note.start + note.duration,
              velocity: note.velocity,
              // This DSP estimator has no calibrated note probability.
            ),
          ),
        ),
      );
    } on Mp3TranscriptionCancelled {
      throw const TranscriptionCancelled();
    }
  }
}
