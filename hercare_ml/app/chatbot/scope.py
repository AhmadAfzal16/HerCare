"""Explicit support-domain boundary for lexical fallback; not clinical intent."""
import re

TERMS = re.compile(r'\b(?:hercare|hum.?raaz|therapist|assistant|support|help|privacy|private|guardian|history|journal|chat|conversation|mood|check.?in|epds|phq.?9|screening|test|depress\w*|postpartum|mother|baby|newborn|parent|bond\w*|connection|sleep|rest|tired|energy|anxious|anxiety|overwhelmed|calm|grounding|breath\w*|meditat\w*|cbt|thought|guilt\w*|fail\w*|inadequate|lonely|alone|sad|faith|pray|belief|family|risk|probability|sentiment|recovery|recover\w*|percent|activity|activities|game|feel\w*|record|save|delete|khush|udaas|udas|akeli|madad|mood|journal|chat|neend|bacha|bache|bachay|khayal|pareshan|ghabrahat|sukoon|saans|dua|iman|aqeeda|nakafi|sharmindagi|ehtram|guftagu|talluq|aaram|thaki|nakaam|maa|sawal|ijazat|mehsoos|feeling|tashkhees|depression|prediction)\b|(?:ہرکیئر|ہم راز|ہمراز|مدد|معالج|نجی|سرپرست|گفتگو|جرنل|جریدہ|موڈ|اسکریننگ|ٹیسٹ|جائزے|ڈپریشن|ماں|بچہ|بچے|بچی|تعلق|نیند|آرام|تھکی|توانائی|پریشان|گھبراہٹ|پرسکون|سانس|مراقبہ|خیال|شرمندگی|ناکام|ناکافی|اکیلی|اداس|ایمان|دعا|عقائد|خاندان|امکان|پیش گوئی|جذبات|صحت یابی|فیصد|سرگرمی|کھیل|احساس|درج|محفوظ|حذف|تشخیص|سی بی ٹی|چیک اِن|پی ایچ|ای پی ڈی)', re.I)
IDENTITY = re.compile(r'^(?:hello|hi|hey|salam|assalam\w*|who are you|what can (?:you|this assistant) do|آپ کون|کیا آپ|یہ مددگار|سلام|tum kon|aap kon)', re.I)
PROHIBITED = re.compile(r'\b(?:dose|dosage|prescribe|sertraline|fluoxetine|antidepressant|medication|antibiotic|fever|investment|bitcoin|python code|politics|weather|election|football|diagnose me)\b|(?:دوا کی خوراک|نسخہ|بخار|سرمایہ کاری|تشخیص کریں)', re.I)


def in_scope(text):
    return bool((TERMS.search(text) or IDENTITY.search(text)) and not PROHIBITED.search(text))
