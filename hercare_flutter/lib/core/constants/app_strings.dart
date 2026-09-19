/// All user-facing strings in one place.
/// Swap [en] / [ur] maps to switch locale at runtime.
///
/// Usage: AppStrings.of(context).splashTagline
/// For now, strings are accessed via [AppStrings.en] or [AppStrings.ur].
/// Phase 2 will integrate proper ARB-based localization.
abstract final class AppStrings {
  AppStrings._();

  // ─── English ──────────────────────────────────────────────────────────────
  static const Map<String, String> en = {
    // Splash
    'appName': 'HerCare',
    'splashTagline': 'You are not alone.',

    // Language Selection
    'selectLanguage': 'Select Your Language',
    'continueInEnglish': 'Continue in English',
    'continueInUrdu': 'جاری رکھیں اردو میں',
    'languageSubtitle':
        'You can change this anytime in Settings.',

    // Onboarding
    'onboardingTitle1': 'Tell us about you',
    'onboardingSubtitle1': 'Help us personalize your experience.',
    'onboardingTitle2': 'Your Birth Journey',
    'onboardingSubtitle2':
        'Clinical data helps us assess your risk accurately.',
    'onboardingTitle3': 'Your Support Circle',
    'onboardingSubtitle3':
        'We\'ll connect your loved ones to help you better.',
    'onboardingTitle4': 'Your Privacy & Consent',
    'onboardingSubtitle4':
        'Read carefully and choose what you\'re comfortable with.',

    // Personal Info
    'fullName': 'Full Name',
    'age': 'Age (years)',
    'education': 'Highest Education',
    'city': 'City',
    'monthsSinceBirth': 'Months since birth',

    // Obstetric Info
    'deliveryMethod': 'Mode of Delivery',
    'vaginalDelivery': 'Vaginal',
    'cesareanDelivery': 'Cesarean (C-Section)',
    'parity': 'Number of Previous Deliveries',
    'obstetricComplications': 'Any obstetric complications?',
    'preeclampsia': 'Preeclampsia / Eclampsia',
    'postpartumHemorrhage': 'Postpartum Hemorrhage',
    'pretermBirth': 'Preterm Birth (< 37 weeks)',
    'gestationalDiabetes': 'Gestational Diabetes',
    'babyGender': 'Baby\'s Gender',
    'male': 'Male',
    'female': 'Female',

    // Family / Support
    'householdType': 'Household Type',
    'nuclear': 'Nuclear Family',
    'joint': 'Joint Family',
    'monthlyIncome': 'Monthly Household Income (PKR)',
    'primarySupport': 'Primary source of support',
    'husband': 'Husband / Partner',
    'motherInLaw': 'Mother / In-law',
    'siblings': 'Siblings',
    'none': 'None',

    // Consent
    'consentTitle': 'Informed Consent',
    'consentIntro':
        'HerCare collects data to provide personalized support. Please review each permission below.',
    'tier1Label': 'Basic Monitoring (Required)',
    'tier1Desc':
        'EPDS screening, mood logs, and sleep data used to personalize your experience.',
    'tier2Label': 'Guardian Reports (Recommended)',
    'tier2Desc':
        'Aggregated health summaries shared with your linked guardian — never raw journal entries.',
    'tier3Label': 'Notification & Usage Analysis (Optional)',
    'tier3Desc':
        'Passively analyzes message previews and screen time to detect early distress signals.',
    'consentNote':
        'You may withdraw any permission at any time from Settings → Privacy.',
    'agreeAndContinue': 'I Agree & Continue',

    // Auth
    'phoneNumber': 'Phone Number',
    'password': 'Password',
    'confirmPassword': 'Confirm Password',
    'createAccount': 'Create Account',
    'login': 'Log In',
    'alreadyHaveAccount': 'Already have an account? Log in',
    'enterOtp': 'Enter OTP',
    'otpSentTo': 'We sent a 6-digit code to ',

    // Buttons / Common
    'next': 'Next',
    'back': 'Back',
    'skip': 'Skip',
    'save': 'Save',
    'cancel': 'Cancel',
    'confirm': 'Confirm',
    'loading': 'Please wait…',
    'error': 'Something went wrong.',
    'retry': 'Retry',
  };

