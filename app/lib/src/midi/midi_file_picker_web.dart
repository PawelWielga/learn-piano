import 'dart:js_interop';

import 'midi_file_picker.dart';

@JS('learnPianoMidi.pick')
external JSPromise<_FileSelection> _pickFile();

extension type _FileSelection(JSObject _) implements JSObject {
  external bool get ok;
  external String? get code;
  external String? get name;
  external JSUint8Array? get bytes;
}

MidiFilePicker createMidiFilePicker() => WebMidiFilePicker();

class WebMidiFilePicker implements MidiFilePicker {
  @override
  Future<PickedMidiFile?> pick() async {
    try {
      final result = await _pickFile().toDart;
      if (!result.ok) {
        if (result.code == 'cancelled') return null;
        throw MidiFilePickException(
          result.code == 'too_large'
              ? 'Plik jest za duży. Maksymalny rozmiar to 2 MB.'
              : 'Nie udało się odczytać pliku MIDI.',
        );
      }
      final data = result.bytes;
      final name = result.name;
      if (data == null || name == null) {
        throw const MidiFilePickException('Niekompletne dane pliku MIDI.');
      }
      return PickedMidiFile(name: name, bytes: data.toDart);
    } on MidiFilePickException {
      rethrow;
    } catch (_) {
      throw const MidiFilePickException(
        'Nie udało się wybrać pliku. Spróbuj ponownie.',
      );
    }
  }
}
