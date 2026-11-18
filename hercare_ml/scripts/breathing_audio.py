"""Build the eight public breathing cues using the meditation asset tool."""
from pathlib import Path
import wave

from .meditation_audio import Synthesizer


CUES = {
    "en": {"inhale": "Breathe in.", "hold": "Hold gently.",
           "exhale": "Breathe out.", "rest": "Rest."},
    "ur": {"inhale": "سانس اندر لیں۔", "hold": "سانس روکیں۔",
           "exhale": "سانس باہر چھوڑیں۔", "rest": "آرام کریں۔"},
}


def main():
    output = Path(__file__).resolve().parents[2] / "hercare_flutter/assets/audio/breathing"
    output.mkdir(parents=True, exist_ok=True)
    voice = Synthesizer()
    for language, cues in CUES.items():
        for phase, text in cues.items():
            audio = voice.speak(text, language, min_seconds=0.25)
            if audio.size >= 4 * voice.rate:
                raise ValueError(f"Cue exceeds the shortest phase: {language}/{phase}")
            with wave.open(str(output / f"{language}_{phase}.wav"), "wb") as clip:
                clip.setparams((1, 2, voice.rate, 0, "NONE", "not compressed"))
                clip.writeframes(audio.astype("<i2", copy=False).tobytes())


if __name__ == "__main__":
    main()
