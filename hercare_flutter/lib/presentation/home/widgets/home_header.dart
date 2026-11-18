import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../providers/language_provider.dart';

class HomeHeader extends StatelessWidget implements PreferredSizeWidget {
  const HomeHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(72);

  String _greeting(bool urdu) {
    final hour = DateTime.now().hour;
    if (urdu) {
      if (hour < 12) return 'صبح بخیر';
      if (hour < 17) return 'دوپہر بخیر';
      return 'شام بخیر';
    }
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  IconData _greetingIcon() {
    final hour = DateTime.now().hour;
    if (hour < 17 && hour >= 6) return Icons.wb_sunny_rounded;
    return Icons.nightlight_round;
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final theme = Theme.of(context);

    return AppBar(
      backgroundColor: context.hcBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      centerTitle: false,
      toolbarHeight: 72,
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.28),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            // Scales down instead of overflowing with very large text sizes.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_greetingIcon(), size: 15, color: AppColors.warning),
                    const SizedBox(width: 5),
                    Text(
                      _greeting(isUrdu),
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: context.hcTextSecondary,
                          fontWeight: FontWeight.w700),
                    ),
                  ]),
                  Text(
                    isUrdu ? 'خوش آمدید' : 'Welcome back',
                    style: theme.textTheme.titleLarge?.copyWith(fontSize: 20),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      actions: [
        _RoundAction(
          tooltip: isUrdu ? 'اطلاعات' : 'Notifications',
          icon: Icons.notifications_none_rounded,
          onTap: () => context.push(AppRoutes.notifications),
        ),
        const SizedBox(width: 8),
        _RoundAction(
          tooltip: isUrdu ? 'ترتیبات' : 'Settings',
          icon: Icons.settings_outlined,
          onTap: () => GoRouter.of(context).push(AppRoutes.settings),
        ),
        const SizedBox(width: 16),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction(
      {required this.tooltip, required this.icon, required this.onTap});
  final String tooltip;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Material(
          color: context.hcSurface,
          shape: const CircleBorder(),
          elevation: context.isDark ? 0 : 1,
          shadowColor: AppColors.shadow.withValues(alpha: 0.18),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 22, color: context.hcTextPrimary),
            ),
          ),
        ),
      );
}
