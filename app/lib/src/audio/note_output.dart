/// Local instrument sound output. MIDI 60 = C4, A4 = 440 Hz.
/// Unlike AudioInput this never uses the microphone.
abstract class NoteOutput {
  /// Starts a note following a direct user interaction.
  /// False means audio playback is unavailable, not that the note was invalid.
  bool noteOn(int midiNote);
  void noteOff(int midiNote);
  void stopAll();
  void dispose();
}
