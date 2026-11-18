"""Build small original M10 PCM chimes; never plays audio or calls an API.

These sounds attract attention only. They are not certified alarm signals,
medical treatment, or confirmation that someone received a support request.
"""
from __future__ import annotations

import argparse
import array
import hashlib
import json
import math
import sys
import wave
from pathlib import Path

RATE = 16000


def samples(duration: float, notes: tuple[tuple[float, float, float], ...]) -> bytes:
    """Original sine-note composition with gentle onset/offset and bounded gain."""
    output = array.array("h")
    for index in range(round(duration * RATE)):
        time = index / RATE
        value = 0.0
        for start, length, frequency in notes:
            elapsed = time - start
            if 0 <= elapsed < length:
                envelope = min(1.0, elapsed / .06, (length - elapsed) / .12)
                value += .18 * envelope * math.sin(2 * math.pi * frequency * elapsed)
        # Keep amplitudes bounded even if this composition is later changed.
        output.append(round(max(-.22, min(.22, value)) * 32767))
    if sys.byteorder != "little":
        output.byteswap()
    return output.tobytes()


def build(project: Path) -> list[dict[str, object]]:
    targets = (
        ("hercare_flutter/assets/audio/crisis/support_chime.wav", 8.0,
         ((.25, .6, 523.25), (1.0, .6, 659.25), (1.75, .9, 783.99),
          (4.25, .6, 523.25), (5.0, .6, 659.25), (5.75, .9, 783.99))),
        ("hercare_flutter/android/app/src/main/res/raw/hercare_urgent.wav", 2.4,
         ((.12, .35, 659.25), (.62, .35, 783.99), (1.12, .35, 659.25),
          (1.62, .5, 783.99))),
    )
    result = []
    for relative, duration, notes in targets:
        path = project / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        with wave.open(str(path), "wb") as writer:
            writer.setnchannels(1)
            writer.setsampwidth(2)
            writer.setframerate(RATE)
            writer.writeframes(samples(duration, notes))
        result.append({"path": relative, "seconds": duration,
                       "bytes": path.stat().st_size,
                       "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args()
    print(json.dumps(build(args.project.resolve()), indent=2))
