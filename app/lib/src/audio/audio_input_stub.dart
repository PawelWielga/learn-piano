import 'dart:async';

import 'audio_input.dart';

AudioInput createAudioInput() => UnsupportedAudioInput();

class UnsupportedAudioInput implements AudioInput {
  final _frames = StreamController<PcmFrame>.broadcast();
  final _statuses = StreamController<AudioInputStatus>.broadcast();

  @override
  Stream<PcmFrame> get frames => _frames.stream;

  @override
  Stream<AudioInputStatus> get statuses => _statuses.stream;

  @override
  Future<void> start() async {
    throw const AudioInputException(AudioInputFailure.unsupported);
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _frames.close();
    await _statuses.close();
  }
}
