import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../shared/hc_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  String _role(String role, bool urdu) => switch (role) {
        'mother' => urdu ? 'ماں' : 'Mother',
        'guardian' => urdu ? 'سرپرست' : 'Guardian',
        'admin' => urdu ? 'منتظم' : 'Admin',
        _ => role,
      };

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isUrdu = languageProvider.isUrdu;
    final user = authProvider.user;
    final theme = Theme.of(context);

    final items = [
      (
        Icons.settings_rounded,
        AppColors.primary,
        AppColors.primaryContainer,
        isUrdu ? 'ترتیبات' : 'Settings',
        () => context.push(AppRoutes.settings),
      ),
      (
        Icons.shield_rounded,
        AppColors.success,
        AppColors.successContainer,
        isUrdu ? 'میرا ڈیٹا اور پرائیویسی' : 'My data & privacy',
        () => context.push(AppRoutes.privacy),
      ),
      (
        Icons.notifications_rounded,
        AppColors.peach,
        AppColors.peachContainer,
        isUrdu ? 'نوٹیفیکیشنز' : 'Notifications',
        () => context.push(AppRoutes.notifications),
      ),
      (
        Icons.support_agent_rounded,
        AppColors.sky,
        AppColors.skyContainer,
        isUrdu ? 'مدد اور تعاون' : 'Help & support',
        () => context.push(AppRoutes.helpSupport),
      ),
    ];

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(isUrdu ? 'پروفائل' : 'Profile'),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          physics: const BouncingScrollPhysics(),
          children: [
            // ─── Header ───────────────────────────────────────────────────
            HcCard(
              gradient: context.isDark ? null : AppColors.heroGradient,
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                    ),
                    child: const Icon(Icons.person_rounded,
                        size: 34, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isUrdu ? 'میرا اکاؤنٹ' : 'My account',
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: context.isDark
                                  ? context.hcTextSecondary
                                  : AppColors.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user?.phone ?? (isUrdu ? 'صارف' : 'User'),
                          style: theme.textTheme.titleLarge?.copyWith(
                              color: context.isDark
                                  ? context.hcTextPrimary
                                  : AppColors.textPrimary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                        ),
                        if (user != null) ...[
                          const SizedBox(height: 8),
                          HcPill(
                            label: _role(user.role, isUrdu),
                            icon: Icons.favorite_rounded,
                            color: AppColors.secondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // ─── Settings list (one grouped card) ─────────────────────────
            HcCard(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          indent: 70,
                          endIndent: 16,
                          color: context.hcOutline.withValues(alpha: 0.5)),
                    _SettingsTile(
                      icon: items[i].$1,
                      color: items[i].$2,
                      tint: items[i].$3,
                      title: items[i].$4,
                      onTap: items[i].$5,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Logout: clear but not alarming.
            OutlinedButton.icon(
              onPressed: () async {
                await authProvider.logout();
                if (context.mounted) {
                  context.go(AppRoutes.login);
                }
              },
              icon: const Icon(Icons.logout_rounded),
              label: Text(isUrdu ? 'لاگ آؤٹ' : 'Log out'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(
                    color: AppColors.error.withValues(alpha: 0.4), width: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color tint;
  final String title;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.color,
    required this.tint,
    required this.title,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            HcIconBadge(icon: icon, color: color, background: tint, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.hcTextHint),
          ],
        ),
      ),
    );
  }
}
