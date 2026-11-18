# M5 — private voice transcription and journal analysis

Implemented and headlessly verified 2026-10-11. No app/device or persistent
server was launched/restarted. No real user recording was processed, exported
or used for training; research collection remains off.

## Working flow

1. Record up to60 seconds or import WAV/M4A/MP3 (up to4MB). Save the encrypted
   original first. The existing100MB/mother audio quota is unchanged.
2. Tap **Transcribe / review**, then **Create private transcript**. This is optional
   and explicit; existing recordings are not silently enrolled.
3. A durable database job sends bytes to your own authenticated ML service.
   Server-only multilingual Whisper-small produces an editable draft. No
   third-party speech provider receives the recording.
4. Listen to the original if needed, correct misheard words and confirm once.
   Confirmed words use the same encrypted storage, blind-index search and
   rule-first sentiment/distress/safety pipeline as typed journals.
5. Confirmed danger creates one private crisis event. Guardian alerts require
   the active link, current consent and separate M10 safe-recipient confirmation.
   Alerts never contain the transcript.

Before confirmation, a possible danger cue offers private Immediate Help but
does not create an unverified clinical event, notify a guardian or enter ordinary
journal scores/search. Cancelling removes the pending/draft transcription, not
the audio. Deleting a journal cascades its job; old callbacks cannot recreate it
or overwrite a newer request.

## Scope and scoring boundaries

Daily emoji mood, optional energy/sleep/support, self-report composite, history,
trends, calendar summaries, private text, imports, playback, search and authorized
report aggregation are retained. This closes the missing encrypted-voice → text
→ NLP/safety path.

The existing composite remains a normalized weighted average of **provided
self-report observations** (mood .4; three other observations .2 each). Confirmed
typed/transcribed NLP supplies separate sentiment/distress signals. It is not
silently blended into that score or a clinical model: the proposal does not
validate an NLP-to-mood numerical formula. Acoustic emotion, depression diagnosis
and a clinically validated all-modality fusion model are not delivered by ASR.
M4 baseline/future-model limitations are unchanged.

English/Urdu transcription follows the recorded app language. Roman Urdu typed
or corrected text uses existing journal analysis; spoken Urdu normally produces
Urdu script, not promised Roman Urdu transliteration.

## Implementation and limits

- Backend: transcription.client.js (bounded private ASR), transcription.service.js
  (owned/versioned state/confirmation), transcription.worker.js (durable queue).
- Python: app/voice_transcription.py, requirements-voice.txt, scripts/voice_download.py,
  voice.env.example. Flutter: VoiceTranscript, VoiceTranscriptScreen,
  JournalAccountGuard and account-bound MoodProvider/MoodService.
- Migration020 only creates transcription jobs/state/index. Existing notes are
  preserved and not opted in. Local migration is applied; never edit001–020.
- Statuses: queued → processing → review → confirmed; failed/no-speech explicit.
  Three-minute leases and SKIP LOCKED claims; three attempts with backoff;
  expired final leases fail. Maximum three pending jobs/mother and20 requests/hour.
- Draft AES-GCM binds mother and journal. Confirmation revision/client UUID/keyed
  fingerprint prevent stale overwrites/replays. Original audio remains encrypted.
- Active role/basic consent are checked before and after inference. Revocation
  cannot recall bytes already sent to your own service, but prevents late results
  being persisted after the post-inference check fails.
- TLS except loopback; production internal ML_SERVICE_TOKEN; no redirects.
  Input4MB, response40KB, draft5000 characters; no audio/transcript logs.
- Decoding stops beyond65 seconds (small60-second recorder/container tolerance).
  CPU int8, two default threads, one ASR inference, VAD/low-confidence filtering.
  Recognition failure is unknown, not neutral mood or a negative safety result.
- All M5 routes use no-store, active mother/Tier1 checks, X-Mood-Account-Id and
  private-body redaction. Foreign check-in IDs cannot attach another user's data.
- Auth changes clear provider state/discard late results. Native encrypted
  check-in/text queues bind owner/API, retain UUIDs, serialize writes/coalesce sync
  and acknowledge only synced items. Ten-entry cap fails explicitly instead of
  dropping an older entry. Legacy unknown-owner queues are not guessed/replayed.
- Voice/transcription requests are not silently queued by the phone. Import retries
  keep an app-temporary copy/UUID without deleting the user's source file.
  Unsaved recording/import copies are session-only.
- Status polling is foreground-only, every five seconds and bounded to two minutes
  per page opening. Manual refresh/reopening remains available.

## Model and costs

Pretrained MIT-licensed [Systran Whisper-small CTranslate2 conversion](https://huggingface.co/Systran/faster-whisper-small),
not a model trained on mothers' recordings. Pinned revision:
536b0662742c02347bc0e980a01041f333bce120. All four assets SHA256-checked at
provisioning/startup; local-only runtime. Total486,212,372 bytes, ignored by Git
and Docker build context. No ASR weights are added to the APK.

[faster-whisper](https://github.com/SYSTRAN/faster-whisper) supports local CPU int8
and voice-activity filtering. The [Whisper model card](https://github.com/openai/whisper/blob/main/model-card.md)
warns about hallucinations and unequal language performance. Human confirmation
is deliberate. No Urdu WER, postpartum diagnostic accuracy or clinically validated
emergency-monitoring claim is made.

No paid speech API/key is required. CPU/RAM/storage hosting still costs unless a
host provides sufficient free resources. Budget ASR memory alongside the existing
ML/NLP models and benchmark load before choosing a small free-tier instance.

## Deployment

Local migration020, dependencies and public weights are provisioned. New hosts:

1. Run the normal backend migration runner before serving the new backend.
2. Install requirements-voice.txt; run python scripts/voice_download.py during
   provisioning, never during an inference request.
3. Inject the stable journal encryption key and private ML secret from deployment
   secrets. Configure backend ML_SERVICE_URL to your own ML endpoint with TLS or
   same-network-namespace loopback. Secrets do not belong in Flutter.
4. Mount weights read-only at /app/artifacts/voice/small in Docker or configure
   VOICE_MODEL_PATH. Docker installs libraries, not weights. VOICE_CPU_THREADS
   defaults2; VOICE_ASR_ENABLED/VOICE_WORKER_ENABLED can disable ASR/worker.
   Original storage/playback still works.
5. Deploy/restart backend/ML and rebuild Flutter when the user chooses to run it.
   No Firebase project change or Google Speech credentials are needed.
6. Stage English/Urdu/noisy/silent/long clips, backgrounding, accounts/consent,
   restarts and safe-guardian delivery. Review Urdu and clinical wording.

## Verified

- Flutter144, Python157 and backend86 default tests passed (15 backend optional
  skipped by default). Full analysis/lint and pip compatibility check clean.
- Separately enabled M5/M2/M3/M7/M9/M10/research rollback suite9 tests passed.
  Fixtures synthetic; all changes rolled back; ASR/messaging mocked.
- Actual weights loaded. Artificial English speech transcribed exactly:
  “Today I feel calm. My family is helping me.” in4.62 seconds in one temporary
  process, using scripts/voice_smoke.ps1, without playback. This is a smoke test,
  not accuracy, Urdu validation or production p95.
- English/Urdu320×480/200%-text and keyboard layouts showed no tested overflow.
  Retry corrections/UUID, denial, account switches and production provider updates
  are covered.

No app/device/persistent service start, APK build/install, real guardian push,
call, private export or model retraining. Previously audited unrelated
security/privacy defects still need separate work; M5 verification does not
certify the whole application for healthcare deployment.
