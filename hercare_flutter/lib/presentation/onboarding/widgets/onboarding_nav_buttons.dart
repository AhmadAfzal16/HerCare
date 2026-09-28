import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';

/// Navigation buttons for the onboarding wizard.
/// Shows Back / Next or Back / Submit on the final step.
class OnboardingNavButtons extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final Color stepColor;
  final bool isSubmitting;
  final bool isUrdu;
  final VoidCallback onNext;
  final VoidCallback onBack;

  const OnboardingNavButtons({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.stepColor,
    required this.isSubmitting,
    required this.isUrdu,
    required this.onNext,
    required this.onBack,
  });

  bool get _isFirstStep => currentStep == 0;
  bool get _isLastStep => currentStep == totalSteps - 1;

  String get _nextLabel {
    if (_isLastStep) {
      return isUrdu ? 'متفق ہوں اور جاری رکھیں' : 'Agree & Continue';
    }
    return isUrdu ? 'اگلا' : 'Next';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
        children: [
          // Back button (always visible)
          SizedBox(
            height: 54,
            child: OutlinedButton(
              onPressed: onBack,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(54, 54),
                maximumSize: const Size(54, 54),
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                side:
                    BorderSide(color: stepColor.withOpacity(0.5), width: 1.5),
              ),
              child: Icon(
                isUrdu
                    ? Icons.arrow_forward_ios_rounded
                    : Icons.arrow_back_ios_rounded,
                color: stepColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Next / Submit button
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 54,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [stepColor, stepColor.withOpacity(0.75)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: stepColor.withOpacity(0.35),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: isSubmitting ? null : onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: AppTextStyles.labelLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        textDirection:
                            isUrdu ? TextDirection.rtl : TextDirection.ltr,
                        children: [
                          if (isUrdu) ...[
                            Text(
                              _nextLabel,
                              style: AppTextStyles.urduLabel.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              _isLastStep
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.arrow_back_ios_rounded,
                              size: 18,
                            ),
                          ] else ...[
                            Text(_nextLabel),
                            const SizedBox(width: 8),
                            Icon(
                              _isLastStep
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.arrow_forward_ios_rounded,
                              size: 18,
                            ),
                          ],
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
