import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';


import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/onboarding_model.dart';
import '../../data/services/local_storage_service.dart';
import '../../providers/language_provider.dart';
import 'steps/personal_info_step.dart';
import 'steps/obstetric_info_step.dart';
import 'steps/family_support_step.dart';
import 'steps/consent_step.dart';
import 'widgets/step_indicator.dart';
import 'widgets/onboarding_nav_buttons.dart';

/// 4-step Onboarding Wizard
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
///   - On final step, data is persisted and user is routed to /register.
class OnboardingWizard extends StatefulWidget {
  const OnboardingWizard({super.key});

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  final PageController _pageController = PageController();
  final OnboardingData _data = OnboardingData();

  // Form keys for each step — validated on Next press
  final List<GlobalKey<FormState>> _formKeys = List.generate(
    AppConstants.totalOnboardingSteps,
    (_) => GlobalKey<FormState>(),
  );

  int _currentStep = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _pageController.dispose();
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

    setState(() => _currentStep++);
    _pageController.animateToPage(
      _currentStep,
      duration: AppConstants.animNormal,
      curve: Curves.easeInOutCubic,
    );
  }

  void _previousStep() {
    if (_currentStep == 0) {
      context.go(AppRoutes.languageSelection);
      return;
    }
    setState(() => _currentStep--);
    _pageController.animateToPage(
      _currentStep,
      duration: AppConstants.animNormal,
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _completeOnboarding() async {
    // Validate consent tier 1 (required)
    if (!_data.consentTier1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Basic monitoring consent is required to use HerCare.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final storage = LocalStorageService();
      await storage.setBool(AppConstants.onboardingCompleteKey, true);
      // Persist onboarding data for use in registration flow
      await storage.setObject('onboarding_data', _data.toJson());

      if (mounted) context.go(AppRoutes.register);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ─── UI ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final stepColor = AppColors.onboardingStepColors[_currentStep];

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──────────────────────────────────────────────────
            _buildHeader(isUrdu, stepColor),

            // ── Step Indicator ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: OnboardingStepIndicator(
                currentStep: _currentStep,
                totalSteps: AppConstants.totalOnboardingSteps,
                activeColor: stepColor,
              ),
            ),

            // ── Page Content ──────────────────────────────────────────
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(), // programmatic only
                children: [
                  PersonalInfoStep(
                    formKey: _formKeys[0],
                    data: _data,
                    isUrdu: isUrdu,
                  ),
                  ObstetricInfoStep(
                    formKey: _formKeys[1],
                    data: _data,
                    isUrdu: isUrdu,
                  ),
                  FamilySupportStep(
                    formKey: _formKeys[2],
                    data: _data,
                    isUrdu: isUrdu,
                  ),
                  ConsentStep(
                    formKey: _formKeys[3],
                    data: _data,
                    isUrdu: isUrdu,
                    onChanged: () => setState(() {}),
                  ),
                ],
              ),
            ),

            // ── Navigation Buttons ────────────────────────────────────
            OnboardingNavButtons(
              currentStep: _currentStep,
              totalSteps: AppConstants.totalOnboardingSteps,
              stepColor: stepColor,
              isSubmitting: _isSubmitting,
              isUrdu: isUrdu,
              onNext: _nextStep,
              onBack: _previousStep,
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
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
      ['Help us personalize your experience.', 'آپ کے تجربے کو ذاتی بنانے میں ہماری مدد کریں۔'],
      ['Clinical data improves risk accuracy.', 'طبی معلومات آپ کا خطرہ درست طریقے سے جانچنے میں مدد کرتی ہیں۔'],
      ['Connect your loved ones.', 'ہم آپ کے پیاروں کو آپ کی بہتر مدد کے لیے جوڑیں گے۔'],
      ['Choose what you\'re comfortable with.', 'غور سے پڑھیں اور اپنی پسند کا انتخاب کریں۔'],
    ];

    final title = isUrdu
        ? stepTitles[_currentStep][1]
        : stepTitles[_currentStep][0];
    final subtitle = isUrdu
        ? stepSubtitles[_currentStep][1]
        : stepSubtitles[_currentStep][0];

    return AnimatedContainer(
      duration: AppConstants.animNormal,
      curve: Curves.easeInOut,
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      decoration: BoxDecoration(
        color: stepColor.withOpacity(0.08),
        border: Border(
          bottom: BorderSide(
            color: stepColor.withOpacity(0.15),
            width: 1,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: isUrdu
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isUrdu
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: stepColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Step ${_currentStep + 1} of ${AppConstants.totalOnboardingSteps}',
                  style: AppTextStyles.labelSmall.copyWith(
                    color: stepColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: isUrdu
                ? AppTextStyles.urduHeadline.copyWith(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                  )
                : AppTextStyles.headlineSmall,
            textDirection:
                isUrdu ? TextDirection.rtl : TextDirection.ltr,
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: isUrdu
                ? AppTextStyles.urduLabel
                : AppTextStyles.bodyMedium,
            textDirection:
                isUrdu ? TextDirection.rtl : TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}
