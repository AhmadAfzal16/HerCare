/// Original, fixed support cards. Not a language model or a clinical assessment.
/// No phone numbers are invented and no private text is written to local storage.
abstract final class OfflineSupport {
  static String text(String language, String en, String ur, String roman) =>
      language == 'ur'
          ? ur
          : language == 'roman_ur'
              ? roman
              : en;

  static bool needsImmediateHelp(String input) {
    final text = input.toLowerCase();
    return RegExp(
                r'hearing voices|seeing things|haven.?t slept.*(days|nights)|no sleep.*(days|nights)|awazein sun|awaazein sun|neend nahi.*(din|raat)|overdose|took too many pills|cannot breathe|can.t breathe|baby (is not|isn.t) breathing|heavy bleeding|husband (beats|hits)|shohar.*(marta|maarta)|saans nahi')
            .hasMatch(text) ||
        RegExp('آوازیں سن|کئی دن.*نیند|نیند.*کئی دن|بہت خون|سانس نہیں|شوہر.*مارتا')
            .hasMatch(text) ||
        RegExp(r'\b(suicid\w*|kill myself|end my life|hurt myself|harm my baby|hurt my baby|khudkushi|khud kushi|jaan dena|marna chahti|bachay ko mar|bache ko mar)\b')
            .hasMatch(text) ||
        RegExp('خودکشی|خود کشی|جان دینا|خود کو نقصان|بچے کو نقصان|مرنا چاہتی')
            .hasMatch(text);
  }

  static String reply(String language, {bool urgent = false}) => urgent
      ? text(
          language,
          'Please seek human help now. If you or your baby may be in immediate danger, contact local emergency services or go to the nearest emergency department. Ask a trusted person to stay with you. Open Immediate Help below. Offline support cannot notify your guardian.',
          'ابھی کسی انسان سے مدد لیں۔ اگر آپ یا بچے کو فوری خطرہ ہے تو مقامی ہنگامی خدمات یا قریبی ایمرجنسی سے رابطہ کریں۔ کسی قابل اعتماد شخص کو ساتھ رہنے کو کہیں۔ نیچے فوری مدد کھولیں۔ آف لائن مدد سرپرست کو اطلاع نہیں بھیج سکتی۔',
          'Abhi kisi insan se madad lein. Agar aap ya bachay ko foran khatra hai to local emergency services ya qareebi emergency department se rabta karein. Kisi bharosay walay shakhs ko saath rehne ko kahein. Neechay Immediate Help kholein. Offline support guardian ko notification nahi bhej sakti.')
      : text(
          language,
          'I am in limited offline mode, not live AI chat. I cannot read your health scores or send notifications. You can try a fixed grounding card, open your journal, or contact a trusted person. This conversation stays only in this screen’s memory and is not saved or sent later.',
          'یہ محدود آف لائن مدد ہے، براہ راست AI چیٹ نہیں۔ صحت کے اسکور پڑھنا یا اطلاع بھیجنا ممکن نہیں۔ توجہ کی مشق، جریدہ یا قابل اعتماد شخص کی مدد آزمائیں۔ یہ گفتگو صرف اس اسکرین کی عارضی یادداشت میں رہے گی، محفوظ یا بعد میں ارسال نہیں ہوگی۔',
          'Yeh limited offline support hai, live AI chat nahi. Main health scores nahi parh sakta aur notification nahi bhej sakta. Grounding card, journal ya bharosay walay shakhs ki madad azmayein. Yeh guftagu sirf is screen ki memory mein hai; save ya baad mein send nahi hogi.');

  static String grounding(String language) => text(
      language,
      'If comfortable, sit with support and notice your feet. Name three things you can see, two sounds you hear, and one surface you can feel. Breathe naturally; stop if uncomfortable. This optional grounding exercise is not treatment.',
      'اگر آرام دہ ہو تو سہارا لے کر بیٹھیں اور پاؤں محسوس کریں۔ تین نظر آنے والی چیزیں، دو آوازیں اور ایک چھونے والی سطح پہچانیں۔ قدرتی سانس لیں؛ تکلیف ہو تو رک جائیں۔ یہ اختیاری مشق علاج نہیں۔',
      'Agar aaram ho to sahara le kar baithain aur paon mehsoos karein. Teen nazar aanay wali cheezein, do awazein aur aik chhoonay wali satah pehchanain. Qudrati saans lein; takleef ho to ruk jayein. Yeh optional exercise ilaaj nahi.');
}
