"""Bounded retrieval/dialogue policy independent of medical prediction and alerts."""
import re
from threading import BoundedSemaphore
from .schemas import ChatRequest
from .retrieval import normalize, retriever
from .safety import concern, safety_response
from .local_generation import generate, evidence_catalog, ABSTAIN
from .personalization import summary
from .scope import in_scope, PROHIBITED

SLOT = BoundedSemaphore(2)
ACTIONS = {'mood_checkin':'mood', 'screening_tests':'tests', 'guardian_support':'guardian',
           'breathing':'breathing', 'meditation':'grounding', 'sleep_record':'mood'}
FALLBACK = {
    'en': 'I do not have a reliable answer for that. I can help with HerCare, gentle reflection or coping options. For a health or treatment question, please ask a qualified professional. What would you like support with?',
    'ur': 'اس سوال کا قابلِ اعتماد جواب میرے پاس نہیں۔ ہرکیئر، نرم گفتگو یا مدد کے طریقوں پر بات کر سکتی ہوں۔ صحت یا علاج کا سوال مستند ماہر سے پوچھیں۔ کس بات میں مدد چاہیے؟',
    'roman_ur': 'Is sawal ka bharosaymand jawab mere paas nahi. HerCare, narmi se guftagu ya coping options mein madad kar sakti hoon. Sehat ya ilaaj ka sawal qualified professional se poochein. Kis baat mein support chahiye?',
}
CBT = {
    'en': ['What makes that thought feel true, and is there anything that does not fit it?', 'What would you say to a friend in the same situation? A balanced thought need not be cheerful.', 'What is one small, manageable step you would choose? You can stop this reflection whenever you wish.'],
    'ur': ['کیا چیز اس خیال کو سچ دکھاتی ہے، اور کیا کوئی بات اس سے مختلف بھی ہے؟', 'اسی حالت میں دوست کو کیا کہیں گی؟ متوازن خیال کا خوشگوار ہونا ضروری نہیں۔', 'آپ کون سا چھوٹا آسان قدم چنیں گی؟ جب چاہیں یہ گفتگو روک سکتی ہیں۔'],
    'roman_ur': ['Kya cheez is khayal ko sach dikhati hai, aur kya koi baat is se mukhtalif bhi hai?', 'Isi halat mein dost ko kya kahein gi? Balanced khayal ka khushgawar hona zaroori nahi.', 'Kaunsa chhota asaan qadam chunein gi? Jab chahein ye reflection rok sakti hain.'],
}
AGGREGATE_NOTICE = {
    'en': 'You allowed dated aggregate context. Those measurements remain separate, may be incomplete, and are not a diagnosis. You can turn personalization off.',
    'ur': 'آپ نے تاریخ والے مجموعی اسکور کی اجازت دی ہے۔ یہ پیمائشیں الگ، نامکمل ہو سکتی ہیں اور تشخیص نہیں۔ ذاتی رہنمائی کی اجازت بند کر سکتی ہیں۔',
    'roman_ur': 'Aap ne tareekh walay aggregate context ki ijazat di hai. Ye measurements alag, na-mukammal ho sakti hain aur tashkhees nahi. Personalization band kar sakti hain.',
}


