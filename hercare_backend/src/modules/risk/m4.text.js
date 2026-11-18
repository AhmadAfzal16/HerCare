const VERSION = 'personal-distress-phrases-v1';

// Deliberately narrow signals. Exclude sleep and fatigue, which already have
// their own measurements. Safety is handled by the existing source module.
const personalDistress = [
  /^(?:today,? )?(?:i (?:feel|am) |i'm )(?:very |so |really )?(?:sad|hopeless|alone|worthless|overwhelmed)(?=$|[\s,.!?])/u,
  /^(?:aaj )?(?:main |mein |mujhe )(?:bohat |bahut |bohut )?(?:udas|udaas|mayoos|akeli|pareshan)(?=$|[\s,.!?])/u,
  /^(?:آج )?(?:میں |مجھے )(?:بہت )?(?:اداس|مایوس|اکیلی|پریشان)(?=$|[\s،۔!?])/u,
];
const ambiguity = /\b(?:not|never|no longer|anymore|used to|said|says|quote|if|example|nahi|nahin|nhi|pehle)\b|نہیں|پہلے|مثال|کہا|[?؟]/u;

function hasDistress(text) {
  const normalized = text.normalize('NFKC').toLowerCase().replace(/[’]/gu, "'").trim();
  if (/["“”‘]/u.test(normalized)) return false;
  const sentences = normalized.split(/(?<=[.!?۔؟])\s+|[\r\n]+/u);
  return sentences.some((sentence) => !ambiguity.test(sentence) &&
    personalDistress.some((pattern) => pattern.test(sentence.trim())));
}

async function capture(client, motherId, source, id, words, safety) {
  if (safety) return;
  const journal = source === 'journal';
  // Lock the grant through insertion so withdrawal can also erase an in-flight signal.
  const permission = await client.query(`SELECT 1 FROM m4_text_consents c
    JOIN onboarding_data o ON o.user_id=c.mother_id
    JOIN users u ON u.id=c.mother_id
    WHERE c.mother_id=$1 AND c.enabled AND o.consent_tier1 AND u.is_active
    FOR SHARE OF c`, [motherId]);
  if (!permission.rows.length) return;
  const timestamp = journal
    ? `SELECT CASE WHEN j.entry_type='voice' THEN v.confirmed_at ELSE j.created_at END AS recorded_at
       FROM journal_entries j LEFT JOIN journal_voice_transcriptions v ON v.journal_id=j.id
       WHERE j.id=$2 AND j.mother_id=$1`
    : `SELECT t.created_at AS recorded_at FROM chatbot_turns t
       JOIN chatbot_sessions s ON s.id=t.session_id WHERE t.request_id=$2 AND t.role='user' AND s.mother_id=$1`;
  await client.query(`INSERT INTO m4_text_signals
    (mother_id,journal_id,chatbot_request_id,recorded_at,distress,rule_version)
    SELECT $1,${journal ? '$2' : 'NULL'},${journal ? 'NULL' : '$2'}, source.recorded_at,$3,$4
    FROM (${timestamp}) source JOIN m4_text_consents c ON c.mother_id=$1
    WHERE c.enabled AND source.recorded_at>=c.granted_at
    ON CONFLICT DO NOTHING`, [motherId, id, hasDistress(words), VERSION]);
}

module.exports = { capture, hasDistress };
