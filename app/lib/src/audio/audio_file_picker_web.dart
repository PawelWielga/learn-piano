import 'dart:js_interop';

import 'audio_file_picker.dart';

@JS('learnPianoMp3.pick')
external JSPromise<_DecodedAudioSelection> _pickMp3();

extension type _DecodedAudioSelection(JSObject _) implements JSObject {
  external bool get ok;
  external String? get code;
  external String? get name;
  external JSFloat32Array? get samples;
  external JSNumber? get sampleRate;
}

AudioFilePicker createAudioFilePicker() => WebAudioFilePicker();

class WebAudioFilePicker implements AudioFilePicker {
  @override
  Future<DecodedAudioFile?> pickAndDecode() async {
    try {
      final result = await _pickMp3().toDart;
      if (!result.ok) {
        if (result.code == 'cancelled') return null;
        throw AudioFilePickException(switch (result.code) {
          'too_large' => 'MP3 jest zbyt duży (maksymalnie 12 MB).',
          'too_long' => 'MP3 jest zbyt długi (maksymalnie 90 sekund).',
          'invalid_format' => 'Wybierz plik z rozszerzeniem .mp3.',
          'unsupported' => 'Przeglądarka nie obsługuje dekodowania MP3.',
          'busy' => 'Wybieranie pliku już trwa.',
          'decode_failed' => 'Nie udało się zdekodować pliku MP3.',
          _ => 'Nie udało się odczytać wybranego MP3.',
        });
      }
      final name = result.name;
      final samples = result.samples;
      final sampleRate = result.sampleRate?.toDartDouble.round();
      if (name == null ||
          samples == null ||
          sampleRate == null ||
          sampleRate <= 0) {
        throw const AudioFilePickException('Niekompletne dane dźwiękowe.');
      }
      return DecodedAudioFile(
        name: name,
        samples: samples.toDart,
        sampleRate: sampleRate,
      );
    } on AudioFilePickException {
      rethrow;
    } catch (_) {
      throw const AudioFilePickException(
        'Błąd odczytu MP3. Spróbuj użyć innego pliku.',
      );
    }
  }
}
