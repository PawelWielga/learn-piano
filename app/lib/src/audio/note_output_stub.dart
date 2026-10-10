import 'note_output.dart';

NoteOutput createNoteOutput() => _UnavailableNoteOutput();

class _UnavailableNoteOutput implements NoteOutput {
  @override
  bool noteOn(int midiNote) => false;

  @override
  void noteOff(int midiNote) {}

  @override
  void stopAll() {}

  @override
  void dispose() {}
}
