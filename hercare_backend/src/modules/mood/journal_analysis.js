const ANALYSIS_VERSION = 'rules-1.0';

const dangerPatterns = [
  /\b(kill|hurt|harm)\s+(myself|me)\b/i,
  /\b(suicid(?:e|al)|end my life|do not want to live|don't want to live)\b/i,
  /\b(mar jana|marna chahti|khudkushi|khud kushi|apne aap ko nuqsan)\b/i,
  /(خود\s*کشی|خود کو نقصان|مر جانا|جینا نہیں چاہتی|زندہ نہیں رہنا)/u,
];

const positiveWords = new Set([
  'happy', 'better', 'calm', 'hope', 'supported', 'good', 'relaxed',
  'خوش', 'بہتر', 'پرسکون', 'امید', 'اچھا',
  'khush', 'behtar', 'sukoon', 'umeed', 'acha',
]);
const negativeWords = new Set([
  'sad', 'alone', 'hopeless', 'anxious', 'scared', 'exhausted', 'angry', 'bad',
  'اداس', 'اکیلی', 'مایوس', 'پریشان', 'خوف', 'تھکی', 'غصہ', 'برا',
  'udas', 'akeli', 'mayoos', 'pareshan', 'dar', 'thaki', 'ghussa', 'bura',
]);

function detectLanguage(text) {
  const urduCount = (text.match(/[\u0600-\u06FF]/gu) || []).length;
  const latinCount = (text.match(/[A-Za-z]/g) || []).length;
  if (urduCount > 0 && latinCount > 0) return 'mixed';
  return urduCount > 0 ? 'ur' : 'en';
}

function analyzeJournal(text) {
  const normalized = text.normalize('NFKC').toLocaleLowerCase('en-US');
  const tokens = normalized
    .replace(/[^\p{L}\p{N}\s]/gu, ' ')
    .split(/\s+/u)
    .filter(Boolean);
  const positive = tokens.filter((word) => positiveWords.has(word)).length;
  const negative = tokens.filter((word) => negativeWords.has(word)).length;
  const denominator = Math.max(positive + negative, 1);
  const sentimentScore = Math.max(-1, Math.min(1, (positive - negative) / denominator));
  const containsDanger = dangerPatterns.some((pattern) => pattern.test(normalized));
  const distressScore = containsDanger
    ? 1
    : Math.max(0, Math.min(1, negative / Math.max(tokens.length * 0.15, 1)));

  return {
    language: detectLanguage(text),
    sentimentLabel: sentimentScore > 0.2
      ? 'positive'
      : sentimentScore < -0.2 ? 'negative' : 'neutral',
    sentimentScore: Number(sentimentScore.toFixed(3)),
    distressScore: Number(distressScore.toFixed(3)),
    containsDanger,
    analysisVersion: ANALYSIS_VERSION,
  };
}

module.exports = { analyzeJournal, detectLanguage, ANALYSIS_VERSION };
