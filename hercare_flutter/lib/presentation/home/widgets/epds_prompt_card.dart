import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/language_provider.dart';
import '../../../providers/screening_provider.dart';

/// Card prompting the user to complete their weekly EPDS screening.
/// Shows a progress bar of last score against the 30-point maximum.
class EpdsPromptCard extends StatelessWidget {
  const EpdsPromptCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final screening = context.watch<ScreeningProvider>();
    if (!screening.overviewLoaded) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => context.read<ScreeningProvider>().loadOverview(),
      );
    }
    final lastScore = screening.latest?.totalScore;
    final progress = (lastScore ?? 0) / 30;
    final isDue = screening.reminder?.due ?? true;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header with DUE badge
          Row(
            children: [
              Text(
                isUrdu ? 'ہفتہ وار جانچ' : 'Weekly Check-in',
                style: AppTextStyles.titleSmall.copyWith(fontSize: 16),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (isDue ? AppColors.error : AppColors.success)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isDue
                      ? (isUrdu ? 'واجب' : 'DUE')
                      : (isUrdu ? 'مکمل' : 'UP TO DATE'),
                  style: AppTextStyles.labelSmall.copyWith(
                    color: isDue ? AppColors.error : AppColors.success,
                    fontWeight: FontWeight.w700,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Card
          Container(
            decoration: BoxDecoration(
              color: context.hcSurface,
              borderRadius: BorderRadius.circular(20),
              border: const Border(
                left: BorderSide(
                  color: AppColors.primary,
                  width: 4,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: icon + title
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: AppColors.primaryContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.assignment_outlined,
                          color: AppColors.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isUrdu ? 'EPDS اسکریننگ' : 'EPDS Screening',
                              style: AppTextStyles.titleSmall,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              isUrdu
                                  ? 'ایڈنبرا پوسٹ نیٹل ڈپریشن اسکیل — 10 سوالات، ~3 منٹ'
                                  : 'Edinburgh Postnatal Depression Scale — 10 questions, ~3 mins',
                              style: AppTextStyles.bodySmall
                                  .copyWith(fontSize: 11),
                              textDirection: isUrdu
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8,
                      backgroundColor: AppColors.primaryContainer,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lastScore == null
                        ? (isUrdu
                            ? 'ابھی تک کوئی مکمل اسکریننگ نہیں'
                            : 'No completed screening yet')
                        : (isUrdu
                            ? 'آخری اسکور: $lastScore / 30'
                            : 'Last score: $lastScore / 30'),
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                  ),
                  const SizedBox(height: 16),

                  // CTA Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.30),
                            blurRadius: 12,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          context.pushNamed('epds');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: Text(
                          isUrdu
                              ? (lastScore == null
                                  ? 'اسکریننگ شروع کریں ←'
                                  : 'اسکریننگ دوبارہ کریں ←')
                              : (lastScore == null
                                  ? 'Start Screening →'
                                  : 'Take Screening Again →'),
                          style: AppTextStyles.labelLarge
                              .copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
