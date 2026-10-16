# ADR-002: Realtime note detector evaluation (2026-10-16)

**Status:** partial evaluation. Production remains unchanged. Issue #72 is open.

## Decision

Keep pure-Dart YIN + NoteEventTracker as the mono microphone baseline and PolyphonicNoteTracker FFT as an experimental chord baseline. Do not bundle third-party model weights until exact weight licensing and Web/Android performance are confirmed. Adopt the portable RealtimeNoteDetector port and a repeatable synthetic PCM scorecard to compare future models. There is no backend or audio upload.

## Candidates and limitations

| Candidate | Evidence / compatibility | Decision |
| --- | --- | --- |
| Google Magenta **Onsets & Frames**, experimental realtime TFLite, preferably unidirectional no-offset variant | Apache-2.0 source repository; published pretrained weight links, but **commercial redistribution terms for those exact weights have not yet been verified** (#68). Model expects 16 kHz input; 44.1/48 kHz requires filtered resampling. Demo ran on Linux/Raspberry Pi, not tested on Flutter Web/Android; Python repository archived 2026-01-06. | Research candidate #1, **not run in Learn Piano or distributed** |
| Spotify **Basic Pitch** ONNX/TFLite | Official Apache-2.0 implementation; recorded-file transcriptions, not an established low-latency causal NoteOn stream. | Keep for offline #59, **do not reuse as live scoring without separate evidence** |
| Project YIN, pure Dart | Already passes synthetic C2–C6 mono tests; low-frequency onset delay measured on GitHub CI | Retain as mono baseline |
| Project FFT polyphony | Synthetic 2–4 voice cases, known C3+C4 harmonic masking, no calibrated per-key confidence | Retain for comparative baseline, not a validated 88-key classifier |

Sources:
- https://github.com/magenta/magenta/blob/main/magenta/models/onsets_frames_transcription/realtime/README.md
- https://github.com/magenta/magenta/blob/main/magenta/models/onsets_frames_transcription/realtime/tflite_model.py
- https://github.com/magenta/magenta
- https://github.com/spotify/basic-pitch

Do not confuse the *Magenta RealTime* generative music model with the historical piano transcription model *Onsets & Frames*.

## Contract and comparison

The new `app/lib/src/pitch/realtime_note_detector.dart` contract accepts `PcmFrame` and returns original NoteOn/NoteOff plus source and evidence provenance. It can be reused by Web and future native Android because it has no JS/Flutter imports. The YIN confidence is a periodicity score, **not a calibrated probability**. FFT cannot supply credible per-note confidence and reports `null`, never a fabricated value. The new adapters are benchmarking/migration interfaces; `TrainingScreen` is intentionally unchanged until a validated model and abstention policy are available.

The `realtime-scorecard.yml` workflow runs original self-generated 2048-sample PCM at 44.1/48 kHz. It measures mono C2/C6/repeated C4/silence and polyphonic 2/3/4 voices and bass C3+C4, with separate algorithm labels. Output: onset/strict precision, recall, F1 and FP/FN, octave errors, per-event onset delay, compute wall time per input packet, and before/after process RSS. The note matcher is deterministic maximum-cardinality 1:1; tolerances **650 ms onset / 700 ms offset** are for realtime state machines only, not the stricter offline #56 methodology.

These **are not model-vs-heuristic results on identical tasks**: YIN is mono-only; FFT is tested on chords. No model performance, weight size, browser/Android speed, battery consumption, total input-to-screen latency or real piano accuracy is claimed. Timing is Stopwatch wall time on GitHub runner, not a hardware benchmark; RSS delta is not peak memory. Scorecard stores JSON metadata, never raw PCM.

Known failing musical case (do not hide it): 48 kHz 2048-packet C3 (MIDI 48, gain 0.23) plus quieter C4 (MIDI 60, gain 0.12) can suppress C4 as a harmonic of C3. Record missing C4 as FN. Tests must allow an improved detector to fix this, rather than enforce the existing failure.

## Conditions for selecting ML in a follow-up PR

1. Verify **exact model weights** commercial redistribution rights separately from source license (#68), immutable SHA-256, notices, download size.
2. Implement one controlled TFLite/ONNX PoC using the chosen official model; cold-start offline Web and native Android, correct filtered resampling, bounded stream windows and time alignment.
3. Run that model on the **same reference PCM fixtures**, reporting 1–4 voices, missing/ghost/repeated notes, latency, CPU/RSS and confidence-based abstention.
4. Demonstrate acceptable interactive input-to-NoteOn latency and UI responsiveness; no model may be enabled by default without passing tests and an explicit fallback plan.
5. Physical piano, acoustics, microphone and Android-device validation remain outstanding (#7, #16, #71).

**Outcome:** benchmark infrastructure and the portable detector interface are implemented. A trained-model PoC, legal review and production integration are NOT complete, so #72 remains open.
