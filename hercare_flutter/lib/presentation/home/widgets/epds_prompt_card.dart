import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../providers/language_provider.dart';
import '../../../providers/screening_provider.dart';
import '../../shared/hc_widgets.dart';

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
        (_) {
          if (context.mounted) screening.loadOverview();
        },
      );
    }
    final lastScore = screening.latest?.totalScore;
    final progress = (lastScore ?? 0) / 30;
    final isDue = screening.reminder?.due;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HcSectionHeader(
            title: isUrdu ? 'ہفتہ وار جانچ' : 'Weekly check-in',
            trailing: isDue == null
                ? null
                : HcPill(
                    label: isDue
                        ? (isUrdu ? 'واجب' : 'Due now')
                        : (isUrdu ? 'مکمل' : 'Up to date'),
                    icon: isDue
                        ? Icons.schedule_rounded
                        : Icons.check_circle_rounded,
                    color: isDue ? AppColors.peach : AppColors.success,
                  ),
          ),
          const SizedBox(height: 12),
          HcCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const HcIconBadge(
                      icon: Icons.assignment_rounded,
                      color: AppColors.primary,
                      background: AppColors.primaryContainer,
                      size: 48,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isUrdu ? 'EPDS اسکریننگ' : 'EPDS screening',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isUrdu
                                ? '10 سوالات · تقریباً 3 منٹ'
                                : '10 gentle questions · about 3 minutes',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: context.hcTextSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(99),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  lastScore == null
                      ? (isUrdu
                          ? 'ابھی تک کوئی مکمل اسکریننگ نہیں'
                          : 'No completed screening yet')
                      : (isUrdu
                          ? 'آخری اسکور: $lastScore / 30'
                          : 'Last score: $lastScore / 30'),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: context.hcTextSecondary),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutes.tests),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                  label: Text(isUrdu ? 'میری جانچیں دیکھیں' : 'View my tests'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
