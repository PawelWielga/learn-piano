import 'dart:js_interop';

import 'note_output.dart';

@JS('learnPianoSynth.noteOn')
external JSBoolean _noteOn(JSNumber note);

@JS('learnPianoSynth.noteOff')
external void _noteOff(JSNumber note);

@JS('learnPianoSynth.stopAll')
external void _stopAll();

@JS('learnPianoSynth.dispose')
external void _dispose();

NoteOutput createNoteOutput() => WebNoteOutput();

class WebNoteOutput implements NoteOutput {
  @override
  bool noteOn(int midiNote) {
    if (midiNote < 0 || midiNote > 127) return false;
    try {
      return _noteOn(midiNote.toJS).toDart;
    } catch (_) {
      return false;
    }
  }

  @override
  void noteOff(int midiNote) {
    try {
      _noteOff(midiNote.toJS);
    } catch (_) {
      // The browser may have suspended/removed the audio device.
    }
  }

  @override
  void stopAll() {
    try {
      _stopAll();
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _dispose();
    } catch (_) {}
  }
}
