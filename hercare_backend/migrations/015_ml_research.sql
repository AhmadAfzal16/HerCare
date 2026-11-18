-- Optional exact model context and prospective opt-in research capture.
-- No existing users are opted in. No journal/chat/audio content is captured.
CREATE TABLE risk_context (
  mother_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  number_of_children SMALLINT CHECK (number_of_children BETWEEN 0 AND 20),
  basic_needs_affordable BOOLEAN,
  mother_in_law_relationship VARCHAR(10) CHECK (mother_in_law_relationship IN ('poor','moderate','good')),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE research_consents (
  mother_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  enabled BOOLEAN NOT NULL DEFAULT FALSE,
  policy_version VARCHAR(30) NOT NULL,
  study_id VARCHAR(100),
  timezone VARCHAR(50) NOT NULL DEFAULT 'Asia/Karachi',
  granted_at TIMESTAMPTZ,
  revoked_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE TABLE research_observations (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  mother_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_type VARCHAR(15) NOT NULL CHECK (source_type IN ('mood','sleep','telemetry','screening','therapy','profile','risk_context','text_signal','prediction')),
  source_id UUID NOT NULL,
  local_date DATE,
  occurred_at TIMESTAMPTZ NOT NULL,
  available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  policy_version VARCHAR(30) NOT NULL,
  payload JSONB NOT NULL,
  CHECK (jsonb_typeof(payload) = 'object')
);
CREATE INDEX idx_research_observations_mother_available ON research_observations(mother_id, available_at, id);
CREATE TABLE research_export_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id UUID REFERENCES users(id) ON DELETE SET NULL,
  purpose VARCHAR(30) NOT NULL CHECK (purpose IN ('fyp_model_development','external_validation')),
  participant_count INTEGER NOT NULL,
  observation_count INTEGER NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE journal_entries ADD COLUMN analysis_metadata JSONB NOT NULL DEFAULT '{}'::jsonb;
ALTER TABLE chat_messages ADD COLUMN analysis_metadata JSONB NOT NULL DEFAULT '{}'::jsonb;

CREATE FUNCTION capture_research_observation() RETURNS TRIGGER AS $$
DECLARE owner_id UUID; source UUID; kind TEXT; observed DATE; occurred TIMESTAMPTZ;
        data JSONB; consent research_consents%ROWTYPE;
BEGIN
  IF TG_TABLE_NAME = 'onboarding_data' THEN owner_id := NEW.user_id;
  ELSE owner_id := NEW.mother_id; END IF;
  -- Serialize consent withdrawal with capture. Revocation deletes research copies.
  SELECT * INTO consent FROM research_consents WHERE mother_id = owner_id FOR SHARE;
  IF NOT FOUND OR NOT consent.enabled THEN RETURN NEW; END IF;
  IF NOT EXISTS (SELECT 1 FROM users u JOIN onboarding_data o ON o.user_id=u.id
      WHERE u.id=owner_id AND u.is_active AND u.role='mother' AND o.consent_tier1
        AND o.age >= 18 AND o.months_since_birth BETWEEN 0 AND 12) THEN RETURN NEW; END IF;
  IF TG_TABLE_NAME = 'risk_context' THEN source := NEW.mother_id;
  ELSE source := NEW.id; END IF;
  occurred := NOW();
  CASE TG_TABLE_NAME
    WHEN 'mood_checkins' THEN
      kind := 'mood'; observed := NEW.entry_date;
      data := jsonb_build_object('mood_rating',NEW.mood_rating,'energy_level',NEW.energy_level,
        'sleep_quality',NEW.sleep_quality,'social_support',NEW.social_support);
    WHEN 'sleep_records' THEN
      kind := 'sleep'; observed := NEW.sleep_date;
      data := jsonb_build_object('sleep_minutes',EXTRACT(EPOCH FROM (NEW.wake_time-NEW.bedtime))/60-NEW.awake_minutes,
        'sleep_awakenings',NEW.awakenings,'sleep_quality',NEW.quality,'timezone_offset_minutes',NEW.timezone_offset_minutes);
    WHEN 'device_telemetry_daily' THEN
      IF NOT EXISTS (SELECT 1 FROM onboarding_data WHERE user_id=owner_id AND consent_tier3) THEN RETURN NEW; END IF;
      kind := 'telemetry'; observed := NEW.local_date;
      data := jsonb_build_object('usage_permission',NEW.usage_access,'notification_permission',NEW.notification_access,
        'screen_minutes',CASE WHEN NEW.usage_access THEN NEW.screen_time_minutes ELSE NULL END,
        'social_minutes',CASE WHEN NEW.usage_access THEN NEW.social_minutes ELSE NULL END,
        'late_night_minutes',CASE WHEN NEW.usage_access THEN NEW.late_night_minutes ELSE NULL END,
        'notification_analyzed_count',CASE WHEN NEW.notification_access THEN NEW.message_notifications ELSE NULL END,
        'notification_negative_count',CASE WHEN NEW.notification_access THEN NEW.negative_notifications ELSE NULL END,
        'distress_notification_count',CASE WHEN NEW.notification_access THEN NEW.distress_notifications ELSE NULL END,
        'abuse_notification_count',CASE WHEN NEW.notification_access THEN NEW.abuse_notifications ELSE NULL END,
        'analysis_version',NEW.analysis_version);
    WHEN 'screening_assessments' THEN
      IF NEW.status <> 'completed' THEN RETURN NEW; END IF;
      kind := 'screening'; occurred := NEW.completed_at;
      data := jsonb_build_object('instrument',NEW.instrument_type,'version',NEW.instrument_version,
        'language',NEW.language,'score',NEW.total_score,'safety_positive',NEW.self_harm_positive);
    WHEN 'therapeutic_sessions' THEN
      kind := 'therapy'; occurred := NEW.completed_at;
      observed := (NEW.completed_at AT TIME ZONE consent.timezone)::date;
      data := jsonb_build_object('activity_type',NEW.activity_type,'duration_seconds',NEW.duration_seconds,
        'completed',NEW.completed,'mood_before',NEW.mood_before,'mood_after',NEW.mood_after,
        'before_rating_timing','retrospective_unverified');
    WHEN 'onboarding_data' THEN
      kind := 'profile';
      data := jsonb_build_object('age',NEW.age,'education_level',NEW.education_level,'household_type',NEW.household_type,
        'postpartum_months_self_reported',NEW.months_since_birth,'previous_deliveries',NEW.parity,
        'cesarean',CASE WHEN NEW.delivery_method IS NULL THEN NULL ELSE (NEW.delivery_method='cesarean')::int END,
        'baby_female',CASE WHEN NEW.baby_gender IS NULL THEN NULL ELSE (NEW.baby_gender='female')::int END,
        'complication_confirmation','not_collected');
    WHEN 'risk_context' THEN
      kind := 'risk_context';
      data := jsonb_build_object('number_of_children',NEW.number_of_children,
        'basic_needs_affordable',NEW.basic_needs_affordable,'mother_in_law_relationship',NEW.mother_in_law_relationship);
    WHEN 'journal_entries' THEN
      IF NEW.sentiment_score IS NULL THEN RETURN NEW; END IF;
      kind := 'text_signal'; observed := (NOW() AT TIME ZONE consent.timezone)::date;
      data := jsonb_build_object('sentiment_score',NEW.sentiment_score,'distress_score',NEW.distress_score,
        'safety_positive',NEW.contains_danger,'analysis_version',NEW.analysis_version,
        'sentiment_source',NEW.analysis_metadata->>'sentiment_source','model_status',NEW.analysis_metadata->>'model_status');
    WHEN 'risk_predictions' THEN
      kind := 'prediction'; occurred := NEW.generated_at;
      data := jsonb_build_object('probability',NEW.depression_probability,'model_scope',NEW.model_scope,
        'model_version',NEW.model_version,'data_completeness',NEW.data_completeness,
        'validation_status',NEW.input_summary->>'validation_status');
    ELSE RETURN NEW;
  END CASE;
  IF (observed IS NOT NULL AND observed < (consent.granted_at AT TIME ZONE consent.timezone)::date)
     OR occurred < consent.granted_at THEN RETURN NEW; END IF;
  INSERT INTO research_observations(mother_id,source_type,source_id,local_date,occurred_at,policy_version,payload)
    VALUES(owner_id,kind,source,observed,occurred,consent.policy_version,data);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER research_mood AFTER INSERT OR UPDATE ON mood_checkins FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_sleep AFTER INSERT OR UPDATE ON sleep_records FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_telemetry AFTER INSERT OR UPDATE ON device_telemetry_daily FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_screening AFTER INSERT OR UPDATE ON screening_assessments FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_therapy AFTER INSERT OR UPDATE ON therapeutic_sessions FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_profile AFTER INSERT OR UPDATE ON onboarding_data FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_context AFTER INSERT OR UPDATE ON risk_context FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_text_signal AFTER INSERT OR UPDATE ON journal_entries FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
CREATE TRIGGER research_prediction AFTER INSERT ON risk_predictions FOR EACH ROW EXECUTE FUNCTION capture_research_observation();
