"""Headless verification: decode M10 WAV data without playback or device use."""
import array
import hashlib
import importlib.util
import sys
import wave
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("crisis_audio", PROJECT / "hercare_ml/scripts/crisis_audio.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def test_crisis_assets_are_small_bounded_original_pcm():
    paths = (
        (PROJECT / "hercare_flutter/assets/audio/crisis/support_chime.wav", 8),
        (PROJECT / "hercare_flutter/android/app/src/main/res/raw/hercare_urgent.wav", 2.4),
    )
    for path, seconds in paths:
        with wave.open(str(path), "rb") as reader:
            assert reader.getnchannels() == 1
            assert reader.getsampwidth() == 2
            assert reader.getframerate() == 16000
            assert reader.getnframes() == round(16000 * seconds)
            pcm = array.array("h", reader.readframes(reader.getnframes()))
        if sys.byteorder != "little":
            pcm.byteswap()
        assert 0 < max(abs(sample) for sample in pcm) <= round(.22 * 32767)
        assert pcm[0] == pcm[-1] == 0
        assert path.stat().st_size < 260000


def test_crisis_asset_generator_is_deterministic(tmp_path):
    first = module.build(tmp_path)
    second = module.build(tmp_path)
    assert first == second
    for item in first:
        assert hashlib.sha256((PROJECT / item["path"]).read_bytes()).hexdigest() == item["sha256"]
