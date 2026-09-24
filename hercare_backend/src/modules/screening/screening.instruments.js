const EPDS_OPTIONS = [
  [['As much as I always could', 'جتنا میں ہمیشہ کر سکتی تھی', 0], ['Not quite so much now', 'اب اتنا زیادہ نہیں', 1], ['Definitely not so much now', 'یقیناً اب اتنا زیادہ نہیں', 2], ['Not at all', 'بالکل نہیں', 3]],
  [['As much as I ever did', 'جتنا میں نے ہمیشہ کیا', 0], ['Rather less than I used to', 'پہلے کی نسبت کچھ کم', 1], ['Definitely less than I used to', 'یقیناً پہلے کی نسبت کم', 2], ['Hardly at all', 'شاید ہی کبھی', 3]],
  [['Yes, most of the time', 'ہاں، زیادہ تر وقت', 3], ['Yes, some of the time', 'ہاں، کچھ وقت', 2], ['Not very often', 'بہت کم', 1], ['No, never', 'نہیں، کبھی نہیں', 0]],
  [['No, not at all', 'نہیں، بالکل نہیں', 0], ['Hardly ever', 'شاید ہی کبھی', 1], ['Yes, sometimes', 'ہاں، کبھی کبھی', 2], ['Yes, very often', 'ہاں، اکثر', 3]],
  [['Yes, quite a lot', 'ہاں، کافی زیادہ', 3], ['Yes, sometimes', 'ہاں، کبھی کبھی', 2], ['No, not much', 'نہیں، زیادہ نہیں', 1], ['No, not at all', 'نہیں، بالکل نہیں', 0]],
  [["Yes, most of the time I haven't been able to cope at all", 'ہاں، زیادہ تر وقت میں بالکل مقابلہ نہیں کر سکی', 3], ["Yes, sometimes I haven't been coping as well as usual", 'ہاں، کبھی کبھی میں معمول کے مطابق مقابلہ نہیں کر پا رہی', 2], ['No, most of the time I have coped quite well', 'نہیں، زیادہ تر وقت میں نے کافی اچھی طرح مقابلہ کیا ہے', 1], ['No, I have been coping as well as ever', 'نہیں، میں ہمیشہ کی طرح اچھی طرح مقابلہ کر رہی ہوں', 0]],
  [['Yes, most of the time', 'ہاں، زیادہ تر وقت', 3], ['Yes, sometimes', 'ہاں، کبھی کبھی', 2], ['Not very often', 'بہت کم', 1], ['No, not at all', 'نہیں، بالکل نہیں', 0]],
  [['Yes, most of the time', 'ہاں، زیادہ تر وقت', 3], ['Yes, quite often', 'ہاں، اکثر', 2], ['Not very often', 'بہت کم', 1], ['No, not at all', 'نہیں، بالکل نہیں', 0]],
  [['Yes, most of the time', 'ہاں، زیادہ تر وقت', 3], ['Yes, quite often', 'ہاں، اکثر', 2], ['Only occasionally', 'صرف کبھی کبھار', 1], ['No, never', 'نہیں، کبھی نہیں', 0]],
  [['Yes, quite often', 'ہاں، اکثر', 3], ['Sometimes', 'کبھی کبھی', 2], ['Hardly ever', 'شاید ہی کبھی', 1], ['Never', 'کبھی نہیں', 0]],
];

