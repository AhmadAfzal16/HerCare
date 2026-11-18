const { AppError } = require('../../middleware/error_handler');
const { analyzeJournal } = require('../mood/journal_analysis');
const POLICY_VERSION = 'chatbot-aggregate-v1';
const LANGUAGES = ['en', 'ur', 'roman_ur'];
const ACTIONS = ['tests', 'mood', 'journal', 'breathing', 'grounding', 'guardian', 'crisis'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function object(body, allowed) {
  if (!body || typeof body !== 'object' || Array.isArray(body) || Object.keys(body).some((field) => !allowed.includes(field))) {
    throw new AppError('Invalid chatbot request fields.', 422);
  }
}
function language(value) {
  if (!LANGUAGES.includes(value)) throw new AppError('Choose English, Urdu or Roman Urdu.', 422);
  return value;
}
function id(value) {
  if (typeof value !== 'string' || !UUID.test(value)) throw new AppError('Invalid conversation identifier.', 422);
  return value;
}
function session(body) { object(body, ['language']); return { language: language(body.language) }; }
function message(body) {
  object(body, ['message', 'language', 'client_request_id']);
  if (typeof body.message !== 'string' || !body.message.trim() || body.message.length > 4000
      || Array.from(body.message).some((character) => character.codePointAt(0) < 32 && ![9, 10, 13].includes(character.codePointAt(0)))) {
    throw new AppError('Write a message of 1 to 4,000 characters.', 422);
  }
  return { message: body.message.trim(), language: language(body.language), client_request_id: id(body.client_request_id) };
}
function consent(body) {
  object(body, ['enabled', 'policy_version']);
  if (typeof body.enabled !== 'boolean' || body.policy_version !== POLICY_VERSION) throw new AppError('Confirm the current personalization consent policy.', 422);
  return { enabled: body.enabled };
}
function pagination(query, max = 30) {
  object(query, ['limit', 'before']);
  const limit = query.limit === undefined ? Math.min(30, max) : Number(query.limit);
  if (!Number.isInteger(limit) || limit < 1 || limit > max) throw new AppError('Invalid page size.', 422);
  let before = null;
  if (query.before !== undefined) {
    try {
      if (typeof query.before !== 'string' || query.before.length > 300) throw new Error('cursor');
      before = /T/.test(query.before) && Number.isFinite(Date.parse(query.before))
        ? { created_at: query.before, id: '00000000-0000-0000-0000-000000000000' }
        : JSON.parse(Buffer.from(query.before, 'base64url').toString('utf8'));
      if (!before || typeof before.created_at !== 'string' || !/^\d{4}-\d{2}-\d{2}T/.test(before.created_at)
          || !Number.isFinite(Date.parse(before.created_at)) || typeof before.id !== 'string'
          || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(before.id)) throw new Error('cursor');
      if (before.ordinal !== undefined && (!/^\d{1,19}$/.test(String(before.ordinal))
          || BigInt(before.ordinal) > 9223372036854775807n)) throw new Error('cursor');
    } catch { throw new AppError('Invalid conversation time cursor.', 422); }
  }
  return { limit, before };
}
function cursor(row) { return row ? Buffer.from(JSON.stringify({ created_at: new Date(row.created_at).toISOString(), id: row.id,
  ...(row.ordinal ? { ordinal: String(row.ordinal) } : {}) })).toString('base64url') : null; }
function inspectSafety(content) {
  const text = content.normalize('NFKC').toLowerCase();
  const base = analyzeJournal(text).containsDanger;
  const infant = /\b(?:kill|hurt|harm|shake|smother)\s+(?:my\s+|the\s+)?(?:baby|infant|child)\b/i.test(text)
    || /(?:بچے|بچی|بچہ)\s*(?:کو)?\s*(?:مار|نقصان|قتل)/u.test(text)
    || /\b(?:bache|bachay|bacha|baby)\s*(?:ko)?\s*(?:marna|maarna|nuqsan|nuksan)\b/i.test(text);
  const voices = /\b(?:voices?|someone)\s+(?:are\s+|is\s+)?(?:telling|tells|ordering)\s+me\s+to\s+(?:hurt|kill|harm)\b/i.test(text)
    || /(?:آوازیں|آواز)\s*.*(?:مارنے|نقصان|قتل)/u.test(text)
    || /\bawaz(?:ein|en)?\b.*\b(?:marne|nuqsan|nuksan)\b/i.test(text);
  const severeConfusion = /\b(?:hearing voices|seeing things|very confused|severely confused|cannot tell what is real)\b/i.test(text)
    || /(?:آوازیں سن|حقیقت سمجھ نہیں|شدید الجھن)/u.test(text)
    || /\b(?:awazein sun|awazen sun|bohat uljhan|haqeeqat samajh nahi)\b/i.test(text);
  const urgentPills = /\bi\s+(?:will overdose|am overdosing|(?:took|have taken|will take|plan to take|want to take)\s+(?:too many|all|an overdose of)\s+(?:pills|tablets|medicine))\b/i.test(text)
    || /(?:میں\s*(?:نے)?\s*(?:بہت|زیادہ|ساری).*گولیاں|میں\s*.*اوورڈوز)/u.test(text)
    || /\b(?:main|mein)\s+(?:ne\s+)?(?:bohat|bahut|ziada|zyada|sari).*\b(?:goliyan|goliyaan|pills)\b/i.test(text);
  const negated = /\b(?:not|never|don't|do not)\s+(?:want\s+to\s+|going\s+to\s+|intend\s+to\s+)?(?:kill|hurt|harm|shake|smother)\b/i.test(text)
    || /(?:نہیں|نہ)\s*(?:چاہتی|چاہتا|کروں)/u.test(text)
    || /\b(?:nahi|nahin|naheen)\b/i.test(text);
  const educational = /\b(?:what is|explain|research|definition|article|my friend|someone else)\b/i.test(text)
    && !/\b(?:i am|i'm|i want|i will|i might|telling me)\b/i.test(text);
  const abuse = /\b(?:abuse|abusive|violent|violence|hits me|beats me|beat me|beating|afraid of my husband|scared of my husband)\b/i.test(text)
    || /(?:تشدد|شوہر سے ڈر|مارتا ہے|مجھے مار|مجھے مارتا)/u.test(text)
    || /\b(?:mujhe|mujhay|mujhey)\s+(?:marta|maarta|mara|maara|peeta|peetta)|\b(?:shohar|husband)\b.*\b(?:dar|khauf|tashaddud)\b/i.test(text);
  const refusesSharing = /\b(?:do not|don't|never)\s+(?:notify|tell|contact|inform|alert)\b|\b(?:do not|don't)\s+want\b.*\b(?:notified|told|contacted|informed|alerted)\b/i.test(text)
    || /(?:بتانا نہیں|نہ بتا|اطلاع نہ|رابطہ نہ)/u.test(text)
    || /\b(?:mat bata(?:na|o)?|nahi batana|na batana|rabta na|notify mat)\b/i.test(text);
  // Automatic sharing is restricted to explicit personal self-harm language.
  // Infant intrusive thoughts, quoted/negated language and abuse need confidential help,
  // not an automatic disclosure to a potentially unsafe guardian.
  const explicitPersonal = /\b(?:i\s+(?:want to|will|might|plan to|am going to)\s+(?:kill|hurt|harm)\s+myself|i(?:'m| am)\s+suicidal|i\s+(?:do not|don't)\s+want to live|end my life)\b/i.test(text)
    || /(?:میں\s*.*(?:خود کو نقصان|خودکشی|خود کشی)|جینا نہیں چاہتی|زندہ نہیں رہنا)/u.test(text)
    || /\b(?:main|mein)\s+.*\b(?:khudkushi|khud kushi|apne aap ko nuqsan|marna chahti)\b/i.test(text);
  const suicidalNegation = /\b(?:not|never)\s+suicidal\b/i.test(text);
  const physical = /cannot breathe|can.t breathe|baby (?:isn.t|is not) breathing|severe chest pain|heavy bleeding/i.test(text)
    || /بہت خون|سانس نہیں/u.test(text) || /saans nahi|bohat khoon/i.test(text);
  return { requires_help: base || infant || voices || severeConfusion || urgentPills || abuse || physical,
    alert_worthy: ((base && explicitPersonal) || urgentPills) && !infant && !voices && !severeConfusion
      && !negated && !suicidalNegation && !educational && !abuse && !refusesSharing,
    reason: urgentPills ? 'urgent_medical_safety_concern' : (voices || severeConfusion) ? 'urgent_safety_concern'
      : infant ? 'infant_safety_concern' : base ? 'self_harm_language' : null,
    rule_version: 'chatbot-safety-1.0' };
}
function fallback(lang, safety = null) {
  const help = safety?.requires_help === true;
  const texts = {
    en: help ? 'Your safety and your baby’s safety matter. If anyone may be in immediate danger, contact local emergency services or go to the nearest emergency department now. Ask a trusted person to stay with you and keep the baby safely with another trusted adult. I cannot assess or diagnose an emergency. Please contact a qualified clinician urgently. Are you safe right now?' : 'Hum-Raaz’s server is unavailable right now. Your message is saved, but an AI response was not generated. You can retry when connected. If you need urgent help, contact a trusted person or local emergency services.',
    ur: help ? 'آپ کی اور آپ کے بچے کی حفاظت اہم ہے۔ اگر فوری خطرہ ہو تو مقامی ایمرجنسی سروس یا قریبی ہسپتال سے ابھی رابطہ کریں۔ کسی قابلِ اعتماد شخص کو اپنے ساتھ رہنے دیں اور بچے کو محفوظ طور پر کسی دوسرے قابلِ اعتماد بالغ کے پاس رکھیں۔ میں ایمرجنسی کی تشخیص نہیں کر سکتی۔ فوراً کسی مستند طبی ماہر سے رابطہ کریں۔ کیا آپ ابھی محفوظ ہیں؟' : 'ہم راز کا سرور اس وقت دستیاب نہیں ہے۔ آپ کا پیغام محفوظ ہے مگر AI کا جواب نہیں بنا۔ رابطہ بحال ہونے پر دوبارہ کوشش کریں۔ فوری مدد کے لیے قابلِ اعتماد شخص یا مقامی ایمرجنسی سروس سے رابطہ کریں۔',
    roman_ur: help ? 'Aap ki aur aap ke bachay ki hifazat aham hai. Agar kisi ko foran khatra ho to local emergency service ya qareebi hospital se abhi rabta karein. Kisi bharosaymand shakhs ko apne saath bulayein aur bachay ko doosray bharosaymand adult ke paas mehfooz rakhein. Main emergency ki tashkhees nahi kar sakti. Foran qualified clinician se rabta karein. Kya aap abhi mehfooz hain?' : 'Hum-Raaz ka server abhi dastiyab nahi. Aap ka paigham mehfooz hai lekin AI jawab generate nahi hua. Connection anay par dobara koshish karein. Fori madad ke liye bharosaymand shakhs ya local emergency service se rabta karein.',
  };
  return { reply: texts[lang], language: lang, mode: help ? 'safety' : 'unavailable', sources: [], actions: help ? ['crisis', 'guardian'] : [],
    safety: { requires_help: help, guardian_alert_allowed: false, reason: safety?.reason || null },
    state: help ? { topic: 'safety', cbt_step: 0 } : {}, model_version: help ? 'chatbot-safety-1.0' : 'unavailable', clinical_validation: false };
}
function privacyFallback(language) {
  const value = fallback(language);
  value.reply = { en: 'Your personalization choice changed while this response was being prepared. That response was discarded. Your message is saved; retry it to continue without the withdrawn score context.',
    ur: 'جواب تیار ہوتے وقت آپ کی ذاتی اسکور استعمال کرنے کی اجازت بدل گئی۔ وہ جواب حذف کر دیا گیا۔ پیغام محفوظ ہے؛ واپس لی گئی اجازت والے اسکور کے بغیر دوبارہ کوشش کریں۔',
    roman_ur: 'Jawab tayyar hotay waqt aap ki personal scores ki ijazat badal gayi. Woh jawab discard kar diya gaya. Paigham mehfooz hai; wapas li gayi ijazat walay scores ke baghair dobara koshish karein.' }[language];
  value.safety.reason = 'personalization_consent_changed';
  return value;
}
module.exports = { POLICY_VERSION, LANGUAGES, ACTIONS, language, id, session, message, consent, pagination, cursor, inspectSafety, fallback, privacyFallback };
