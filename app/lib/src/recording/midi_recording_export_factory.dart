import 'midi_recording_export.dart';
import 'midi_recording_export_stub.dart'
    if (dart.library.js_interop) 'midi_recording_export_web.dart' as platform;

MidiRecordingExporter createMidiRecordingExporter() =>
    platform.createMidiRecordingExporter();
