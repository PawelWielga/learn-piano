import 'dart:typed_data';

/// Captured mono PCM audio. [capturedAt] uses the AudioContext timeline,
/// not wall-clock time; amplitudes are normalized to -1.0..1.0.
class PcmFrame {
  const PcmFrame({
    required this.samples,
    required this.sampleRate,
    required this.capturedAt,
  });

  final Float32List samples;
  final int sampleRate;
  final Duration capturedAt;
}

enum AudioInputStatus { listening, stopped, interrupted }

enum AudioInputFailure {
  insecureContext,
  permissionDenied,
  noDevice,
  deviceBusy,
  unsupported,
  alreadyRunning,
  cancelled,
  unknown,
}

class AudioInputException implements Exception {
  const AudioInputException(this.failure);

  final AudioInputFailure failure;

  @override
  String toString() => 'AudioInputException: ${failure.name}';
}

/// Web adapter behind a platform-independent, injectable API.
///
/// No PCM frames are persisted or sent over the network.
abstract class AudioInput {
  Stream<PcmFrame> get frames;
  Stream<AudioInputStatus> get statuses;

  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
