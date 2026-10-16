# MP3 import: anti-aliasing during half-rate analysis (#58)

At 44,100 and 48,000 Hz the legacy file transcriber previously selected every
second PCM sample without filtering. A source component above half the new
sample rate could therefore fold into an unrelated lower frequency and confuse
the harmonic matcher.

`AntiAliasDecimator` now applies a normalized 63-tap Hamming-windowed,
linear-phase half-band FIR before halving the sample rate. At 44.1 kHz the
analysis rate is 22.05 kHz; at 48 kHz it is 24 kHz. Files below 32 kHz retain
their original rate and samples. The original PCM still feeds the onset RMS
gate and duration timestamps: the analyzer works on the filtered buffer with
the original center index divided by two. The source file is never modified.

The same spectral analyzer also powers the experimental realtime chord tracker.
Its reusable 8192-sample microphone buffer is low-pass filtered into a reusable
4096-sample analysis buffer before each FFT. This avoids silently treating raw
48 kHz samples as if they were already at 24 kHz, which would shift recognized
pitches by an octave. The existing synthetic realtime scorecard and chord tests
must pass as well as the MP3 tests.

The FIR output is computed once for the entire imported file rather than once
per FFT window. It is processed in bounded chunks, yielding between chunks to
keep cancellation and progress responsive. This is a targeted safety fix for
the existing experimental harmonic matcher, **not** an assertion of accurate
piano transcription. Longer-term DSP/FFT and ONNX evaluation remain in #58/#59;
moving all heavy analysis out of the main UI thread remains #61.

Verification in CI:

- `cd app && flutter test test/recording/anti_alias_decimator_test.dart`
  tests 44.1/48 kHz above-Nyquist rejection, preservation of C2–C7
  fundamental frequencies, chunk equivalence and a C2/C6 file import.
- `cd app && flutter test` checks existing chord and import regressions.
- The MP3 benchmark workflow checks the same synchronized synthetic
  MIDI/audio reference and rejects regressions on its existing **24 kHz**
  baseline. Because those fixtures are below the decimation threshold, the
  existing baseline alone **cannot** establish 44.1/48 kHz improvement.
  The additional high-rate alias tests specifically cover that omission.

These synthetic tests do not establish results on a real piano, and no hardware
validation is implied. Future comparison should include runtime and memory
metrics at longer durations on supported browsers.