  // ─── Urdu ─────────────────────────────────────────────────────────────────
  static const Map<String, String> ur = {
    'appName': 'ہرکیئر',
    'splashTagline': 'آپ اکیلی نہیں ہیں۔',
    'selectLanguage': 'زبان منتخب کریں',
    'continueInEnglish': 'Continue in English',
    'continueInUrdu': 'اردو میں جاری رکھیں',
    'languageSubtitle': 'آپ اسے کسی بھی وقت ترتیبات میں تبدیل کر سکتی ہیں۔',
    'onboardingTitle1': 'اپنے بارے میں بتائیں',
    'onboardingSubtitle1': 'آپ کے تجربے کو ذاتی بنانے میں ہماری مدد کریں۔',
    'onboardingTitle2': 'آپ کا زچگی کا سفر',
    'onboardingSubtitle2': 'طبی معلومات آپ کا خطرہ درست طریقے سے جانچنے میں مدد کرتی ہیں۔',
    'onboardingTitle3': 'آپ کا سپورٹ سرکل',
    'onboardingSubtitle3': 'ہم آپ کے پیاروں کو آپ کی بہتر مدد کے لیے جوڑیں گے۔',
    'onboardingTitle4': 'آپ کی رازداری اور رضامندی',
    'onboardingSubtitle4': 'غور سے پڑھیں اور اپنی پسند کا انتخاب کریں۔',
    'fullName': 'پورا نام',
    'age': 'عمر (سال)',
    'education': 'اعلیٰ تعلیم',
    'city': 'شہر',
    'monthsSinceBirth': 'پیدائش کے بعد مہینے',
    'deliveryMethod': 'ولادت کا طریقہ',
    'vaginalDelivery': 'قدرتی ولادت',
    'cesareanDelivery': 'آپریشن (سیزرین)',
    'parity': 'پچھلی ولادتوں کی تعداد',
    'obstetricComplications': 'کوئی پیچیدگیاں؟',
    'preeclampsia': 'پری ایکلامپسیا',
    'postpartumHemorrhage': 'زچگی کے بعد خون آنا',
    'pretermBirth': 'وقت سے پہلے پیدائش',
    'gestationalDiabetes': 'حمل کی ذیابیطس',
    'babyGender': 'بچے کی جنس',
    'male': 'لڑکا',
    'female': 'لڑکی',
    'householdType': 'گھرانے کی نوعیت',
    'nuclear': 'علیحدہ خاندان',
    'joint': 'مشترکہ خاندان',
    'monthlyIncome': 'ماہانہ آمدنی (روپے)',
    'primarySupport': 'بنیادی مددگار',
    'husband': 'شوہر',
    'motherInLaw': 'والدہ / ساس',
    'siblings': 'بہن بھائی',
    'none': 'کوئی نہیں',
    'consentTitle': 'باخبر رضامندی',
    'consentIntro': 'ہرکیئر ذاتی مدد فراہم کرنے کے لیے ڈیٹا اکٹھا کرتا ہے۔',
    'tier1Label': 'بنیادی نگرانی (ضروری)',
    'tier1Desc': 'EPDS اسکریننگ، موڈ لاگز، اور نیند کا ڈیٹا۔',
    'tier2Label': 'سرپرست رپورٹس (تجویز کردہ)',
    'tier2Desc': 'مجموعی صحت کا خلاصہ آپ کے سرپرست کے ساتھ شیئر کیا جاتا ہے۔',
    'tier3Label': 'اطلاع و استعمال کا تجزیہ (اختیاری)',
    'tier3Desc': 'تناؤ کی ابتدائی علامات کا پتہ لگانے کے لیے۔',
    'consentNote': 'آپ کسی بھی وقت ترتیبات سے اجازت واپس لے سکتی ہیں۔',
    'agreeAndContinue': 'میں متفق ہوں اور جاری رکھنا چاہتی ہوں',
    'phoneNumber': 'فون نمبر',
    'password': 'پاس ورڈ',
    'confirmPassword': 'پاس ورڈ کی تصدیق کریں',
    'createAccount': 'اکاؤنٹ بنائیں',
    'login': 'لاگ ان کریں',
    'next': 'اگلا',
    'back': 'پیچھے',
    'loading': 'براہ کرم انتظار کریں…',
    'error': 'کچھ غلط ہو گیا۔',
    'retry': 'دوبارہ کوشش کریں',
  };
}
