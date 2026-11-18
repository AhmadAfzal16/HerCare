ALTER TABLE therapeutic_sessions ADD COLUMN breathing_participation VARCHAR(20)
  CHECK (breathing_participation IS NULL OR
    (activity_type = 'breathing' AND breathing_participation IN
      ('most_cues', 'some_cues', 'stopped_early')));
