import importlib.util
from pathlib import Path


def _builder():
    path = Path(__file__).resolve().parents[1] / "scripts" / "meditation_audio.py"
    spec = importlib.util.spec_from_file_location("meditation_audio_build", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_complete_bilingual_catalog_and_real_decodable_bundled_audio():
    result = _builder().verify()
    assert result["clips"] == 24
    assert 0 < result["bytes"] < 3_000_000
    assert result["human_reviewed"] is False


def test_caption_audio_provenance_and_synthetic_voice_disclosure():
    import json

    builder = _builder()
    manifest = json.loads((builder.OUTPUT / "manifest.json").read_text(encoding="utf-8"))
    assert manifest["synthetic_voice"] is True
    assert "eSpeak NG 1.52.0" in manifest["generator"]
    assert all(1 < clip["seconds"] < 45 for clip in manifest["clips"])
    assert len({clip["file"] for clip in manifest["clips"]}) == 24
