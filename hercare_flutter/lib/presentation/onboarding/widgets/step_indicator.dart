import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';

/// Animated step progress indicator for the onboarding wizard.
/// Shows numbered circles connected by animated lines.
class OnboardingStepIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final Color activeColor;

  const OnboardingStepIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Row(
        children: List.generate(totalSteps * 2 - 1, (i) {
          if (i.isOdd) {
            // Connector line
            final stepIdx = i ~/ 2;
            final isCompleted = stepIdx < currentStep;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                height: 3,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? activeColor
                      : AppColors.outline.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          } else {
            // Step circle
            final stepIdx = i ~/ 2;
            final isCompleted = stepIdx < currentStep;
            final isCurrent = stepIdx == currentStep;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: isCurrent ? 36 : 30,
              height: isCurrent ? 36 : 30,
              decoration: BoxDecoration(
                color: isCompleted
                    ? activeColor
                    : isCurrent
                        ? activeColor
                        : AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isCompleted || isCurrent
                      ? activeColor
                      : AppColors.outline.withOpacity(0.4),
                  width: 2,
                ),
                boxShadow: isCurrent
                    ? [
                        BoxShadow(
                          color: activeColor.withOpacity(0.3),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Center(
                child: isCompleted
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 16)
                    : Text(
                        '${stepIdx + 1}',
                        style: AppTextStyles.labelSmall.copyWith(
                          color: isCurrent
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: isCurrent ? 13 : 11,
                        ),
                      ),
              ),
            );
          }
        }),
      ),
    );
  }
}
