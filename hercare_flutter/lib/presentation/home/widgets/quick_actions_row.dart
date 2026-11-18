import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../providers/language_provider.dart';
import '../../shared/hc_widgets.dart';

/// Grid of quick actions: every tool is visible at once, no sideways scrolling.
class QuickActionsRow extends StatelessWidget {
  const QuickActionsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    final actions = [
      _QuickAction(
        icon: Icons.air_rounded,
        labelEn: 'Breathe',
        labelUr: 'سانس لیں',
        color: AppColors.sky,
        tint: AppColors.skyContainer,
        onTap: () => context.push('${AppRoutes.breathing}?id=box_breathing'),
      ),
      _QuickAction(
        icon: Icons.edit_note_rounded,
        labelEn: 'Journal',
        labelUr: 'جریدہ',
        color: AppColors.secondary,
        tint: AppColors.secondaryContainer,
        onTap: () => context.push(AppRoutes.journal),
      ),
      _QuickAction(
        icon: Icons.chat_bubble_rounded,
        labelEn: 'Hum-Raaz',
        labelUr: 'ہم راز',
        color: AppColors.primary,
        tint: AppColors.primaryContainer,
        onTap: () => context.push(AppRoutes.chatbot),
      ),
      _QuickAction(
        icon: Icons.spa_rounded,
        labelEn: 'Calm tools',
        labelUr: 'سکون کی مشقیں',
        color: AppColors.success,
        tint: AppColors.successContainer,
        onTap: () => context.push(AppRoutes.therapy),
      ),
      _QuickAction(
        icon: Icons.self_improvement_rounded,
        labelEn: 'Meditate',
        labelUr: 'مراقبہ',
        color: AppColors.accent,
        tint: AppColors.accentContainer,
        onTap: () => context.push('${AppRoutes.meditation}?id=mindfulness'),
      ),
      _QuickAction(
        icon: Icons.forum_rounded,
        labelEn: 'Support chat',
        labelUr: 'سپورٹ چیٹ',
        color: AppColors.primaryDark,
        tint: const Color(0xFFEAE6FA),
        onTap: () => context.push(AppRoutes.secureChat),
      ),
      _QuickAction(
        icon: Icons.insights_rounded,
        labelEn: 'Insights',
        labelUr: 'بصیرت',
        color: AppColors.peach,
        tint: AppColors.peachContainer,
        onTap: () => context.push(AppRoutes.riskInsights),
      ),
      _QuickAction(
        icon: Icons.health_and_safety_rounded,
        labelEn: 'Get help now',
        labelUr: 'فوری مدد',
        color: AppColors.crisis,
        tint: AppColors.errorContainer,
        onTap: () => context.push(AppRoutes.crisis),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HcSectionHeader(title: isUrdu ? 'فوری اقدامات' : 'Quick actions'),
          const SizedBox(height: 12),
          HcCard(
            padding: const EdgeInsets.fromLTRB(8, 16, 8, 10),
            child: LayoutBuilder(builder: (context, constraints) {
              final large = MediaQuery.textScalerOf(context).scale(14) > 19;
              final columns = constraints.maxWidth >= 300 && !large ? 4 : 3;
              final width = constraints.maxWidth / columns;
              return Wrap(
                runSpacing: 6,
                children: [
                  for (final action in actions)
                    SizedBox(
                      width: width,
                      child: _ActionTile(action: action, isUrdu: isUrdu),
                    ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String labelEn;
  final String labelUr;
  final Color color;
  final Color tint;
  final VoidCallback onTap;

  const _QuickAction({
    required this.icon,
    required this.labelEn,
    required this.labelUr,
    required this.color,
    required this.tint,
    required this.onTap,
  });
}

class _ActionTile extends StatelessWidget {
  final _QuickAction action;
  final bool isUrdu;

  const _ActionTile({required this.action, required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    final label = isUrdu ? action.labelUr : action.labelEn;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              HcIconBadge(
                icon: action.icon,
                color: action.color,
                background: action.tint,
                size: 50,
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: context.hcTextPrimary, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
