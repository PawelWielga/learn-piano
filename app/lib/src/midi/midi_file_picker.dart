import 'dart:typed_data';

class PickedMidiFile {
  const PickedMidiFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

class MidiFilePickException implements Exception {
  const MidiFilePickException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Injectable local file chooser, separate from MIDI parsing.
abstract class MidiFilePicker {
  Future<PickedMidiFile?> pick();
}
