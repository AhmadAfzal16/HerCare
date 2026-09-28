CREATE TABLE IF NOT EXISTS sleep_records (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  mother_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  sleep_date DATE NOT NULL,
  bedtime TIMESTAMPTZ NOT NULL,
  wake_time TIMESTAMPTZ NOT NULL,
  awake_minutes INTEGER NOT NULL CHECK (awake_minutes BETWEEN 0 AND 1439),
  quality SMALLINT NOT NULL CHECK (quality BETWEEN 1 AND 5),
  awakenings SMALLINT NOT NULL CHECK (awakenings BETWEEN 0 AND 50),
  timezone_offset_minutes INTEGER NOT NULL CHECK (timezone_offset_minutes BETWEEN -840 AND 840),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (mother_id, sleep_date),
  CHECK (wake_time > bedtime AND wake_time <= bedtime + INTERVAL '24 hours'),
  CHECK (EXTRACT(EPOCH FROM (wake_time - bedtime)) / 60 > awake_minutes)
);
