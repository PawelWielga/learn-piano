import 'dart:typed_data';

/// Decoded mono PCM held in memory only for the duration of transcription.
class DecodedAudioFile {
  const DecodedAudioFile({
    required this.name,
    required this.samples,
    required this.sampleRate,
  });

  final String name;
  final Float32List samples;
  final int sampleRate;

  Duration get duration => sampleRate <= 0
      ? Duration.zero
      : Duration(microseconds: (samples.length * 1000000 / sampleRate).round());
}

class AudioFilePickException implements Exception {
  const AudioFilePickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Chooses and decodes one local MP3 without uploading it to a server.
abstract class AudioFilePicker {
  Future<DecodedAudioFile?> pickAndDecode();
}

/// Optional warm-up for web bridges needed before opening a native file picker.
///
/// Call on screen entry, not inside the file button callback: mobile browsers
/// require the file chooser to open synchronously during user activation.
abstract interface class PreparableAudioFilePicker {
  Future<void> prepare();
}
