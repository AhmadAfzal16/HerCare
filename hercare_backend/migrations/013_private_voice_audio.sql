-- Store short voice journals encrypted in PostgreSQL so basic voice notes do
-- not depend on an external object store or speech-to-text subscription.
ALTER TABLE journal_entries
  ADD COLUMN IF NOT EXISTS voice_audio_encrypted BYTEA;

DO $$
DECLARE old_constraint TEXT;
BEGIN
  SELECT conname INTO old_constraint
  FROM pg_constraint
  WHERE conrelid = 'journal_entries'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%content_encrypted%'
    AND pg_get_constraintdef(oid) LIKE '%voice_object_key%'
  LIMIT 1;
  IF old_constraint IS NOT NULL THEN
    EXECUTE format('ALTER TABLE journal_entries DROP CONSTRAINT %I', old_constraint);
  END IF;
END $$;

ALTER TABLE journal_entries
  ADD CONSTRAINT journal_entries_payload_check CHECK (
    (entry_type = 'text' AND content_encrypted IS NOT NULL) OR
    (entry_type = 'voice' AND
      (voice_object_key IS NOT NULL OR voice_audio_encrypted IS NOT NULL))
  );
