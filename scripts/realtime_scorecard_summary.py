#!/usr/bin/env python3
"""Present local synthetic PCM benchmark JSON as a concise Markdown table."""
from __future__ import annotations
import json
from pathlib import Path
import sys


def render(report: dict) -> str:
    lines = [
        "# Realtime synthetic PCM detector scorecard",
        "",
        "**YIN mono vs FFT poly baseline; no trained model was run.**",
        "",
        "| Scenario | Hz | Detector | TP | FP | FN | Onset F1 | Strict F1 | "
        "Onset p95 ms | Compute ms | ms/packet | RSS delta MB |",
        "| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: | "
        "---: | ---: | ---: | ---: |",
    ]
    for c in report["cases"]:
        o, s = c["onset"], c["strict"]
        lines.append(
            f"| {c['name']} | {c['sampleRate']} | {c['source']} | "
            f"{o['matched']} | {o['falsePositives']} | "
            f"{o['falseNegatives']} | {o['f1']:.3f} | {s['f1']:.3f} | "
            f"{o['onsetErrorMs']['p95Abs']:.1f} | "
            f"{c['computeWallMs']:.1f} | {c['computePerPacketMs']:.3f} | "
            f"{c['processRssDeltaBytes'] / 1048576:.2f} |"
        )
    lines.extend([
        "",
        "Known C3+C4 octave-mask failure remains a scored false negative. "
        "See attached JSON for individual missed/ghost pitches.",
        "",
        "±650ms onset, ±700ms strict offset; not comparable to offline MP3 metric. "
        "Compute time is VM wall time in observe(), RSS is not peak. "
        "No physical piano, browser/Android latency or model inference measured.",
    ])
    return "\n".join(lines) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: realtime_scorecard_summary.py report.json", file=sys.stderr)
        return 2
    try:
        report = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
        assert isinstance(report["cases"], list)
        assert len(report["cases"]) >= 8
        print(render(report))
        return 0
    except (OSError, AssertionError, ValueError, KeyError) as exc:
        print(f"Invalid realtime scorecard: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
