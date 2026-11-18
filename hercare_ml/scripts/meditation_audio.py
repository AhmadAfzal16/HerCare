"""Generate/check original, public meditation cues without a speech API.

Only this explicit asset-build command loads eSpeak NG. It is not an ML API,
does not process user text, and never uses a speaker/audio playback device.
Flutter captions and synthesized speech share the same source JSON.
"""
from __future__ import annotations

import argparse
import ctypes
import hashlib
import json
from pathlib import Path

import av
import numpy as np

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "hercare_flutter" / "assets"
SOURCE = ASSETS / "meditation_guides.json"
OUTPUT = ASSETS / "audio" / "meditation"
IDS = {"body_scan", "muscle_relaxation", "mindfulness"}


def catalog() -> dict:
    result = json.loads(SOURCE.read_text(encoding="utf-8"))
    if result.get("version") != 1 or set(result.get("activities", {})) != IDS:
        raise ValueError("Unexpected meditation catalog")
    for steps in result["activities"].values():
        if len(steps) != 4:
            raise ValueError("Exactly four short cues are required")
        for step in steps:
            if set(step) != {"en", "ur"} or any(
                not isinstance(text, str) or not 1 <= len(text) <= 1000
                for text in step.values()
            ):
                raise ValueError("Invalid cue")
    return result


class Synthesizer:
    def __init__(self):
        import espeakng_loader

        self.lib = ctypes.CDLL(espeakng_loader.get_library_path())
        self.lib.espeak_Initialize.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_char_p, ctypes.c_int]
        self.lib.espeak_Initialize.restype = ctypes.c_int
        # SYNCHRONOUS retrieval, explicitly NOT playback. Parent contains data dir.
        self.rate = self.lib.espeak_Initialize(
            2, 0, str(Path(espeakng_loader.get_data_path()).parent).encode(), 0x8000
        )
        if not 8000 <= self.rate <= 48000:
            raise RuntimeError("Speech data unavailable")
        callback_type = ctypes.CFUNCTYPE(
            ctypes.c_int, ctypes.POINTER(ctypes.c_short), ctypes.c_int, ctypes.c_void_p
        )
        self.chunks: list[bytes] = []

        def receive(samples, count, _events):
            if samples and count > 0:
                self.chunks.append(ctypes.string_at(samples, count * 2))
            return 0

        self.callback = callback_type(receive)  # keep callback alive
        self.lib.espeak_SetSynthCallback.argtypes = [callback_type]
        self.lib.espeak_SetSynthCallback(self.callback)
        self.lib.espeak_SetVoiceByName.argtypes = [ctypes.c_char_p]
        self.lib.espeak_SetVoiceByName.restype = ctypes.c_int
        self.lib.espeak_SetParameter.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_int]
        self.lib.espeak_Synth.argtypes = [
            ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint, ctypes.c_int,
            ctypes.c_uint, ctypes.c_uint, ctypes.c_void_p, ctypes.c_void_p,
        ]
        self.lib.espeak_Synth.restype = ctypes.c_int
        self.lib.espeak_Info.argtypes = [ctypes.c_void_p]
        self.lib.espeak_Info.restype = ctypes.c_char_p
        self.version = self.lib.espeak_Info(None).decode()
        self.lib.espeak_SetParameter(1, 125, 0)  # gentle speech rate
        self.lib.espeak_SetParameter(2, 80, 0)

    def speak(self, text: str, language: str, *, min_seconds: float = 1) -> np.ndarray:
        self.chunks = []
        if self.lib.espeak_SetVoiceByName(language.encode()) != 0:
            raise RuntimeError(f"Missing {language} voice; no substitute is allowed")
        encoded = ctypes.create_string_buffer(text.encode("utf-8"))
        if self.lib.espeak_Synth(encoded, len(encoded), 0, 1, 0, 1 | 0x1000, None, None) != 0:
            raise RuntimeError("Synthesis failed")
        audio = np.frombuffer(b"".join(self.chunks), dtype=np.int16).copy()
        if not self.rate * min_seconds < audio.size < self.rate * 45 or np.max(np.abs(audio.astype(np.int32))) < 100:
            raise RuntimeError("Empty or unexpectedly long cue")
        return audio


