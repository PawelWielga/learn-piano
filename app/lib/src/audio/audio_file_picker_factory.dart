import 'audio_file_picker.dart';
import 'audio_file_picker_stub.dart'
    if (dart.library.js_interop) 'audio_file_picker_web.dart'
    as platform;

AudioFilePicker createAudioFilePicker() => platform.createAudioFilePicker();
