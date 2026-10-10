import 'midi_file_picker.dart';
import 'midi_file_picker_stub.dart'
    if (dart.library.js_interop) 'midi_file_picker_web.dart'
    as platform;

MidiFilePicker createMidiFilePicker() => platform.createMidiFilePicker();
