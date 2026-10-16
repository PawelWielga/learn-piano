# Realtime synthetic PCM replay, issue #57

Run: `cd app && flutter test test/pitch/realtime_pcm_replay_test.dart`

Tests synthesize original sine and harmonic tones without sampled music,
external soundfonts, downloads or a physical keyboard. The helper creates
2048-sample AudioWorklet-style packets at 44,100 and 48,000 Hz with monotonic
capture timestamps. The mono pipeline reproduces the 120 ms sampling cadence
of the training screen and invokes the real YIN `PitchDetector`,
`NoteEventTracker` and `WaitForNoteEngine`. The chord pipeline exercises
`PolyphonicNoteTracker` directly.

The tests cover each C2–C6 semitone, low notes with strong harmonics, weak
deterministic noise, silence, sensitive quiet notes, tuning at ±30 and
+42 cents, reverberation-like fading tails, held C2, repeated C4,
interrupted capture, an octave leap, and 2–4 pitches with a stronger bass.
A single continuous key must not complete C4–C4–C4. CI prints synthetic
algorithmic NoteOn latency in milliseconds relative to scheduled onsets,
plus actual/missing/ghost chord pitches.

**This is not proof of accurate detection on a physical piano.** It does not
test microphone hardware, room acoustics, phone latency, noisy environments
or Android integration. The current spectral chord tracker is experimental;
future model comparisons belong in #72. Physical criteria in #7 and #16
remain open until real equipment is available.

**Observed synthetic limitation (2026-10-16):** When C3 (MIDI 48) has a
stronger fundamental than the simultaneous C4 (MIDI 60), the current FFT
tracker can suppress C4 as if it were merely C3's second harmonic. The
octave-overlap test records missing notes and guards a basic bound, but
**does not claim good chord recall**. The issue is explicitly tracked in #72.
Non-octave overlapping chords have stricter assertions.
