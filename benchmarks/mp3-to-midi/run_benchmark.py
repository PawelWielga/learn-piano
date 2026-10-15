#!/usr/bin/env python3
"""Verify aligned fixture provenance, measure note scores, and gate regressions.

Requires Python standard library, FFmpeg and Dart/Flutter dependencies. Raw
audio never leaves the runner; only JSON note diagnostics are saved as artifacts.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
APP = ROOT / "app"
SCENARIO_TYPES = {
    "range_c2_c6": "mono",
    "dyad": "poly",
    "triad": "poly",
    "bass_melody": "poly",
    "repeated_c4": "mono",
    "staccato_rests": "mono",
    "dynamics": "mono",
    "overlap_voices": "poly",
}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_fixture(manifest: dict, fixtures: Path, scenario: str) -> None:
    if manifest.get("generator_version") != 1:
        raise ValueError("Unsupported fixture generator version")
    if manifest.get("audio_to_midi_offset_ms") != 0:
        raise ValueError("Benchmark requires verified zero-offset WAV/MIDI")
    if manifest.get("sample_rate_hz") != 24000:
        raise ValueError("Benchmark requires aligned 24000 Hz WAV")
    if scenario not in SCENARIO_TYPES:
        raise ValueError(f"Unknown scenario: {scenario}")
    entry = manifest["scenarios"][scenario]
    for extension in ("wav", "mid"):
        filename = fixtures / f"{scenario}.{extension}"
        if sha256(filename) != entry[f"{extension}_sha256"]:
            raise ValueError(f"Fixture checksum mismatch: {filename}")


def regression_errors(case: dict, result: dict, budgets: dict) -> list[str]:
    """Compare each score independently against a reviewed, measured baseline."""
    errors: list[str] = []
    if result.get("referenceExcluded") != 0:
        errors.append("Reference notes excluded from scoring")
    if result.get("truncated"):
        errors.append("Transcription hit note limit")
    if result.get("methodology") != "maximum-cardinality-v1":
        errors.append("Unexpected matcher methodology")
    if result.get("onsetToleranceMs") != 130 or result.get("offsetToleranceMs") != 160:
        errors.append("Changed matching tolerances require baseline review")
    if result["onset"]["reference"] != case["reference"]:
        errors.append("Reference note count differs from approved baseline")

    for category in ("onset", "strict"):
        actual = result[category]
        previous = case[category]
        budget = budgets[category]
        if actual["f1"] + 1e-9 < previous["f1"] - budget["maxF1Drop"]:
            errors.append(f"{category}: F1 regressed from {previous['f1']:.3f} to {actual['f1']:.3f}")
        if actual["falsePositives"] > previous["falsePositives"] + budget["maxExtraFalsePositives"]:
            errors.append(f"{category}: false positives increased")
        if actual["falseNegatives"] > previous["falseNegatives"] + budget["maxExtraFalseNegatives"]:
            errors.append(f"{category}: false negatives increased")
    return errors


def collect(fixtures: Path, baseline: dict, output: Path) -> tuple[dict, list[str]]:
    manifest = read_json(fixtures / "manifest.json")
    if baseline["generator_version"] != manifest["generator_version"]:
        raise ValueError("Generator version changed; update baseline deliberately")
    if baseline["methodology"] != "maximum-cardinality-v1":
        raise ValueError("Unsupported approved matching policy")
    output.mkdir(parents=True, exist_ok=True)

    for name, case in baseline["cases"].items():
        check_fixture(manifest, fixtures, name)
        if manifest["scenarios"][name]["notes"] != case["notes"]:
            raise ValueError(f"Approved reference note events changed: {name}")

    cases: dict[str, dict] = {}
    failures: list[str] = []
    with tempfile.TemporaryDirectory() as temporary:
        directory = Path(temporary)
        for name in SCENARIO_TYPES:
            check_fixture(manifest, fixtures, name)
            raw_pcm = directory / f"{name}.f32"
            report_file = directory / f"{name}.json"
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(fixtures / f"{name}.wav"),
                "-ac", "1", "-ar", "24000", "-f", "f32le", str(raw_pcm),
            ], check=True)
            task = subprocess.run([
                "dart", "run", "tool/mp3_benchmark.dart", str(raw_pcm),
                str(fixtures / f"{name}.mid"), "--require-full-reference",
                "--json-output", str(report_file),
            ], cwd=APP, text=True, capture_output=True)
            if task.returncode != 0:
                failures.append(f"{name}: benchmark crashed: {task.stderr.strip()}")
                continue
            result = read_json(report_file)
            result["type"] = SCENARIO_TYPES[name]
            result["baselineStatus"] = "approved" if name in baseline["cases"] else "diagnostic"
            if name in baseline["cases"]:
                failures += [
                    f"{name}: {error}"
                    for error in regression_errors(baseline["cases"][name], result, baseline["budgets"])
                ]
            cases[name] = result
            print(f"{name}: matched {result['onset']['matched']}/{result['onset']['reference']}, "
                  f"F1 onset={result['onset']['f1']:.3f}, strict={result['strict']['f1']:.3f}")
    return cases, failures


def write_report(destination: Path, cases: dict, errors: list[str]) -> None:
    destination.mkdir(parents=True, exist_ok=True)
    report = {
        "status": "regression" if errors else "pass",
        "provenance": "generator manifest SHA-256-verified, synchronized WAV + MIDI",
        "scope": "clean synthetic PCM only; MP3 codec delay and real piano not evaluated",
        "cases": cases,
        "errors": errors,
    }
    (destination / "report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    lines = [
        "# Synthetic note transcription benchmark",
        "",
        f"Status: **{report['status']}**. Verified WAV/MIDI, zero offset. "
        "This does not measure MP3 decoding or a real acoustic piano.",
        "",
        "| Scenario | Type | Baseline | Ref | Detected | TP | FP | FN | "
        "Onset F1 | Strict F1 | Onset p95 abs (ms) | Offset p95 abs (ms) | Octave errors |",
        "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | "
        "---: | ---: | ---: | ---: | ---: |",
    ]
    for name, result in cases.items():
        onset = result["onset"]
        strict = result["strict"]
        lines.append(
            f"| {name} | {result['type']} | {result['baselineStatus']} | "
            f"{onset['reference']} | {onset['detected']} | {onset['matched']} | "
            f"{onset['falsePositives']} | {onset['falseNegatives']} | "
            f"{onset['f1']:.3f} | {strict['f1']:.3f} | "
            f"{onset['onsetErrorMs']['p95Abs']:.1f} | "
            f"{onset['offsetErrorMs']['p95Abs']:.1f} | "
            f"{len(result['octaveConfusions'])} |"
        )
    if errors:
        lines += ["", "## Regression failures", ""]
        lines += [f"- {error}" for error in errors]
    lines += [
        "", "Baseline: approved results measured on 2026-10-15 before #56.",
        "Budget: no F1 loss, extra FP or FN on five approved synthetic cases. "
        "Three additional scenarios remain diagnostic until an explicit baseline update.",
        "Matching: max-cardinality one-to-one, pitch and ±130ms onset; strict also ±160ms offset.",
    ]
    (destination / "summary.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        baseline = read_json(args.baseline)
        cases, failures = collect(args.fixtures.resolve(), baseline, args.output.resolve())
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError) as exc:
        cases, failures = {}, [f"Benchmark setup failure: {exc}"]
    write_report(args.output, cases, failures)
    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1
    print(f"Benchmark regression gate passed ({len(cases)} scenarios).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
