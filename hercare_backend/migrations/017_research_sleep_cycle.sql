-- Add clock-time aggregates to future, already consented sleep snapshots only.
-- No historic backfill, opt-in, collection enablement or applied-migration edits.
-- The existing capture trigger owns eligibility/consent/withdrawal rules.
CREATE FUNCTION enrich_research_sleep_cycle() RETURNS TRIGGER AS $$
DECLARE source_record sleep_records%ROWTYPE;
        local_bed TIMESTAMP; local_wake TIMESTAMP;
BEGIN
  IF NEW.source_type <> 'sleep' THEN RETURN NEW; END IF;
  SELECT * INTO source_record FROM sleep_records
    WHERE id=NEW.source_id AND mother_id=NEW.mother_id;
  IF NOT FOUND THEN RETURN NEW; END IF;
  -- Stored offset follows the client convention UTC minus local time.
  -- Explicit UTC conversion makes this independent of DB session timezone.
  local_bed := (source_record.bedtime AT TIME ZONE 'UTC')
    - make_interval(mins => source_record.timezone_offset_minutes);
  local_wake := (source_record.wake_time AT TIME ZONE 'UTC')
    - make_interval(mins => source_record.timezone_offset_minutes);
  NEW.payload := NEW.payload || jsonb_build_object(
    'bedtime_local_minutes', EXTRACT(EPOCH FROM local_bed::time)/60,
    'wake_local_minutes', EXTRACT(EPOCH FROM local_wake::time)/60,
    'sleep_clock_source', 'self_reported_client_offset');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER research_sleep_cycle BEFORE INSERT ON research_observations
  FOR EACH ROW EXECUTE FUNCTION enrich_research_sleep_cycle();
