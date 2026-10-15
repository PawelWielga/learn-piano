"""Synthetic fixtures and provenance checks, without real hardware."""

from pathlib import Path
import subprocess
import tempfile
import unittest
import wave

from generate import SCENARIOS, SAMPLE_RATE, TICKS_PER_SECOND, generate, samples_at


class FixtureGeneratorTests(unittest.TestCase):
    def test_scenarios_cover_core_failures(self):
        self.assertGreaterEqual(len(SCENARIOS), 6)
        self.assertEqual(min(n.pitch for s in SCENARIOS.values() for n in s), 36)
        self.assertEqual(max(n.pitch for s in SCENARIOS.values() for n in s), 84)
        self.assertTrue(any(len({n.onset for n in s}) < len(s) for s in SCENARIOS.values()))
        self.assertTrue(any(len({n.velocity for n in s}) > 1 for s in SCENARIOS.values()))
        self.assertEqual(TICKS_PER_SECOND, 960)

    def test_outputs_are_identical_on_two_runs(self):
        with tempfile.TemporaryDirectory() as temp:
            a = Path(temp) / "a"
            b = Path(temp) / "b"
            self.assertEqual(generate(a), generate(b))
            for path in a.iterdir():
                self.assertEqual(path.read_bytes(), (b / path.name).read_bytes())

    def test_all_midi_and_wav_timelines_match(self):
        with tempfile.TemporaryDirectory() as temp:
            output = Path(temp)
            manifest = generate(output)
            self.assertEqual(manifest["audio_to_midi_offset_ms"], 0)
            for name, notes in SCENARIOS.items():
                midi = (output / f"{name}.mid").read_bytes()
                self.assertEqual(midi[:4], b"MThd")
                self.assertEqual(int.from_bytes(midi[12:14], "big"), 480)
                self.assertIn(b"\xff\x51\x03\x07\xa1\x20", midi)
                self.assertEqual(midi[-4:], b"\x00\xff\x2f\x00")
                with wave.open(str(output / f"{name}.wav")) as wav:
                    self.assertEqual(wav.getframerate(), SAMPLE_RATE)
                    self.assertEqual(wav.getnchannels(), 1)
                    self.assertEqual(wav.getsampwidth(), 2)
                    last_end = max(n.onset + n.length for n in notes)
                    self.assertEqual(wav.getnframes(), samples_at(last_end) + 4800)
                    # Reference ticks and synthesis indices coincide exactly.
                    for note in notes:
                        self.assertEqual(samples_at(note.onset) * 960,
                                         note.onset * SAMPLE_RATE)
                        self.assertEqual(samples_at(note.onset + note.length) * 960,
                                         (note.onset + note.length) * SAMPLE_RATE)
                self.assertEqual(len(manifest["scenarios"][name]["notes"]), len(notes))

    def test_unverified_audio_cannot_be_tracked(self):
        root = Path(__file__).resolve().parents[2]
        tracked = subprocess.check_output(
            ["git", "ls-files", "--", "benchmarks/mp3-to-midi"],
            cwd=root, text=True,
        ).splitlines()
        prohibited = [p for p in tracked if Path(p).suffix.lower() in
                      {".mp3", ".mid", ".midi", ".wav", ".flac", ".ogg", ".m4a"}]
        self.assertEqual(prohibited, [], "Audio/MIDI must be generated, never committed")


if __name__ == "__main__":
    unittest.main()
