import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';
import '../../providers/auth_provider.dart';
import '../../core/routing/app_router.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isUrdu = languageProvider.isUrdu;
    final user = authProvider.user;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isUrdu ? 'پروفائل' : 'Profile',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          physics: const BouncingScrollPhysics(),
          children: [
            // ─── Avatar & Name ───────────────────────────────────────────────
            Center(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryContainer,
                  border: Border.all(color: AppColors.primary, width: 2),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  size: 50,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              user?.phone ?? (isUrdu ? 'صارف' : 'User'),
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineMedium,
            ),
            if (user != null) ...[
              const SizedBox(height: 4),
              Text(
                (user.role).toUpperCase(),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: context.hcTextSecondary),
              ),
            ],
            const SizedBox(height: 32),

            // ─── Settings List ───────────────────────────────────────────────
            
            // Language Toggle
            _SettingsTile(
              icon: Icons.language_rounded,
              title: isUrdu ? 'زبان کی ترجیحات' : 'Language Preferences',
              trailing: Container(
                decoration: BoxDecoration(
                  color: context.hcSurfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (isUrdu) languageProvider.toggleLocale();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: !isUrdu ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'English',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: !isUrdu ? Colors.white : AppColors.textSecondary,
                            fontWeight: !isUrdu ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (!isUrdu) languageProvider.toggleLocale();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isUrdu ? AppColors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Urdu',
                          style: AppTextStyles.labelMedium.copyWith(
                            color: isUrdu ? Colors.white : AppColors.textSecondary,
                            fontWeight: isUrdu ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // My Data & Privacy
            _SettingsTile(
              icon: Icons.shield_outlined,
              title: isUrdu ? 'میرا ڈیٹا اور پرائیویسی' : 'My Data & Privacy',
              onTap: () {
                context.push(AppRoutes.privacy);
              },
            ),
            const SizedBox(height: 16),

            // Notifications
            _SettingsTile(
              icon: Icons.notifications_none_rounded,
              title: isUrdu ? 'نوٹیفیکیشنز' : 'Notifications',
              onTap: () {
                context.push(AppRoutes.notifications);
              },
            ),
            const SizedBox(height: 16),

            // Help & Support
            _SettingsTile(
              icon: Icons.help_outline_rounded,
              title: isUrdu ? 'مدد اور تعاون' : 'Help & Support',
            ),
            const SizedBox(height: 32),

            // Logout Button
            ElevatedButton.icon(
              onPressed: () async {
                await authProvider.logout();
                if (context.mounted) {
                  context.go(AppRoutes.login);
                }
              },
              icon: Icon(Icons.logout_rounded),
              label: Text(isUrdu ? 'لاگ آؤٹ' : 'Log Out'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
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
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.titleSmall.copyWith(fontSize: 15),
                  ),
                ),
                if (trailing != null) trailing!
                else Icon(Icons.chevron_right_rounded, color: context.hcTextSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
