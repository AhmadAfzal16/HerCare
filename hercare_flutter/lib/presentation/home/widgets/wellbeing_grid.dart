import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../providers/language_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../providers/screening_provider.dart';
import '../../shared/hc_widgets.dart';
import '../../wellbeing/wellbeing_screen.dart';

/// 2×2 grid of wellbeing stat cards:
/// Latest score | Mood today | Sleep | Guardian chat
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
    const moodLabelsEn = ['Very low', 'Low', 'Okay', 'Good', 'Great'];
    const moodLabelsUr = ['بہت کم', 'کم', 'ٹھیک ہے', 'اچھا', 'بہترین'];

    final cards = [
      _WellbeingCard(
        icon: Icons.insights_rounded,
        color: AppColors.primary,
        tint: AppColors.primaryContainer,
        title: isUrdu ? 'EPDS اسکور' : 'EPDS score',
        value: latest?.totalScore == null ? '—' : '${latest!.totalScore} / 30',
        footer: completed == null
            ? (isUrdu ? 'میری جانچیں' : 'My tests')
            : DateFormat.yMMMd(isUrdu ? 'ur' : 'en')
                .format(completed.toLocal()),
        onTap: () => context.push(AppRoutes.tests),
      ),
      _WellbeingCard(
        icon: Icons.sentiment_satisfied_alt_rounded,
        color: AppColors.secondary,
        tint: AppColors.secondaryContainer,
        title: isUrdu ? 'آج کا موڈ' : 'Mood today',
        value: todayMood == null ? '—' : moodEmojis[todayMood - 1],
        valueIsEmoji: todayMood != null,
        footer: todayMood == null
            ? (isUrdu ? 'اندراج کریں' : 'Check in')
            : (isUrdu
                ? moodLabelsUr[todayMood - 1]
                : moodLabelsEn[todayMood - 1]),
        onTap: () => context.push(AppRoutes.mood),
      ),
      _WellbeingCard(
        icon: Icons.bedtime_rounded,
        color: AppColors.sky,
        tint: AppColors.skyContainer,
        title: isUrdu ? 'نیند' : 'Sleep',
        value: isUrdu ? 'نیند کا ریکارڈ' : 'Sleep log',
        valueIsText: true,
        footer: isUrdu ? 'نیند دیکھیں' : 'View sleep',
        onTap: () => context.push(AppRoutes.digitalWellbeing),
      ),
      _WellbeingCard(
        icon: Icons.forum_rounded,
        color: AppColors.success,
        tint: AppColors.successContainer,
        title: isUrdu ? 'سرپرست کی چیٹ' : 'Guardian chat',
        value: isUrdu ? 'محفوظ چیٹ' : 'Secure chat',
        valueIsText: true,
        footer: isUrdu ? 'چیٹ کھولیں' : 'Open chat',
        onTap: () => context.push(AppRoutes.secureChat),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HcSectionHeader(
            title: isUrdu ? 'آپ کی صحت' : 'Your wellbeing',
            actionLabel: isUrdu ? 'سب دیکھیں' : 'View all',
            onAction: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const WellbeingScreen()),
            ),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final oneColumn = MediaQuery.textScalerOf(context).scale(16) > 21 ||
                constraints.maxWidth < 270;
            if (oneColumn) {
              return Column(children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  cards[i],
                ],
              ]);
            }
            // Rows of two with equal heights, so the grid looks tidy.
            return Column(children: [
              for (var row = 0; row < cards.length; row += 2) ...[
                if (row > 0) const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: cards[row]),
                      const SizedBox(width: 12),
                      Expanded(child: cards[row + 1]),
                    ],
                  ),
                ),
              ],
            ]);
          }),
        ],
      ),
    );
  }
}

class _WellbeingCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color tint;
  final String title;
  final String value;
  final bool valueIsEmoji;
  final bool valueIsText;
  final String footer;
  final VoidCallback? onTap;

  const _WellbeingCard({
    required this.icon,
    required this.color,
    required this.tint,
    required this.title,
    required this.value,
    this.valueIsEmoji = false,
    this.valueIsText = false,
    required this.footer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return HcCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      radius: 22,
      // spaceBetween keeps the pill at the bottom when a row is stretched to
      // equal height, and simply stacks when the height is unconstrained.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  HcIconBadge(
                      icon: icon, color: color, background: tint, size: 38),
                  const Spacer(),
                  Icon(Icons.arrow_outward_rounded,
                      size: 16, color: context.hcTextHint),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: context.hcTextSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              if (valueIsEmoji)
                Text(value, style: const TextStyle(fontSize: 24))
              else
                Text(
                  value,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontSize: valueIsText ? 16 : 20),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const SizedBox(height: 10),
            ],
          ),
          HcPill(label: footer, color: color),
        ],
      ),
    );
  }
}
