import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/theme_provider.dart';
import '../../core/routing/app_router.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final authProvider = context.watch<AuthProvider>();
    final isUrdu = languageProvider.isUrdu;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isUrdu ? 'ترتیبات' : 'Settings',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.hcTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          physics: const BouncingScrollPhysics(),
          children: [
            // ── Account Section ──────────────────────────────────────────────
            _SectionHeader(title: isUrdu ? 'اکاؤنٹ' : 'Account'),
            _SettingsTile(
              icon: Icons.person_outline_rounded,
              iconColor: AppColors.primary,
              title: isUrdu ? 'پروفائل' : 'Profile',
              subtitle:
                  isUrdu ? 'اپنی معلومات دیکھیں' : 'View your information',
              onTap: () => context.push(AppRoutes.profile),
            ),
            _SettingsTile(
              icon: Icons.shield_outlined,
              iconColor: AppColors.primary,
              title: isUrdu ? 'میرا ڈیٹا اور پرائیویسی' : 'My Data & Privacy',
              subtitle: isUrdu
                  ? 'رضامندی اور ڈیٹا کا انتظام'
                  : 'Manage consent & data',
              onTap: () => context.push(AppRoutes.privacy),
            ),
            _SettingsTile(
              icon: Icons.family_restroom_rounded,
              iconColor: AppColors.primary,
              title: isUrdu ? 'سرپرست اور فیملی' : 'Guardian & Family',
              subtitle:
                  isUrdu ? 'رسائی کا انتظام کریں' : 'Manage guardian access',
              onTap: () => context.push(AppRoutes.guardianLink),
            ),

            const SizedBox(height: 8),

            // ── Preferences Section ──────────────────────────────────────────
            _SectionHeader(title: isUrdu ? 'ترجیحات' : 'Preferences'),
            _LanguageTile(isUrdu: isUrdu, languageProvider: languageProvider),
            _SettingsTile(
              icon: Icons.library_music_outlined,
              iconColor: AppColors.primary,
              title: isUrdu
                  ? 'آپ کے لیے مواد اور ترجیحات'
                  : 'For You & content preferences',
              subtitle: isUrdu
                  ? 'مذہبی مواد، موسیقی اور محفوظ مضامین'
                  : 'Islamic content, music and saved reading',
              onTap: () => context.push(AppRoutes.content),
            ),
            _SettingsTile(
              icon: Icons.notifications_none_rounded,
              iconColor: AppColors.secondary,
              title: isUrdu ? 'نوٹیفیکیشنز' : 'Notifications',
              subtitle: isUrdu ? 'یاد دہانیاں ترتیب دیں' : 'Set up reminders',
              onTap: () => context.push(AppRoutes.notifications),
            ),
            _ThemeModeTile(isUrdu: isUrdu),

            const SizedBox(height: 8),

            // ── Support Section ──────────────────────────────────────────────
            _SectionHeader(title: isUrdu ? 'مدد' : 'Support'),
            _SettingsTile(
              icon: Icons.help_outline_rounded,
              iconColor: AppColors.accent,
              title: isUrdu ? 'مدد اور تعاون' : 'Help & Support',
              subtitle: isUrdu ? 'ایپ استعمال کرنے میں مدد' : 'Using HerCare',
              onTap: () => context.push(AppRoutes.helpSupport),
            ),
            _SettingsTile(
              icon: Icons.info_outline_rounded,
              iconColor: AppColors.accent,
              title: isUrdu ? 'ایپ کے بارے میں' : 'About App',
              subtitle: 'HerCare v1.0.0',
              onTap: () => _showAboutDialog(context, isUrdu),
            ),
            const SizedBox(height: 8),

            // ── Danger Zone ──────────────────────────────────────────────────
            _SectionHeader(title: isUrdu ? 'سیشن' : 'Session'),
            _SettingsTile(
              icon: Icons.logout_rounded,
              iconColor: AppColors.error,
              title: isUrdu ? 'لاگ آؤٹ' : 'Log Out',
              subtitle: isUrdu
                  ? 'اپنے سیشن سے باہر نکلیں'
                  : 'Sign out of your session',
              titleColor: AppColors.error,
              onTap: () async {
                final confirmed = await _showConfirmDialog(
                  context,
                  title: isUrdu ? 'لاگ آؤٹ' : 'Log Out',
                  message: isUrdu
                      ? 'کیا آپ واقعی لاگ آؤٹ کرنا چاہتے ہیں؟'
                      : 'Are you sure you want to log out?',
                  confirmLabel: isUrdu ? 'ہاں' : 'Yes, Log Out',
                  isDestructive: true,
                );
                if (confirmed && context.mounted) {
                  await authProvider.logout();
                  if (context.mounted) context.go(AppRoutes.login);
                }
              },
            ),
            const SizedBox(height: 32),

            // ── App version footer ───────────────────────────────────────────
            Center(
              child: Text(
                'HerCare • v1.0.0 • Made with ❤️',
                style: AppTextStyles.labelSmall.copyWith(
                  color: context.hcTextHint,
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  void _showAboutDialog(BuildContext context, bool isUrdu) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.hcSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(isUrdu ? 'ہر کیئر کے بارے میں' : 'About HerCare',
            style: AppTextStyles.titleMedium),
        content: Text(
          isUrdu
              ? 'HerCare ایک ذہنی صحت کا ایپ ہے جو نئی ماؤں کی مدد کے لیے بنایا گیا ہے۔\n\nورژن: 1.0.0'
              : 'HerCare is a mental health app designed to support new mothers through postpartum depression screening and care.\n\nVersion: 1.0.0',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(isUrdu ? 'بند کریں' : 'Close',
                style: const TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  Future<bool> _showConfirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.hcSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: AppTextStyles.titleMedium),
        content: Text(message, style: AppTextStyles.bodyMedium),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
                context.read<LanguageProvider>().isUrdu ? 'منسوخ' : 'Cancel',
                style: TextStyle(color: context.hcTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel,
                style: TextStyle(
                    color: isDestructive ? AppColors.error : AppColors.primary,
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ── Section Header ─────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
      child: Text(
        title.toUpperCase(),
        style: AppTextStyles.labelSmall.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

// ── Generic Settings Tile ──────────────────────────────────────────────────────
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Icon badge
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: iconColor, size: 22),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: AppTextStyles.titleSmall.copyWith(
                          color: titleColor ?? context.hcTextPrimary,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                // Trailing
                Icon(Icons.chevron_right_rounded,
                    color: context.hcTextHint, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Language Toggle Tile ───────────────────────────────────────────────────────
class _LanguageTile extends StatelessWidget {
  final bool isUrdu;
  final LanguageProvider languageProvider;
  const _LanguageTile({required this.isUrdu, required this.languageProvider});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isUrdu ? 'زبان' : 'Language', style: AppTextStyles.titleSmall),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 8, children: [
              ChoiceChip(
                  label: const Text('English'),
                  selected: !isUrdu,
                  onSelected: (_) {
                    if (isUrdu) languageProvider.toggleLocale();
                  }),
              ChoiceChip(
                  label: const Text('اردو'),
                  selected: isUrdu,
                  onSelected: (_) {
                    if (!isUrdu) languageProvider.toggleLocale();
                  }),
            ]),
          ]),
        ),
      );
}

// ── Dark / Light Mode Toggle Tile ─────────────────────────────────────────────
class _ThemeModeTile extends StatelessWidget {
  final bool isUrdu;
  const _ThemeModeTile({required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDark;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.secondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: AppColors.secondary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isUrdu ? 'ڈارک موڈ' : 'Dark Mode',
                    style: AppTextStyles.titleSmall.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isUrdu
                        ? 'رات کے وقت کے لیے'
                        : 'Easier on the eyes at night',
                    style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            Switch(
              value: isDark,
              onChanged: (val) => themeProvider.setDark(val),
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
