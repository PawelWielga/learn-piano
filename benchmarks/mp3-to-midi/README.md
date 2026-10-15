# MP3 → MIDI: generated reference fixtures

The previous `your-reality/source.mp3` and `reference.mid` were not synchronized and their redistribution rights were **unverified**. They are removed from the current branch. Do not use their diagnostic F1 scores as an indication of transcription accuracy.

## Generate reproducible fixtures

From the repository root, using Python 3.10+ and no third-party Python dependencies:

```sh
python3 benchmarks/mp3-to-midi/generate.py --output /tmp/learn-piano-fixtures
python3 -m unittest discover -s benchmarks/mp3-to-midi -p 'test_*.py' -v
```

Eight original scenarios are generated as synchronized `.mid` and `.wav` pairs plus `manifest.json` with note events and SHA-256 checksums:

| Scenario | Coverage |
| --- | --- |
| `range_c2_c6` | C2 (MIDI 36) and C6 (84) |
| `dyad` | Two simultaneous pitches |
| `triad` | Three simultaneous pitches |
| `bass_melody` | Sustained bass with melody |
| `repeated_c4` | Repeated same-pitch attacks |
| `staccato_rests` | Short notes and silence |
| `dynamics` | Variable velocities |
| `overlap_voices` | Overlapping note boundaries |

**Origin and licensing:** All sequences are original short exercises authored in `generate.py`, not copyrighted-song transcriptions. The additive sine-wave renderer uses no external soundfont, samples, model weights or downloads. Generated data are intended only for project tests; the repository owner's decision on licensing of project code/fixtures remains tracked under #68. Generated binary files stay out of Git and are created in CI.

**Timeline:** MIDI type 0, PPQ 480, 120 BPM, 960 ticks/second. WAV mono PCM16, 24 kHz, 25 samples/tick. Both derive from the same note events, so MIDI zero and WAV sample zero agree **exactly (offset 0 ms)**. The audio has a 5 ms attack and a 12 ms release *inside each reference note duration*, then a 200 ms silent tail. This is a clean synthesized PCM benchmark, not a recording of a real piano.

To optionally create MP3 files (FFmpeg with `libmp3lame` required), add `--mp3` to the generator command. **MP3 encoder delay/padding has not been calibrated**, so do not use these compressed files for timing accuracy claims until their delay is measured. CI transcribes WAV decoded to float32 PCM rather than claiming MP3-codec accuracy.

## Diagnostic transcription test

```sh
ffmpeg -hide_banner -loglevel error -y -i /tmp/learn-piano-fixtures/triad.wav \
  -ac 1 -ar 24000 -f f32le /tmp/triad.f32
cd app
flutter pub get
dart run tool/mp3_benchmark.dart /tmp/triad.f32 /tmp/learn-piano-fixtures/triad.mid
```

This quick single-file command is diagnostic. The reviewed regression gate below validates fixture provenance, tests matching, and measures every generated case.

## Git history

Removing the two historical binaries from the present branch **does not remove them from old commits or existing clones/forks**. No history rewrite or force-push was performed; the decision and any coordinated cleanup remain with the repo owner (#54). A unit test rejects any tracked audio/MIDI binary under `benchmarks/mp3-to-midi`; explicitly reviewed exceptions would need a change to that guard.

## Reproducible accuracy and regression gate (issue #56)

The benchmark checks the **real transcription algorithm** against locally synthesized
WAV/PCM with an exactly aligned MIDI reference. The Python runner validates each
WAV and MIDI SHA-256 against the generated manifest before computing any metric.
The five approved fixtures also check their exact reference note events against
[baseline.json](baseline.json). Changed note material or time offsets are rejected.

After installing Flutter/Dart and FFmpeg (with the app dependencies resolved), run:

```sh
python3 benchmarks/mp3-to-midi/generate.py --output /tmp/learn-piano-fixtures
python3 -m unittest discover -s benchmarks/mp3-to-midi -p 'test_*.py' -v
cd app && flutter pub get && flutter test test/benchmark/note_matching_test.dart && cd ..
python3 benchmarks/mp3-to-midi/run_benchmark.py \
  --fixtures /tmp/learn-piano-fixtures \
  --baseline benchmarks/mp3-to-midi/baseline.json \
  --output /tmp/learn-piano-benchmark-report
```

The report contains JSON note-level false positives and false negatives, likely
octave mistakes, onset/offset absolute error mean/p50/p95/max, and a Markdown table
per scenario with mono/poly labels. CI uploads only the manifest and report, not
raw audio. The process exits nonzero when the regression budget fails; the
Python unit tests include forced regression cases that must fail.

**Metric definition:** pitch must match exactly and absolute onset error must
be at most **130 ms**. The separate strict score additionally requires absolute
offset error at most **160 ms**. Both matching passes find a deterministic
**maximum-cardinality one-to-one matching** (augmenting paths), so no detected
or reference note can receive two true positives. Candidate edges are ordered
by absolute timing error, but global minimum timing error is not guaranteed.
Precision = TP / (TP + FP), recall = TP / (TP + FN), F1 = harmonic mean.
Octave errors are pairs of still-unmatched notes offset by multiples of 12
semitones with onsets within tolerance; they **remain FP and FN**, never TP.
Timing percentile values describe correctly paired notes, not ignored misses.

**Baseline:** results measured by Actions on 2026-10-15 with the old matcher
yielded zero FP/FN and F1 1.000 (both policies) for `range_c2_c6` (2 notes),
`triad` (3), `bass_melody` (4), `repeated_c4` (3) and
`overlap_voices` (3). Those five cases are locked in `baseline.json` with
a **zero regression budget** for F1 loss, extra FP and extra FN. This is a
comparison to actual measured results, not an arbitrary F1=0.95 threshold.
`dyad`, `staccato_rests` and `dynamics` are additional **diagnostic**
scenarios until their results are explicitly reviewed and approved.

To change reference music, matching policy or budgets, update the generator
and `baseline.json` in the same reviewed PR, explain why and inspect newly
generated CI metrics first. Never weaken the baseline merely to make an
unexplained algorithm regression pass.

This is an intentionally narrow, easy **clean synthetic PCM** dataset.
It does not validate real piano acoustics, room noise, microphone input, or
MP3 encoder/decoder delay. Future comparisons of actual MP3 must measure
and compensate codec alignment first; the benchmark must not present WAV
metrics as MP3 accuracy.
