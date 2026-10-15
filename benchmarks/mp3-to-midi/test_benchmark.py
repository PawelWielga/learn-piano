"""Contract tests: regression gate rejects synthetic algorithm degradations."""

from pathlib import Path
import tempfile
import unittest

from run_benchmark import check_fixture, regression_errors


ROOT = Path(__file__).resolve().parents[2]


def score(tp=3, fp=0, fn=0, f1=1.0):
    return {
        "reference": tp + fn,
        "matched": tp,
        "falsePositives": fp,
        "falseNegatives": fn,
        "f1": f1,
    }


class RegressionGateTests(unittest.TestCase):
    def setUp(self):
        self.case = {
            "reference": 3,
            "onset": {"f1": 1.0, "falsePositives": 0, "falseNegatives": 0},
            "strict": {"f1": 1.0, "falsePositives": 0, "falseNegatives": 0},
        }
        self.budgets = {
            key: {"maxF1Drop": 0, "maxExtraFalsePositives": 0, "maxExtraFalseNegatives": 0}
            for key in ("onset", "strict")
        }
        self.result = {
            "referenceExcluded": 0,
            "truncated": False,
            "methodology": "maximum-cardinality-v1",
            "onsetToleranceMs": 130,
            "offsetToleranceMs": 160,
            "onset": score(),
            "strict": score(),
        }

    def test_approved_baseline_passes(self):
        self.assertEqual(regression_errors(self.case, self.result, self.budgets), [])

    def test_missing_note_is_a_regression(self):
        self.result["onset"] = score(tp=2, fn=1, f1=0.8)
        self.assertTrue(regression_errors(self.case, self.result, self.budgets))

    def test_extra_note_is_a_regression(self):
        self.result["strict"] = score(tp=3, fp=1, f1=6 / 7)
        self.assertTrue(regression_errors(self.case, self.result, self.budgets))

    def test_unscored_reference_and_changed_matching_tolerance_rejected(self):
        self.result["referenceExcluded"] = 1
        self.result["onsetToleranceMs"] = 250
        failures = regression_errors(self.case, self.result, self.budgets)
        self.assertGreaterEqual(len(failures), 2)

    def test_modified_audio_hash_fails_before_scoring(self):
        with tempfile.TemporaryDirectory() as path:
            directory = Path(path)
            (directory / "triad.wav").write_bytes(b"altered audio")
            (directory / "triad.mid").write_bytes(b"altered midi")
            manifest = {
                "generator_version": 1,
                "audio_to_midi_offset_ms": 0,
                "sample_rate_hz": 24000,
                "scenarios": {"triad": {"wav_sha256": "0" * 64, "mid_sha256": "1" * 64}},
            }
            with self.assertRaises(ValueError):
                check_fixture(manifest, directory, "triad")


if __name__ == "__main__":
    unittest.main()
