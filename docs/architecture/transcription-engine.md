# Offline transcription boundary (#60)

The MP3 import screen depends on `TranscriptionEngine` and receives the default
implementation through `createTranscriptionEngine()`. The legacy analyzer is
wrapped by `LegacyDspTranscriptionEngine`; the old `Mp3NoteTranscriber` API
remains available to existing benchmarks and tests.

The engine accepts local mono `DecodedAudioFile` (Float32 PCM and actual sample
rate), options, cooperative cancellation and progress. It returns a stable
`engineId`, audio duration, `TranscribedNote` onset/end/MIDI pitch/velocity,
optional 0–1 confidence, optional relative pitch-bend points, truncation and
limitations. All of these are pure Dart types. No JS, WebAudio, ONNX or Android
types belong in the contract.

Before export, `toRecordedNotes()` validates pitch, velocity, duration, end
within the file, confidence and bends. It preserves chords and sorts by onset
and pitch. The existing `MidiRecordingWriter` still writes the validated
notes. It does **not** currently export pitch bends; the import screen warns
when a future engine supplies them. Confidence from the legacy DSP remains
null, not an invented probability.

An eventual Basic Pitch ONNX adapter should normalize inference onset,
offset, pitches and bends into this contract. It must verify model weights,
commercial usage and runtime compatibility separately (#59/#68/#69). This
refactor does not install an inference engine or upload any audio.

The widget tracks the request generation. After cancel/navigation/new import,
late progress, errors and completed results must not replace current state.
The engine's cancellation callback is cooperative, so the UI ignores stale
results even if an engine delays or ignores cancellation. Input audio stays
local and in memory until abandoned.

CI: `flutter test test/transcription test/screens/mp3_import_engine_test.dart`,
plus the full Flutter suite, synthetic MP3 benchmark and Web release build.
There is no physical-device claim. A future Android adapter should implement
the same interface without changing widgets.
