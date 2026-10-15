#!/usr/bin/env python3
"""Reproducible, original note-event fixtures: MIDI SMF0 and synthesized WAV.

No downloads, samples, third-party packages, or randomly generated material.
Both outputs derive from the same Note objects on a 960 tick/second grid.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path
import struct
import subprocess
import wave

SAMPLE_RATE = 24_000
PPQ = 480
TEMPO_US_PER_BEAT = 500_000
TICKS_PER_SECOND = PPQ * 1_000_000 // TEMPO_US_PER_BEAT
SILENCE_TAIL_MS = 200
SYNTH_RELEASE_MS = 12
GENERATOR_VERSION = 1


@dataclass(frozen=True)
class Note:
    pitch: int
    onset: int  # ticks from the start of the MIDI timeline
    length: int  # ticks
    velocity: int = 100


# Self-authored exercises, not transcriptions of copyrighted compositions.
SCENARIOS: dict[str, tuple[Note, ...]] = {
    "range_c2_c6": (Note(36, 96, 280), Note(84, 500, 280)),
    "dyad": (Note(48, 96, 580, 105), Note(55, 96, 580, 90)),
    "triad": (Note(60, 96, 600), Note(64, 96, 600), Note(67, 96, 600)),
    "bass_melody": (
        Note(36, 0, 900, 80), Note(60, 120, 210, 100),
        Note(64, 410, 210, 93), Note(67, 700, 190, 106),
    ),
    "repeated_c4": (Note(60, 0, 180), Note(60, 300, 180), Note(60, 600, 180)),
    "staccato_rests": (Note(52, 0, 95), Note(55, 380, 95), Note(57, 760, 95)),
    "dynamics": (Note(69, 0, 230, 40), Note(69, 360, 230, 115)),
    "overlap_voices": (
        Note(48, 0, 700, 80), Note(60, 230, 700, 103),
        Note(64, 460, 700, 90),
    ),
}


def samples_at(tick: int) -> int:
    """At 24k/960, every tick maps exactly to 25 samples."""
    return tick * SAMPLE_RATE // TICKS_PER_SECOND


def _vlq(value: int) -> bytes:
    if value < 0:
        raise ValueError("Negative MIDI delta time")
    parts = [value & 0x7F]
    value >>= 7
    while value:
        parts.insert(0, 0x80 | (value & 0x7F))
        value >>= 7
    return bytes(parts)


def midi_bytes(notes: tuple[Note, ...]) -> bytes:
    events = [(0, -1, b"\xff\x51\x03" + TEMPO_US_PER_BEAT.to_bytes(3, "big"))]
    for note in notes:
        if not (0 <= note.pitch <= 127 and 1 <= note.velocity <= 127):
            raise ValueError("Invalid MIDI pitch or velocity")
        if note.onset < 0 or note.length <= 0:
            raise ValueError("Invalid MIDI note timing")
        events.append((note.onset, 1, bytes((0x90, note.pitch, note.velocity))))
        events.append((note.onset + note.length, 0, bytes((0x80, note.pitch, 0))))
    events.sort(key=lambda event: (event[0], event[1], event[2]))
    track = bytearray()
    tick = 0
    for at, _, payload in events:
        track.extend(_vlq(at - tick))
        track.extend(payload)
        tick = at
    track.extend(b"\x00\xff\x2f\x00")
    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, PPQ)
    return header + b"MTrk" + struct.pack(">I", len(track)) + track


def pcm_samples(notes: tuple[Note, ...]) -> list[int]:
    length = samples_at(max(note.onset + note.length for note in notes))
    length += SAMPLE_RATE * SILENCE_TAIL_MS // 1000
    signal = [0.0] * length
    attack = SAMPLE_RATE * 5 // 1000
    release = SAMPLE_RATE * SYNTH_RELEASE_MS // 1000
    for note in notes:
        start = samples_at(note.onset)
        end = samples_at(note.onset + note.length)
        frequency = 440.0 * 2 ** ((note.pitch - 69) / 12)
        scale = 0.20 * (note.velocity / 127)
        for index in range(start, end):
            relative = index - start
            envelope = min(1.0, (relative + 1) / attack, (end - index) / release)
            phase = 2 * math.pi * frequency * relative / SAMPLE_RATE
            value = (math.sin(phase) + 0.22 * math.sin(2 * phase)
                     + 0.10 * math.sin(3 * phase)) / 1.32
            signal[index] += scale * envelope * value
    if max(abs(value) for value in signal) >= 1.0:
        raise ValueError("Synthesis clipped")
    return [round(value * 32767) for value in signal]


def write_wav(path: Path, notes: tuple[Note, ...]) -> None:
    samples = pcm_samples(notes)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(SAMPLE_RATE)
        output.writeframes(struct.pack(f"<{len(samples)}h", *samples))


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def generate(destination: Path, *, encode_mp3: bool = False) -> dict:
    destination.mkdir(parents=True, exist_ok=True)
    manifest = {
        "generator_version": GENERATOR_VERSION,
        "origin": "Self-authored short exercises; additive sine synthesis, no soundfont or samples",
        "sample_rate_hz": SAMPLE_RATE,
        "channels": 1,
        "pcm_format": "signed 16-bit little-endian WAV",
        "midi_ppq": PPQ,
        "tempo_us_per_beat": TEMPO_US_PER_BEAT,
        "audio_to_midi_offset_ms": 0,
        "synth_release_ms": SYNTH_RELEASE_MS,
        "silence_tail_ms": SILENCE_TAIL_MS,
        "randomness": "none (no seed needed)",
        "scenarios": {},
    }
    for name, notes in SCENARIOS.items():
        midi = destination / f"{name}.mid"
        wav = destination / f"{name}.wav"
        midi.write_bytes(midi_bytes(notes))
        write_wav(wav, notes)
        entry = {
            "midi_sha256": sha256(midi),
            "wav_sha256": sha256(wav),
            "notes": [
                {"pitch": n.pitch, "onset_tick": n.onset, "length_tick": n.length,
                 "velocity": n.velocity}
                for n in notes
            ],
        }
        if encode_mp3:
            mp3 = destination / f"{name}.mp3"
            subprocess.run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-y",
                "-i", str(wav), "-codec:a", "libmp3lame", "-qscale:a", "2",
                str(mp3),
            ], check=True)
            entry["mp3_sha256"] = sha256(mp3)
        manifest["scenarios"][name] = entry
    (destination / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mp3", action="store_true", help="Optional MP3 encoding via FFmpeg")
    args = parser.parse_args()
    generate(args.output, encode_mp3=args.mp3)
    print(f"Generated {len(SCENARIOS)} synchronized MIDI/WAV cases in {args.output}")


if __name__ == "__main__":
    main()
