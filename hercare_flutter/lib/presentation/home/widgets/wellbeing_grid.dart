import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/language_provider.dart';
import '../../wellbeing/wellbeing_screen.dart';

/// 2×2 grid of wellbeing stat cards:
/// EPDS Score | Mood Today | Last Sleep | Hum-Raaz
class WellbeingGrid extends StatelessWidget {
  const WellbeingGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isUrdu ? 'آپ کی صحت' : 'Your Wellbeing',
                style: AppTextStyles.titleSmall.copyWith(fontSize: 16),
              ),
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
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: [
              _WellbeingCard(
                icon: Icons.bar_chart_rounded,
                iconBg: AppColors.primaryContainer,
                iconColor: AppColors.primary,
                title: isUrdu ? 'EPDS اسکور' : 'EPDS Score',
                value: '8 / 30',
                chipLabel: isUrdu ? 'کم خطرہ' : 'Mild risk',
                chipColor: AppColors.success,
                timestamp: isUrdu ? '2 دن پہلے' : '2 days ago',
              ),
              _WellbeingCard(
                icon: Icons.sentiment_satisfied_alt_rounded,
                iconBg: AppColors.secondaryContainer,
                iconColor: AppColors.secondary,
                title: isUrdu ? 'آج کا موڈ' : 'Mood Today',
                value: '🙂',
                valueIsEmoji: true,
                chipLabel: isUrdu ? 'ٹھیک ہے' : 'Feeling okay',
                chipColor: AppColors.secondary,
                timestamp: isUrdu ? 'ابھی' : 'Just now',
              ),
              _WellbeingCard(
                icon: Icons.bedtime_rounded,
                iconBg: const Color(0xFFCFFAFE),
                iconColor: AppColors.accent,
                title: isUrdu ? 'آخری نیند' : 'Last Sleep',
                value: '6h 20m',
                chipLabel: isUrdu ? 'اوسط سے کم' : 'Below avg',
                chipColor: AppColors.warning,
                timestamp: isUrdu ? 'گزشتہ رات' : 'Last night',
              ),
              _WellbeingCard(
                icon: Icons.chat_bubble_outline_rounded,
                iconBg: AppColors.successContainer,
                iconColor: AppColors.success,
                title: isUrdu ? 'ہم راز' : 'Hum-Raaz',
                value: isUrdu ? 'AI چیٹ' : 'AI Chat',
                valueIsText: true,
                chipLabel: isUrdu ? '24/7 دستیاب' : 'Available 24/7',
                chipColor: AppColors.success,
                timestamp: '',
              ),
            ],
          ),
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
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
          const SizedBox(height: 6),

          // Title
          Text(
            title,
            style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),

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
              color: chipColor.withOpacity(0.12),
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
    );
  }
}