def compose(request: ChatRequest):
    text = normalize(request.message)
    if concern(text):
        return safety_response(request.language)
    if any(screen.safety_positive and not screen.stale for screen in request.context.screenings):
        return safety_response(request.language, 'recent_screening_safety_indicator')
    if request.state.topic == 'safety':
        safe_now = re.search(r'\b(?:i am safe now|i.m safe now|main ab (?:mehfooz|safe) (?:hun|hoon))\b|میں (?:ابھی|اب) محفوظ ہوں', text)
        if not safe_now:
            return safety_response(request.language, 'prior_safety_concern_needs_checkin')
        return {'reply': {'en':'Thank you for telling me you are safe right now. That is your report, not a clinical assessment. Please still contact a qualified professional about the concern. If danger returns, use Immediate Help.',
                         'ur':'ابھی محفوظ ہونے کی بات بتانے کا شکریہ۔ یہ آپ کی اطلاع ہے، طبی جائزہ نہیں۔ اس تشویش پر مستند ماہر سے ضرور بات کریں۔ خطرہ واپس آئے تو فوری مدد استعمال کریں۔',
                         'roman_ur':'Abhi safe hone ki baat batane ka shukriya. Yeh aap ki report hai, clinical assessment nahi. Is concern par qualified professional se zaroor baat karein. Khatra wapas aaye to Immediate Help use karein.'}[request.language],
                'language':request.language,'mode':'retrieval_only','sources':[],'actions':['crisis'],
                'safety':{'requires_help':False,'guardian_alert_allowed':False,'reason':None},
                'state':{},'model_version':'hum-raaz-dialogue-v1','clinical_validation':False}
    if not SLOT.acquire(blocking=False):
        return {'reply': FALLBACK[request.language], 'language': request.language, 'mode': 'unavailable', 'sources': [], 'actions': [],
                'safety': {'requires_help': False, 'guardian_alert_allowed': False, 'reason': None}, 'state': {}, 'model_version': 'busy', 'clinical_validation': False}
    try:
        remember = re.search(r'\b(?:what did i (?:say|tell|share)|remember (?:my|our|what)|previous conversation)\b|(?:پچھلی گفتگو|پہلے کیا بتایا)|\b(?:pehle kya (?:bataya|kaha)|pichli (?:baat|guftagu))\b', text)
        if remember:
            last_user = next((turn.content for turn in reversed(request.history) if turn.role == 'user'), None)
            prefix = {'en':'The recent conversation context contains your words: ', 'ur':'حالیہ گفتگو میں آپ نے کہا: ', 'roman_ur':'Haal ki guftagu mein aap ne kaha: '}[request.language]
            response = prefix + last_user[:350] if last_user else {
                'en':'I do not have an earlier user message in this bounded context. You can open your private history to see older conversations.',
                'ur':'اس محدود سیاق میں پہلے کا پیغام نہیں ہے۔ پرانی گفتگو دیکھنے کے لیے نجی تاریخ کھول سکتی ہیں۔',
                'roman_ur':'Is mehdood context mein pehle ka paigham nahi. Purani guftagu dekhne ke liye private history khol sakti hain.'}[request.language]
            return {'reply':response,'language':request.language,'mode':'retrieval_only','sources':[],'actions':[],
                    'safety':{'requires_help':False,'guardian_alert_allowed':False,'reason':None},
                    'state':request.state.model_dump(),'model_version':'hum-raaz-memory-v1','clinical_validation':False}
        matches = retriever().search(request.message) if in_scope(text) else []
        state = request.state
        continuation = re.fullmatch(r'(?:yes(?: please)?|continue|tell me more|haan|han|ji|aur batao|جی|ہاں|مزید بتائیں)[.!?۔؟ ]*', text)
        if continuation and state.topic and state.topic != 'thoughts':
            prior_card = next((card for card in retriever().cards if card['id'] == state.topic), None)
            if prior_card:
                matches = [(prior_card, 1.0, 1.0)]
        stop = re.search(r'\b(?:stop|cancel|leave this|bas|rok|nahi chahiye)\b|(?:بس|روک|نہیں چاہیے)', text)
        explicit_switch = matches and matches[0][2] >= .3 and matches[0][0]['id'] != 'thoughts'
        if state.cbt_step and not stop and not explicit_switch and not PROHIBITED.search(text):
            step = state.cbt_step
            return {'reply': CBT[request.language][step-1], 'language': request.language, 'mode': 'retrieval_only',
                    'sources': [], 'actions': ['grounding'], 'safety': {'requires_help': False, 'guardian_alert_allowed': False, 'reason': None},
                    'state': {'topic': 'thoughts', 'cbt_step': step+1 if step < 3 else 0}, 'model_version': 'hum-raaz-dialogue-v1', 'clinical_validation': False}
        if stop:
            matches = []
        topic = matches[0][0]['id'] if matches else None
        card = matches[0][0] if matches else None
        mode = 'retrieval_only'
        if card and topic != 'thoughts':
            evidence = evidence_catalog(retriever().cards, request.language)
            chosen = generate(request.message, request.language, request.history, evidence, {})
            if chosen == ABSTAIN:
                card = None
                topic = None
                mode = 'local_rag'
            elif chosen:
                card = next(c for c in retriever().cards if c['id'] == chosen)
                topic = chosen
                mode = 'local_rag'
        reply = card['responses'][request.language] if card else FALLBACK[request.language]
        context = request.context
        # Personalize topic/length, not medical conclusions; do not let a high mood cancel safety.
        if context.personalization_enabled and card and card['id'] in {'about', 'support', 'calm', 'mood'}:
            if context.mood and context.mood.mean_rating is not None and context.mood.mean_rating <= 2:
                reply += '\n\n' + {'en':'Your recent recorded mood is low. Would one small support step feel easier than a long exercise?',
                                   'ur':'آپ کا حالیہ درج شدہ موڈ کم ہے۔ کیا لمبی مشق کے بجائے مدد کا ایک چھوٹا قدم آسان لگے گا؟',
                                   'roman_ur':'Aap ka haal ka recorded mood kam hai. Kya lambi exercise ke bajaye support ka chhota qadam asaan lagay ga?'}[request.language]
            reply += '\n\n' + AGGREGATE_NOTICE[request.language]
        aggregate = summary(context, request.language)
        if aggregate:
            reply += '\n\n' + aggregate
        sources_cards = [card] if card else []
        sources = [{'id': c['id'], 'title': c['title'], 'url': c['url']} for c in sources_cards if c['url'].startswith('https://')]
        return {'reply': reply, 'language': request.language, 'mode': mode, 'sources': sources,
                'actions': [ACTIONS[card['action']]] if card else ['mood', 'tests', 'crisis'],
                'safety': {'requires_help': False, 'guardian_alert_allowed': False, 'reason': None},
                'state': {'topic': topic, 'cbt_step': 1 if topic == 'thoughts' else 0},
                'model_version': 'hum-raaz-rag-v1' if mode == 'local_rag' else 'hum-raaz-retrieval-v1', 'clinical_validation': False}
    finally:
        SLOT.release()
