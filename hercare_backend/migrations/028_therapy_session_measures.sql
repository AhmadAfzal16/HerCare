-- M9 monitoring: optional measures around a breathing/meditation session.
-- Tension 0-10 asked before and after, a "did anything feel distressing?" answer, and a short
-- heart reading before/after (heart rate in bpm, HRV as RMSSD in ms) from the phone camera or a
-- Bluetooth band. Summaries only; raw camera frames and beat-by-beat data never leave the phone.
ALTER TABLE therapeutic_sessions
  ADD COLUMN IF NOT EXISTS tension_before SMALLINT CHECK (tension_before BETWEEN 0 AND 10),
  ADD COLUMN IF NOT EXISTS tension_after SMALLINT CHECK (tension_after BETWEEN 0 AND 10),
  ADD COLUMN IF NOT EXISTS distress_reported BOOLEAN,
  ADD COLUMN IF NOT EXISTS hr_before SMALLINT CHECK (hr_before BETWEEN 35 AND 220),
  ADD COLUMN IF NOT EXISTS hr_after SMALLINT CHECK (hr_after BETWEEN 35 AND 220),
  ADD COLUMN IF NOT EXISTS hrv_before SMALLINT CHECK (hrv_before BETWEEN 1 AND 300),
  ADD COLUMN IF NOT EXISTS hrv_after SMALLINT CHECK (hrv_after BETWEEN 1 AND 300),
  ADD COLUMN IF NOT EXISTS physio_source VARCHAR(8) CHECK (physio_source IN ('camera', 'band'));
ALTER TABLE therapeutic_sessions DROP CONSTRAINT IF EXISTS therapeutic_sessions_physio_source_required;
ALTER TABLE therapeutic_sessions ADD CONSTRAINT therapeutic_sessions_physio_source_required CHECK (
  (hr_before IS NULL AND hr_after IS NULL AND hrv_before IS NULL AND hrv_after IS NULL) OR physio_source IS NOT NULL);
CREATE INDEX IF NOT EXISTS idx_therapeutic_sessions_distress
  ON therapeutic_sessions(mother_id, completed_at DESC) WHERE distress_reported;
