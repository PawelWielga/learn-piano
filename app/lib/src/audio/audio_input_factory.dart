import 'audio_input.dart';
import 'audio_input_stub.dart'
    if (dart.library.js_interop) 'audio_input_web.dart' as platform;

AudioInput createAudioInput() => platform.createAudioInput();
