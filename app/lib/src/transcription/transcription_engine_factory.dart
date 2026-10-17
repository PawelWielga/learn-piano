import 'legacy_dsp_transcription_engine.dart';
import 'transcription_engine.dart';

/// The default remains offline spectral DSP until a model has passed license,
/// Web/Android runtime and accuracy benchmarks. No choice leaks into the UI.
TranscriptionEngine createTranscriptionEngine() =>
    const LegacyDspTranscriptionEngine();
