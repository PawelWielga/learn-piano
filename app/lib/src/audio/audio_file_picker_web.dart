import 'dart:async';
import 'dart:js_interop';

import 'audio_file_picker.dart';

// The old index.html can be cached after a deploy while main.dart.js is new.
// Detect the absent global and load the missing helper before user interaction.
@JS('globalThis.learnPianoMp3')
external JSObject? get _mp3Module;

@JS('document.createElement')
external _ScriptTag _createScriptTag(JSString name);

@JS('document.head.appendChild')
external JSAny? _appendToHead(_ScriptTag element);

extension type _ScriptTag(JSObject _) implements JSObject {
  external set src(String value);
  external set onload(JSFunction? callback);
  external set onerror(JSFunction? callback);
  external void remove();
}

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

class WebAudioFilePicker implements AudioFilePicker, PreparableAudioFilePicker {
  Future<void>? _preparing;

  @override
  Future<void> prepare() {
    if (_mp3Module != null) return Future<void>.value();
    return _preparing ??= _loadBridge().whenComplete(() {
      _preparing = null;
    });
  }

  Future<void> _loadBridge() async {
    final completer = Completer<void>();
    final script = _createScriptTag('script'.toJS);
    Timer? timeout;

    void finish(bool loaded) {
      if (completer.isCompleted) return;
      timeout?.cancel();
      script.onload = null;
      script.onerror = null;
      script.remove();
      if (loaded && _mp3Module != null) {
        completer.complete();
      } else {
        completer.completeError(
          const AudioFilePickException(
            'Nie udało się uruchomić wyboru pliku MP3. '
            'Sprawdź połączenie i odśwież stronę.',
          ),
        );
      }
    }

    script.onload = (() => finish(true)).toJS;
    script.onerror = (() => finish(false)).toJS;
    // Cache-busted fallback for installations with an outdated index.html.
    script.src = 'mp3_file_input.js?bridge=2';
    timeout = Timer(const Duration(seconds: 10), () => finish(false));
    try {
      _appendToHead(script);
    } catch (_) {
      finish(false);
    }
    await completer.future;
  }

  @override
  Future<DecodedAudioFile?> pickAndDecode() async {
    // No await before the native chooser: preserve Firefox's user activation.
    if (_mp3Module == null) {
      throw const AudioFilePickException(
        'Brakuje modułu wyboru MP3. Wróć do ekranu importu '
        'lub odśwież stronę.',
      );
    }
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
          'open_failed' => 'Przeglądarka nie pozwoliła otworzyć wyboru pliku. '
              'Spróbuj ponownie lub odśwież stronę.',
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
        'Nie udało się otworzyć wyboru MP3. '
        'Odśwież stronę i spróbuj ponownie.',
      );
    }
  }
}
