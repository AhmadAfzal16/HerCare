import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/language_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../providers/screening_provider.dart';
import 'package:intl/intl.dart';
import '../../wellbeing/wellbeing_screen.dart';

/// 2×2 grid of wellbeing stat cards:
/// EPDS Score | Mood Today | Last Sleep | Hum-Raaz
class WellbeingGrid extends StatelessWidget {
  const WellbeingGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final todayMood = context.watch<MoodProvider>().today?.moodRating;
    final screening = context.watch<ScreeningProvider>();
    final latest = screening.latest;
    final completed = latest?.completedAt;
    const moodEmojis = ['😔', '😟', '😐', '🙂', '😊'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                  child: Text(
                isUrdu ? 'آپ کی صحت' : 'Your Wellbeing',
                style: AppTextStyles.titleSmall.copyWith(fontSize: 16),
              )),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const WellbeingScreen(),
                    ),
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  isUrdu ? 'سب دیکھیں ←' : 'View all →',
                  style: AppTextStyles.labelMedium.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2x2 grid
          LayoutBuilder(builder: (context, constraints) {
            final columns = MediaQuery.textScalerOf(context).scale(16) > 21 ||
                    constraints.maxWidth < 270
                ? 1
                : 2;
            final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;
            return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _WellbeingCard(
                    icon: Icons.bar_chart_rounded,
                    iconBg: AppColors.primaryContainer,
                    iconColor: AppColors.primary,
                    title: isUrdu ? 'EPDS اسکور' : 'EPDS Score',
                    value: latest?.totalScore == null
                        ? '—'
                        : '${latest!.totalScore} / 30',
                    chipLabel: isUrdu ? 'میری جانچیں' : 'My tests',
                    chipColor: AppColors.primary,
                    timestamp: completed == null
                        ? ''
                        : DateFormat.yMMMd(isUrdu ? 'ur' : 'en')
                            .format(completed.toLocal()),
                    onTap: () => context.push(AppRoutes.tests),
                  ),
                  _WellbeingCard(
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    iconBg: AppColors.secondaryContainer,
                    iconColor: AppColors.secondary,
                    title: isUrdu ? 'آج کا موڈ' : 'Mood Today',
                    value: todayMood == null ? '—' : moodEmojis[todayMood - 1],
                    valueIsEmoji: true,
                    chipLabel: todayMood == null
                        ? (isUrdu ? 'اندراج کریں' : 'Check in')
                        : (isUrdu ? 'آج محفوظ' : 'Saved today'),
                    chipColor: AppColors.secondary,
                    timestamp:
                        todayMood == null ? '' : (isUrdu ? 'آج' : 'Today'),
                    onTap: () => context.push(AppRoutes.mood),
                  ),
                  _WellbeingCard(
                    icon: Icons.bedtime_rounded,
                    iconBg: const Color(0xFFCFFAFE),
                    iconColor: AppColors.accent,
                    title: isUrdu ? 'آخری نیند' : 'Last Sleep',
                    value: '—',
                    chipLabel: isUrdu ? 'نیند دیکھیں' : 'View sleep',
                    chipColor: AppColors.warning,
                    timestamp: '',
                    onTap: () => context.push(AppRoutes.digitalWellbeing),
                  ),
                  _WellbeingCard(
                    icon: Icons.chat_bubble_outline_rounded,
                    iconBg: AppColors.successContainer,
                    iconColor: AppColors.success,
                    title: isUrdu ? 'سرپرست کی چیٹ' : 'Guardian chat',
                    value: isUrdu ? 'محفوظ چیٹ' : 'Secure chat',
                    valueIsText: true,
                    chipLabel: isUrdu ? 'چیٹ کھولیں' : 'Open chat',
                    chipColor: AppColors.success,
                    timestamp: '',
                    onTap: () => context.push(AppRoutes.secureChat),
                  ),
                ].map((card) => SizedBox(width: width, child: card)).toList());
          }),
        ],
      ),
    );
  }
}

class _WellbeingCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;
  final bool valueIsEmoji;
  final bool valueIsText;
  final String chipLabel;
  final Color chipColor;
  final String timestamp;
  final VoidCallback? onTap;

  const _WellbeingCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
    this.valueIsEmoji = false,
    this.valueIsText = false,
    required this.chipLabel,
    required this.chipColor,
    required this.timestamp,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.hcSurface,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(icon, color: iconColor, size: 17),
              ),
              const SizedBox(height: 4),

              // Title
              Text(
                title,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 1),

              // Value
              if (valueIsEmoji)
                Text(value, style: const TextStyle(fontSize: 22))
              else
                Text(
                  value,
                  style: AppTextStyles.titleMedium.copyWith(
                    fontSize: valueIsText ? 13 : 16,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

              const SizedBox(height: 4),

              // Chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  chipLabel,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: chipColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (timestamp.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  timestamp,
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 9),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
