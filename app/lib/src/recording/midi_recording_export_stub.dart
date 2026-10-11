import 'dart:typed_data';

import 'midi_recording_export.dart';

MidiRecordingExporter createMidiRecordingExporter() =>
    _UnsupportedMidiRecordingExporter();

class _UnsupportedMidiRecordingExporter implements MidiRecordingExporter {
  @override
  bool save(Uint8List bytes, String fileName) => false;
}
