import 'midi_file_picker.dart';

MidiFilePicker createMidiFilePicker() => UnsupportedMidiFilePicker();

class UnsupportedMidiFilePicker implements MidiFilePicker {
  @override
  Future<PickedMidiFile?> pick() async {
    throw const MidiFilePickException(
      'Ta platforma nie obsługuje wybierania plików MIDI.',
    );
  }
}