def write_aac(path: Path, audio: np.ndarray, rate: int) -> None:
    # Small mono AAC/M4A assets, supported by existing just_audio on phones/web.
    with av.open(str(path), "w", format="mp4") as container:
        stream = container.add_stream("aac", rate=24000)
        stream.bit_rate = 40000
        stream.layout = "mono"
        resampler = av.AudioResampler(format="fltp", layout="mono", rate=24000)
        frame = av.AudioFrame.from_ndarray(audio.reshape(1, -1), format="s16", layout="mono")
        frame.sample_rate = rate
        for converted in resampler.resample(frame) + resampler.resample(None):
            for packet in stream.encode(converted):
                container.mux(packet)
        for packet in stream.encode(None):
            container.mux(packet)


def verify() -> dict:
    data = catalog()
    manifest = json.loads((OUTPUT / "manifest.json").read_text(encoding="utf-8"))
    if manifest["source_sha256"] != hashlib.sha256(SOURCE.read_bytes()).hexdigest():
        raise ValueError("Captions changed; rebuild audio and re-review")
    expected = {f"{lang}_{activity}_{index}.m4a" for activity in IDS for lang in ("en", "ur") for index in range(4)}
    if {item["file"] for item in manifest["clips"]} != expected:
        raise ValueError("Missing or duplicate cue")
    for clip in manifest["clips"]:
        path = OUTPUT / clip["file"]
        if hashlib.sha256(path.read_bytes()).hexdigest() != clip["sha256"]:
            raise ValueError(f"Asset mismatch: {clip['file']}")
        with av.open(str(path)) as container:
            frames = list(container.decode(audio=0))
            samples = sum(frame.samples for frame in frames)
            if not frames or not 24000 < samples < 45 * 24000:
                raise ValueError("Invalid audio duration")
            peak = max(float(np.max(np.abs(frame.to_ndarray()))) for frame in frames)
            if peak < 0.001 or not np.isfinite(peak):
                raise ValueError("Silent or invalid asset")
        activity = clip["activity_id"]
        text = data["activities"][activity][clip["step"]][clip["language"]]
        if clip["text_sha256"] != hashlib.sha256(text.encode()).hexdigest():
            raise ValueError("Caption/audio provenance mismatch")
    return {"clips": len(manifest["clips"]), "bytes": sum((OUTPUT / name).stat().st_size for name in expected), "source": manifest["generator"], "human_reviewed": False}


def build() -> dict:
    data = catalog()
    synth = Synthesizer()
    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "version": 1, "generator": f"eSpeak NG {synth.version}; espeakng-loader 0.2.4",
        "generator_license": "GPL-3.0-or-later (build tool only)",
        "source_url": "https://github.com/espeak-ng/espeak-ng",
        "synthetic_voice": True, "human_reviewed": False,
        "source_sha256": hashlib.sha256(SOURCE.read_bytes()).hexdigest(), "clips": [],
    }
    for activity, steps in data["activities"].items():
        for language in ("en", "ur"):
            for index, step in enumerate(steps):
                name = f"{language}_{activity}_{index}.m4a"
                audio = synth.speak(step[language], language)
                write_aac(OUTPUT / name, audio, synth.rate)
                manifest["clips"].append({
                    "file": name, "activity_id": activity, "language": language, "step": index,
                    "seconds": round(audio.size / synth.rate, 3),
                    "sha256": hashlib.sha256((OUTPUT / name).read_bytes()).hexdigest(),
                    "text_sha256": hashlib.sha256(step[language].encode()).hexdigest(),
                })
    (OUTPUT / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return verify()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--verify", action="store_true", help="Verify shipped assets; do not synthesize")
    args = parser.parse_args()
    print(json.dumps(verify() if args.verify else build(), ensure_ascii=False))
