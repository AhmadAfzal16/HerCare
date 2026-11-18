import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/onboarding_model.dart';
import '../../data/services/local_storage_service.dart';
import '../../providers/language_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/onboarding_service.dart';
import 'steps/personal_info_step.dart';
import 'steps/obstetric_info_step.dart';
import 'steps/family_support_step.dart';
import 'steps/consent_step.dart';
import 'widgets/step_indicator.dart';
import 'widgets/onboarding_nav_buttons.dart';

/// Two required steps, with birth/family details available on request.
///
/// Steps:
///   0 – Personal Info     (M1 – Abdul Haadi)
///   1 – Obstetric Info    (M1 – PPD risk factors: delivery mode, complications)
///   2 – Family Support    (M1 – household type, income, support network)
///   3 – Consent           (M1 – tiered permission model)
///
/// Architecture:
///   - [OnboardingData] model accumulates data across steps.
///   - Each step validates its own form before allowing Next.
///   - On final step, data is persisted to the authenticated mother account.
class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  final ScrollController _pageScroll = ScrollController();
  final OnboardingData _data = OnboardingData();

  // Form keys for each step — validated on Next press
  final List<GlobalKey<FormState>> _formKeys = List.generate(
    AppConstants.totalOnboardingSteps,
    (_) => GlobalKey<FormState>(),
  );

  int _currentStep = 0;
  int _consentBackStep = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pageScroll.dispose();
    super.dispose();
  }

  // ─── Navigation ───────────────────────────────────────────────────────────

  Future<void> _nextStep() async {
    final formKey = _formKeys[_currentStep];
    // Consent step (step 3) has no traditional form; validated inside the step
    if (_currentStep < 3 && !(formKey.currentState?.validate() ?? false)) {
      return;
    }
    formKey.currentState?.save();

    if (_currentStep == AppConstants.totalOnboardingSteps - 1) {
      await _completeOnboarding();
      return;
    }

    _goToStep(_currentStep == 0 ? 3 : _currentStep + 1);
  }

  void _goToStep(int step) {
    if (step == 3) _consentBackStep = _currentStep;
    setState(() => _currentStep = step);
    if (_pageScroll.hasClients) _pageScroll.jumpTo(0);
  }

  void _addOptionalDetails() {
    final form = _formKeys[0].currentState;
    if (!(form?.validate() ?? false)) return;
    form?.save();
    _goToStep(1);
  }

  void _skipOptionalDetails() {
    _formKeys[_currentStep].currentState?.save();
    _goToStep(3);
  }

  void _previousStep() {
    if (_currentStep == 0) {
      return;
    }
    _goToStep(_currentStep == 3 ? _consentBackStep : _currentStep - 1);
  }

  Future<void> _completeOnboarding() async {
    // Validate consent tier 1 (required)
    if (!_data.consentTier1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Basic monitoring consent is required to use HerCare.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    final auth = context.read<AuthProvider>();
    try {
      await OnboardingService().complete(_data);
      await auth.refreshCurrentUser();
      await LocalStorageService()
          .setBool(AppConstants.onboardingCompleteKey, true);

      if (!mounted) return;
      context.go(AppRoutes.home);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error.toString().replaceFirst('Exception: ', ''),
            ),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final stepColor = AppColors.onboardingStepColors[_currentStep];

    final step = switch (_currentStep) {
      0 => PersonalInfoStep(formKey: _formKeys[0], data: _data, isUrdu: isUrdu),
      1 =>
        ObstetricInfoStep(formKey: _formKeys[1], data: _data, isUrdu: isUrdu),
      2 =>
        FamilySupportStep(formKey: _formKeys[2], data: _data, isUrdu: isUrdu),
      _ => ConsentStep(
          formKey: _formKeys[3],
          data: _data,
          isUrdu: isUrdu,
          onChanged: () => setState(() {})),
    };
    return Scaffold(
      backgroundColor: context.hcBg,
      body: SafeArea(
          child: Column(children: [
        Expanded(
            child: SingleChildScrollView(
          controller: _pageScroll,
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(children: [
            _buildHeader(isUrdu, stepColor),
            Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: OnboardingStepIndicator(
                    currentStep: _currentStep == 0 ? 0 : 1,
                    totalSteps: 2,
                    activeColor: stepColor)),
            if (_currentStep < 3)
              TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : (_currentStep == 0
                          ? _addOptionalDetails
                          : _skipOptionalDetails),
                  child: Text(_currentStep == 0
                      ? (isUrdu
                          ? 'مزید صحت اور خاندان کی معلومات دیں (اختیاری)'
                          : 'Add health and family details (optional)')
                      : (isUrdu
                          ? 'باقی اختیاری سوالات چھوڑ دیں'
                          : 'Skip remaining optional questions'))),
            KeyedSubtree(key: ValueKey(_currentStep), child: step),
          ]),
        )),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: OnboardingNavButtons(
                currentStep: _currentStep,
                totalSteps: AppConstants.totalOnboardingSteps,
                stepColor: stepColor,
                isSubmitting: _isSubmitting,
                isUrdu: isUrdu,
                onNext: _nextStep,
                onBack: _previousStep)),
      ])),
    );
  }

  Widget _buildHeader(bool isUrdu, Color stepColor) {
    const stepTitles = [
      ['Tell us about you', 'اپنے بارے میں بتائیں'],
      ['Your Birth Journey', 'آپ کا زچگی کا سفر'],
      ['Your Support Circle', 'آپ کا سپورٹ سرکل'],
      ['Privacy & Consent', 'رازداری اور رضامندی'],
    ];
    const stepSubtitles = [
      [
        'Only two quick answers are needed to continue.',
        'جاری رکھنے کے لیے صرف دو مختصر جواب درکار ہیں۔'
      ],
      ['These details are optional.', 'یہ معلومات دینا اختیاری ہے۔'],
      ['You can skip these questions.', 'آپ یہ سوالات چھوڑ سکتی ہیں۔'],
      [
        'Choose what you\'re comfortable with.',
        'غور سے پڑھیں اور اپنی پسند کا انتخاب کریں۔'
      ],
    ];

    final title =
        isUrdu ? stepTitles[_currentStep][1] : stepTitles[_currentStep][0];
    final subtitle = isUrdu
        ? stepSubtitles[_currentStep][1]
        : stepSubtitles[_currentStep][0];

    return AnimatedContainer(
      duration: AppConstants.animNormal,
      curve: Curves.easeInOut,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      decoration: BoxDecoration(
        color: stepColor.withValues(alpha: 0.08),
        border: Border(
          bottom: BorderSide(
            color: stepColor.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: stepColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _currentStep == 0
                    ? (isUrdu ? 'ضروری ۱ / ۲' : 'Required 1 of 2')
                    : _currentStep == 3
                        ? (isUrdu ? 'ضروری ۲ / ۲' : 'Required 2 of 2')
                        : (isUrdu ? 'اختیاری معلومات' : 'Optional details'),
                style: AppTextStyles.labelSmall.copyWith(
                  color: stepColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: isUrdu
                ? AppTextStyles.urduHeadline.copyWith(
                    color: context.hcTextPrimary,
                    fontSize: 22,
                  )
                : AppTextStyles.headlineSmall,
            textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: isUrdu ? AppTextStyles.urduLabel : AppTextStyles.bodyMedium,
            textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
