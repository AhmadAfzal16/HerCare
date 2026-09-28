class EpdsQuestion {
  final int id;
  final String questionEn;
  final String questionUr;
  final List<EpdsAnswer> answers;

  const EpdsQuestion({
    required this.id,
    required this.questionEn,
    required this.questionUr,
    required this.answers,
  });
}

class EpdsAnswer {
  final String textEn;
  final String textUr;
  final int score;

  const EpdsAnswer({
    required this.textEn,
    required this.textUr,
    required this.score,
  });
}

// ─── Standard EPDS Questionnaire (English + Urdu) ───────────────────────────
// Questions and scoring based on standard clinical EPDS.
// Note: Scoring direction changes for some questions (0-3 vs 3-0).

const List<EpdsQuestion> epdsQuestions = [
  EpdsQuestion(
    id: 1,
    questionEn: '1. I have been able to laugh and see the funny side of things',
    questionUr: '١. میں ہنسنے اور چیزوں کا خوشگوار پہلو دیکھنے کے قابل رہی ہوں',
    answers: [
      EpdsAnswer(textEn: 'As much as I always could', textUr: 'جتنا میں ہمیشہ کر سکتی تھی', score: 0),
      EpdsAnswer(textEn: 'Not quite so much now', textUr: 'اب اتنا زیادہ نہیں', score: 1),
      EpdsAnswer(textEn: 'Definitely not so much now', textUr: 'یقیناً اب اتنا زیادہ نہیں', score: 2),
      EpdsAnswer(textEn: 'Not at all', textUr: 'بالکل نہیں', score: 3),
    ],
  ),
  EpdsQuestion(
    id: 2,
    questionEn: '2. I have looked forward with enjoyment to things',
    questionUr: '٢. میں نے چیزوں کا خوشی سے انتظار کیا ہے',
    answers: [
      EpdsAnswer(textEn: 'As much as I ever did', textUr: 'جتنا میں نے ہمیشہ کیا', score: 0),
      EpdsAnswer(textEn: 'Rather less than I used to', textUr: 'پہلے کی نسبت کچھ کم', score: 1),
      EpdsAnswer(textEn: 'Definitely less than I used to', textUr: 'یقیناً پہلے کی نسبت کم', score: 2),
      EpdsAnswer(textEn: 'Hardly at all', textUr: 'شاید ہی کبھی', score: 3),
    ],
  ),
  EpdsQuestion(
    id: 3,
    questionEn: '3. I have blamed myself unnecessarily when things went wrong',
    questionUr: '٣. جب چیزیں غلط ہوئیں تو میں نے بلاوجہ خود کو قصوروار ٹھہرایا ہے',
    answers: [
      EpdsAnswer(textEn: 'Yes, most of the time', textUr: 'ہاں، زیادہ تر وقت', score: 3),
      EpdsAnswer(textEn: 'Yes, some of the time', textUr: 'ہاں، کچھ وقت', score: 2),
      EpdsAnswer(textEn: 'Not very often', textUr: 'بہت کم', score: 1),
      EpdsAnswer(textEn: 'No, never', textUr: 'نہیں، کبھی نہیں', score: 0),
    ],
  ),
  EpdsQuestion(
    id: 4,
    questionEn: '4. I have been anxious or worried for no good reason',
    questionUr: '٤. میں بلاوجہ پریشان یا فکرمند رہی ہوں',
    answers: [
      EpdsAnswer(textEn: 'No, not at all', textUr: 'نہیں، بالکل نہیں', score: 0),
      EpdsAnswer(textEn: 'Hardly ever', textUr: 'شاید ہی کبھی', score: 1),
      EpdsAnswer(textEn: 'Yes, sometimes', textUr: 'ہاں، کبھی کبھی', score: 2),
      EpdsAnswer(textEn: 'Yes, very often', textUr: 'ہاں، اکثر', score: 3),
    ],
  ),
  EpdsQuestion(
    id: 5,
    questionEn: '5. I have felt scared or panicky for no very good reason',
    questionUr: '٥. میں بلاوجہ خوفزدہ یا گھبراہٹ کا شکار ہوئی ہوں',
    answers: [
      EpdsAnswer(textEn: 'Yes, quite a lot', textUr: 'ہاں، کافی زیادہ', score: 3),
      EpdsAnswer(textEn: 'Yes, sometimes', textUr: 'ہاں، کبھی کبھی', score: 2),
      EpdsAnswer(textEn: 'No, not much', textUr: 'نہیں، زیادہ نہیں', score: 1),
      EpdsAnswer(textEn: 'No, not at all', textUr: 'نہیں، بالکل نہیں', score: 0),
    ],
  ),
  EpdsQuestion(
    id: 6,
    questionEn: '6. Things have been getting on top of me',
    questionUr: '٦. چیزیں مجھ پر حاوی ہو رہی ہیں',
    answers: [
      EpdsAnswer(textEn: 'Yes, most of the time I haven\'t been able to cope at all', textUr: 'ہاں، زیادہ تر وقت میں بالکل مقابلہ نہیں کر سکی', score: 3),
      EpdsAnswer(textEn: 'Yes, sometimes I haven\'t been coping as well as usual', textUr: 'ہاں، کبھی کبھی میں معمول کے مطابق مقابلہ نہیں کر پا رہی', score: 2),
      EpdsAnswer(textEn: 'No, most of the time I have coped quite well', textUr: 'نہیں، زیادہ تر وقت میں نے کافی اچھی طرح مقابلہ کیا ہے', score: 1),
      EpdsAnswer(textEn: 'No, I have been coping as well as ever', textUr: 'نہیں، میں ہمیشہ کی طرح اچھی طرح مقابلہ کر رہی ہوں', score: 0),
    ],
  ),
  EpdsQuestion(
    id: 7,
    questionEn: '7. I have been so unhappy that I have had difficulty sleeping',
    questionUr: '٧. میں اتنی ناخوش رہی ہوں کہ مجھے سونے میں دشواری ہوئی ہے',
    answers: [
      EpdsAnswer(textEn: 'Yes, most of the time', textUr: 'ہاں، زیادہ تر وقت', score: 3),
      EpdsAnswer(textEn: 'Yes, sometimes', textUr: 'ہاں، کبھی کبھی', score: 2),
      EpdsAnswer(textEn: 'Not very often', textUr: 'بہت کم', score: 1),
      EpdsAnswer(textEn: 'No, not at all', textUr: 'نہیں، بالکل نہیں', score: 0),
    ],
  ),
  EpdsQuestion(
    id: 8,
    questionEn: '8. I have felt sad or miserable',
    questionUr: '٨. میں نے اداس یا دکھی محسوس کیا ہے',
    answers: [
      EpdsAnswer(textEn: 'Yes, most of the time', textUr: 'ہاں، زیادہ تر وقت', score: 3),
      EpdsAnswer(textEn: 'Yes, quite often', textUr: 'ہاں، اکثر', score: 2),
      EpdsAnswer(textEn: 'Not very often', textUr: 'بہت کم', score: 1),
      EpdsAnswer(textEn: 'No, not at all', textUr: 'نہیں، بالکل نہیں', score: 0),
    ],
  ),
  EpdsQuestion(
    id: 9,
    questionEn: '9. I have been so unhappy that I have been crying',
    questionUr: '٩. میں اتنی ناخوش رہی ہوں کہ میں روتی رہی ہوں',
    answers: [
      EpdsAnswer(textEn: 'Yes, most of the time', textUr: 'ہاں، زیادہ تر وقت', score: 3),
      EpdsAnswer(textEn: 'Yes, quite often', textUr: 'ہاں، اکثر', score: 2),
      EpdsAnswer(textEn: 'Only occasionally', textUr: 'صرف کبھی کبھار', score: 1),
      EpdsAnswer(textEn: 'No, never', textUr: 'نہیں، کبھی نہیں', score: 0),
    ],
  ),
  EpdsQuestion(
    id: 10,
    questionEn: '10. The thought of harming myself has occurred to me',
    questionUr: '١٠. خود کو نقصان پہنچانے کا خیال میرے ذہن میں آیا ہے',
    answers: [
      EpdsAnswer(textEn: 'Yes, quite often', textUr: 'ہاں، اکثر', score: 3),
      EpdsAnswer(textEn: 'Sometimes', textUr: 'کبھی کبھی', score: 2),
      EpdsAnswer(textEn: 'Hardly ever', textUr: 'شاید ہی کبھی', score: 1),
      EpdsAnswer(textEn: 'Never', textUr: 'کبھی نہیں', score: 0),
    ],
  ),
];
