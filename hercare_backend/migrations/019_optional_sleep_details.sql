-- M8: skipped observations remain unknown, not average quality/zero awakenings.
-- Existing measurements, care records and research settings are preserved.
ALTER TABLE sleep_records ALTER COLUMN quality DROP NOT NULL;
ALTER TABLE sleep_records ALTER COLUMN awakenings DROP NOT NULL;