const EPDS_QUESTIONS = [
  ['I have been able to laugh and see the funny side of things', 'میں ہنسنے اور چیزوں کا خوشگوار پہلو دیکھنے کے قابل رہی ہوں'],
  ['I have looked forward with enjoyment to things', 'میں نے چیزوں کا خوشی سے انتظار کیا ہے'],
  ['I have blamed myself unnecessarily when things went wrong', 'جب چیزیں غلط ہوئیں تو میں نے بلاوجہ خود کو قصوروار ٹھہرایا ہے'],
  ['I have been anxious or worried for no good reason', 'میں بلاوجہ پریشان یا فکرمند رہی ہوں'],
  ['I have felt scared or panicky for no very good reason', 'میں بلاوجہ خوفزدہ یا گھبراہٹ کا شکار ہوئی ہوں'],
  ['Things have been getting on top of me', 'چیزیں مجھ پر حاوی ہو رہی ہیں'],
  ['I have been so unhappy that I have had difficulty sleeping', 'میں اتنی ناخوش رہی ہوں کہ مجھے سونے میں دشواری ہوئی ہے'],
  ['I have felt sad or miserable', 'میں نے اداس یا دکھی محسوس کیا ہے'],
  ['I have been so unhappy that I have been crying', 'میں اتنی ناخوش رہی ہوں کہ میں روتی رہی ہوں'],
  ['The thought of harming myself has occurred to me', 'خود کو نقصان پہنچانے کا خیال میرے ذہن میں آیا ہے'],
];

const PHQ9_QUESTIONS = [
  ['Little interest or pleasure in doing things', 'کاموں میں دلچسپی یا خوشی کم محسوس ہونا'],
  ['Feeling down, depressed, or hopeless', 'اداس، افسردہ یا ناامید محسوس کرنا'],
  ['Trouble falling or staying asleep, or sleeping too much', 'نیند آنے یا برقرار رہنے میں مشکل، یا بہت زیادہ سونا'],
  ['Feeling tired or having little energy', 'تھکاوٹ یا توانائی کی کمی محسوس کرنا'],
  ['Poor appetite or overeating', 'بھوک کم لگنا یا ضرورت سے زیادہ کھانا'],
  ['Feeling bad about yourself, or that you are a failure', 'اپنے بارے میں برا محسوس کرنا یا خود کو ناکام سمجھنا'],
  ['Trouble concentrating on things', 'کاموں پر توجہ مرکوز کرنے میں مشکل'],
  ['Moving or speaking slowly, or being unusually restless', 'حرکت یا بولنے میں غیر معمولی سستی، یا بہت زیادہ بے چینی'],
  ['Thoughts that you would be better off dead or of hurting yourself', 'یہ خیال کہ آپ کا زندہ نہ رہنا بہتر ہے یا خود کو نقصان پہنچانا'],
];

const PHQ9_OPTIONS = [
  ['Not at all', 'بالکل نہیں', 0],
  ['Several days', 'کئی دن', 1],
  ['More than half the days', 'آدھے سے زیادہ دن', 2],
  ['Nearly every day', 'تقریباً ہر روز', 3],
];

function buildQuestions(questions, options) {
  return questions.map(([textEn, textUr], index) => ({
    number: index + 1,
    text_en: textEn,
    text_ur: textUr,
    options: (Array.isArray(options[0][0]) ? options[index] : options)
      .map(([textEnOption, textUrOption, score], optionIndex) => ({
        index: optionIndex,
        text_en: textEnOption,
        text_ur: textUrOption,
        score,
      })),
  }));
}

const INSTRUMENTS = Object.freeze({
  epds: Object.freeze({
    type: 'epds',
    name: 'Edinburgh Postnatal Depression Scale',
    version: 'cope-2023-v1',
    scoring_version: 'hercare-4band-v1',
    timeframe_days: 7,
    max_score: 30,
    crisis_question: 10,
    translation_status: {
      en: 'reference_text',
      ur: 'project_translation_requires_clinical_validation',
    },
    questions: buildQuestions(EPDS_QUESTIONS, EPDS_OPTIONS),
  }),
  phq9: Object.freeze({
    type: 'phq9',
    name: 'Patient Health Questionnaire 9',
    version: 'phq9-v1',
    scoring_version: 'hercare-4band-v1',
    timeframe_days: 14,
    max_score: 27,
    crisis_question: 9,
    translation_status: {
      en: 'reference_text',
      ur: 'project_translation_requires_clinical_validation',
    },
    questions: buildQuestions(PHQ9_QUESTIONS, PHQ9_OPTIONS),
  }),
});

function getInstrument(type) {
  return INSTRUMENTS[type] || null;
}

module.exports = { INSTRUMENTS, getInstrument };
