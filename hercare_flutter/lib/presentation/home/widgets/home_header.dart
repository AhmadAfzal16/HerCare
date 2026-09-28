import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/language_provider.dart';
import '../../../core/routing/app_router.dart';
import 'package:go_router/go_router.dart';

class HomeHeader extends StatelessWidget implements PreferredSizeWidget {
  const HomeHeader({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(70);

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _greetingUrdu() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'صبح بخیر،';
    if (hour < 17) return 'دوپہر بخیر،';
    return 'شام بخیر،';
  }

  @override
  Widget build(BuildContext context) {
    final user   = context.watch<AuthProvider>().user;
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final phone  = user?.phone ?? '';
    // Show last 4 digits of phone as display name until profile is set
    final displayName = phone.length >= 4
        ? '••${phone.substring(phone.length - 4)}'
        : 'Hi there';

    return AppBar(
      backgroundColor: context.hcSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      automaticallyImplyLeading: false,
      toolbarHeight: 70,
      title: Row(
        children: [
          // Avatar circle
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.30),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.favorite_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          // Greeting text
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isUrdu ? _greetingUrdu() : _greeting(),
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12),
                textDirection:
                    isUrdu ? TextDirection.rtl : TextDirection.ltr,
              ),
              Text(
                displayName,
                style: AppTextStyles.titleMedium.copyWith(fontSize: 17),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // Bell with badge
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: Icon(Icons.notifications_none_rounded,
                  color: context.hcTextPrimary, size: 26),
              onPressed: () => GoRouter.of(context).push(AppRoutes.notifications),
            ),
            Positioned(
              right: 10,
              top: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ),
        IconButton(
          icon: Icon(Icons.settings_outlined,
              color: context.hcTextPrimary, size: 24),
          onPressed: () => GoRouter.of(context).push(AppRoutes.settings),
        ),
        const SizedBox(width: 4),
      ],
    );
  }
}
