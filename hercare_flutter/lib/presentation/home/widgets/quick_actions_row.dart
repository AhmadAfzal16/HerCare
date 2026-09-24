import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/language_provider.dart';

/// Horizontally scrollable row of quick action chips.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    final actions = [
      _QuickAction(
        icon: '🧘',
        labelEn: 'Breathe',
        labelUr: 'سانس لیں',
        bg: AppColors.primaryContainer,
        iconColor: AppColors.primary,
        onTap: () {},
      ),
      _QuickAction(
        icon: '📓',
        labelEn: 'Journal',
        labelUr: 'جریدہ',
        bg: AppColors.secondaryContainer,
        iconColor: AppColors.secondary,
        onTap: () => context.push(AppRoutes.journal),
      ),
      _QuickAction(
        icon: '💬',
        labelEn: 'Hum-Raaz',
        labelUr: 'ہم راز',
        bg: const Color(0xFFCFFAFE),
        iconColor: AppColors.accent,
        onTap: () {},
      ),
      _QuickAction(
        icon: '🤝',
        labelEn: 'Support Chat',
        labelUr: 'سپورٹ چیٹ',
        bg: AppColors.successContainer,
        iconColor: AppColors.success,
        onTap: () => context.push(AppRoutes.secureChat),
      ),
      _QuickAction(
        icon: '📈',
        labelEn: 'Risk Insights',
        labelUr: 'خطرے کی بصیرت',
        bg: const Color(0xFFEDE9FE),
        iconColor: AppColors.primary,
        onTap: () => context.push(AppRoutes.riskInsights),
      ),
      _QuickAction(
        icon: '🆘',
        labelEn: 'Crisis Help',
        labelUr: 'فوری مدد',
        bg: const Color(0xFFFEE2E2),
        iconColor: AppColors.crisis,
        onTap: () => context.push(AppRoutes.crisis),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUrdu ? 'فوری اقدامات' : 'Quick Actions',
            style: AppTextStyles.titleSmall.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: actions.map((a) {
                return _ActionChip(action: a, isUrdu: isUrdu);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final String icon;
  final String labelEn;
  final String labelUr;
  final Color bg;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.labelEn,
    required this.labelUr,
    required this.bg,
    required this.iconColor,
    required this.onTap,
  });
}

class _ActionChip extends StatelessWidget {
  final _QuickAction action;
  final bool isUrdu;

  const _ActionChip({required this.action, required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: action.bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: action.iconColor.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(action.icon, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              isUrdu ? action.labelUr : action.labelEn,
              style: AppTextStyles.labelMedium.copyWith(
                color: action.iconColor,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
