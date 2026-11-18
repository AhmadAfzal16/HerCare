-- A daily check-in needs only a mood rating. Extra observations are optional.
ALTER TABLE mood_checkins
  ALTER COLUMN energy_level DROP NOT NULL,
  ALTER COLUMN sleep_quality DROP NOT NULL,
  ALTER COLUMN social_support DROP NOT NULL;
