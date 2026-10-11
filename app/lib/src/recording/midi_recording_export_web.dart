import 'dart:js_interop';
import 'dart:typed_data';

import 'midi_recording_export.dart';

@JS('learnPianoRecording.download')
external JSBoolean _downloadMidi(JSUint8Array bytes, JSString fileName);

MidiRecordingExporter createMidiRecordingExporter() =>
    WebMidiRecordingExporter();

class WebMidiRecordingExporter implements MidiRecordingExporter {
  @override
  bool save(Uint8List bytes, String fileName) {
    try {
      return _downloadMidi(bytes.toJS, fileName.toJS).toDart;
    } catch (_) {
      return false;
    }
  }
}
