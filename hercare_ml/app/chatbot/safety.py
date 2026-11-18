"""Conservative multilingual safety cues, not a diagnostic classifier."""
import re
from .retrieval import normalize

PATTERNS = [
    r'\b(?:kill|hurt|harm)\s+(?:myself|my\s+(?:baby|child)|the\s+baby)\b',
    r'\b(?:suicid\w*|end my life|don.t want to live|do not want to live|overdose|took too many pills)\b',
    r'\b(?:shake|smother)\s+(?:my\s+|the\s+)?(?:baby|child)\b',
    r'\b(?:khud\s*kushi|khudkushi|marna chahti|apne aap ko nu[ q]*san|bach[ae]y? ko (?:mar|nuqsan))\b',
    r'(?:خود\s*کشی|خود کو نقصان|جینا نہیں چاہتی|زندہ نہیں رہنا|بچے کو (?:مار|نقصان)|بچی کو (?:مار|نقصان))',
    r'(?:hearing voices|voices .*(?:hurt|kill)|severely confused|آوازیں.*(?:سنتی|سنائی)|شدید الجھن|awazein.*(?:sunti|sunai))',
    r'(?:cannot breathe|can.t breathe|baby (?:isn.t|is not) breathing|severe chest pain|heavy bleeding|بہت خون|سانس نہیں|saans nahi|bohat khoon)',
    r'(?:husband (?:beats|hits)|afraid of my husband|scared of my husband|domestic violence|شوہر.*(?:مارتا|تشدد)|shohar.*(?:marta|maarta)|ghar.*tashaddud)',
]


def concern(text):
    text = normalize(text)
    return any(re.search(pattern, text) for pattern in PATTERNS)


HELP = {
    'en': 'Your safety matters. If you or your baby may be in immediate danger, contact local emergency services or go to the nearest emergency department now. Ask a safe, trusted person to stay with you. I cannot assess an emergency or provide treatment. Are you safe right now?',
    'ur': 'آپ کی حفاظت اہم ہے۔ اگر آپ یا بچے کو فوری خطرہ ہو تو مقامی ایمرجنسی سروس یا قریبی ہسپتال سے ابھی رابطہ کریں۔ محفوظ قابلِ اعتماد شخص کو ساتھ بلائیں۔ میں ایمرجنسی کا جائزہ یا علاج نہیں دے سکتی۔ کیا آپ ابھی محفوظ ہیں؟',
    'roman_ur': 'Aap ki hifazat aham hai. Agar aap ya bachay ko foran khatra ho to local emergency service ya qareebi hospital se abhi rabta karein. Kisi safe bharosaymand shakhs ko saath bulayein. Main emergency ka jaiza ya ilaaj nahi de sakti. Kya aap abhi mehfooz hain?',
}


def safety_response(language, reason='safety_language'):
    return {'reply': HELP[language], 'language': language, 'mode': 'safety', 'sources': [], 'actions': ['crisis'],
            'safety': {'requires_help': True, 'guardian_alert_allowed': False, 'reason': reason},
            'state': {'topic': 'safety', 'cbt_step': 0}, 'model_version': 'hum-raaz-safety-v1', 'clinical_validation': False}
