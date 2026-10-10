import 'dart:async';
import 'dart:js_interop';

import 'audio_input.dart';

@JS('learnPianoAudio.start')
external JSPromise<_StartResult> _startCapture(
  JSFunction onFrame,
  JSFunction onInterrupted,
);

@JS('learnPianoAudio.stop')
external JSPromise<JSAny?> _stopCapture();

extension type _StartResult(JSObject _) implements JSObject {
  external bool get ok;
  external String? get code;
}

AudioInput createAudioInput() => WebAudioInput();

class WebAudioInput implements AudioInput {
  final _frames = StreamController<PcmFrame>.broadcast();
  final _statuses = StreamController<AudioInputStatus>.broadcast();

  bool _starting = false;
  bool _running = false;
  bool _disposed = false;
  bool _interrupted = false;

  late final JSFunction _frameCallback =
      ((JSFloat32Array data, JSNumber sampleRate, JSNumber timestampMs) {
        if (!_running || _disposed) return;

        // The worklet transfers ownership of its buffer to the main thread.
        // It never reuses the transferred array, so no additional copy is needed.
        _frames.add(
          PcmFrame(
            samples: data.toDart,
            sampleRate: sampleRate.toDartDouble.round(),
            capturedAt: Duration(
              microseconds: (timestampMs.toDartDouble * 1000).round(),
            ),
          ),
        );
      }).toJS;

  late final JSFunction _interruptionCallback = ((JSString reason) {
    if (_disposed) return;
    _interrupted = true;
    _running = false;
    _statuses.add(AudioInputStatus.interrupted);
  }).toJS;

  @override
  Stream<PcmFrame> get frames => _frames.stream;

  @override
  Stream<AudioInputStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    if (_disposed) throw StateError('Audio input already disposed');
    if (_starting || _running) {
      throw const AudioInputException(AudioInputFailure.alreadyRunning);
    }

    _starting = true;
    _interrupted = false;
    try {
      final result = await _startCapture(
        _frameCallback,
        _interruptionCallback,
      ).toDart;
      if (!result.ok) {
        throw AudioInputException(_failureForCode(result.code));
      }
      if (_disposed || _interrupted) {
        await _stopCapture().toDart;
        throw const AudioInputException(AudioInputFailure.cancelled);
      }
      _running = true;
      _statuses.add(AudioInputStatus.listening);
    } on AudioInputException {
      rethrow;
    } catch (_) {
      throw const AudioInputException(AudioInputFailure.unknown);
    } finally {
      _starting = false;
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    try {
      await _stopCapture().toDart;
    } finally {
      if (!_disposed) _statuses.add(AudioInputStatus.stopped);
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await stop();
    } finally {
      await _frames.close();
      await _statuses.close();
    }
  }
}

AudioInputFailure _failureForCode(String? code) {
  return switch (code) {
    'insecure_context' => AudioInputFailure.insecureContext,
    'permission_denied' => AudioInputFailure.permissionDenied,
    'no_device' => AudioInputFailure.noDevice,
    'device_busy' => AudioInputFailure.deviceBusy,
    'unsupported' => AudioInputFailure.unsupported,
    'already_running' => AudioInputFailure.alreadyRunning,
    'cancelled' => AudioInputFailure.cancelled,
    _ => AudioInputFailure.unknown,
  };
}
