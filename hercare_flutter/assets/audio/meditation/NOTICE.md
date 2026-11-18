# HerCare meditation audio

The 24 bundled mono AAC/M4A files speak original HerCare guidance in English and Urdu.
They are synthetic, not recordings of a therapist, real mother, or identifiable speaker.
Captions and audio share `assets/meditation_guides.json`. No user data was used.

Generated locally with eSpeak NG 1.52.0 via espeakng-loader 0.2.4. The generation
tool is GPL-3.0-or-later; the Python loader wrapper is MIT. Neither engine,
dictionary nor native speech library is distributed in the Flutter app.
Source and generator license: https://github.com/espeak-ng/espeak-ng
Loader source/license: https://github.com/thewh1teagle/espeakng-loader

Generation settings: 125 words/minute, volume80, language voices `en` and `ur`.
Compression: mono AAC40kbps at24kHz in M4A; speech cues have quiet gaps between
them in the timed session, not hours of stored silence. `manifest.json` records
per-file checksums/durations and matching text checksums.

Human Urdu pronunciation review, clinician guidance review and physical-device
listening checks remain release requirements. Generated speech is intentionally
labelled synthetic in the app. Human narration can replace the individual clips
without shipping a TTS model or changing the session UI; update provenance and
checksums and retain written speaker/distribution permission.
