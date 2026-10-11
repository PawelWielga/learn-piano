import 'dart:typed_data';

/// Saves generated MIDI locally, without an upload or server.
abstract class MidiRecordingExporter {
  /// Called synchronously from a button tap to preserve browser permissions.
  bool save(Uint8List bytes, String fileName);
}
