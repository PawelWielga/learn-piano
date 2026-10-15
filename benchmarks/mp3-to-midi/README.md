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

These F1 figures are **diagnostic only**; a statistically defensible matcher, measured baseline and CI regression thresholds are the subject of #56. Synthetic tones also do not replace real-device and acoustic-piano tests.

## Git history

Removing the two historical binaries from the present branch **does not remove them from old commits or existing clones/forks**. No history rewrite or force-push was performed; the decision and any coordinated cleanup remain with the repo owner (#54). A unit test rejects any tracked audio/MIDI binary under `benchmarks/mp3-to-midi`; explicitly reviewed exceptions would need a change to that guard.
