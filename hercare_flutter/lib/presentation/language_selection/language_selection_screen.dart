import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_constants.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/services/local_storage_service.dart';
import '../../providers/language_provider.dart';

/// Language Selection Screen
/// Shown once on first launch. Persists selection to SharedPreferences.
/// Designed to work without requiring a language to read the UI itself
/// (both options are always displayed bilingual).
class LanguageSelectionScreen extends StatelessWidget {
  const LanguageSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: SafeArea(
          child: Column(
            children: [
              // ── Top decorative area ────────────────────────────────────
              const Spacer(flex: 2),
              _buildHeroSection(),
              const Spacer(flex: 1),

              // ── Language cards ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    _LanguageCard(
                      emoji: '🇬🇧',
                      title: 'English',
                      subtitle: 'Continue in English',
                      locale: const Locale('en'),
                      onTap: () => _selectLanguage(context, 'en'),
                    ),
                    const SizedBox(height: 16),
                    _LanguageCard(
                      emoji: '🇵🇰',
                      title: 'اردو',
                      subtitle: 'اردو میں جاری رکھیں',
                      locale: const Locale('ur'),
                      isUrdu: true,
                      onTap: () => _selectLanguage(context, 'ur'),
                    ),
                  ],
                ),
              ),

              const Spacer(flex: 1),

              // ── Already have account? ──────────────────────────────────
              TextButton(
                onPressed: () => context.go(AppRoutes.login),
                child: Text(
                  'Already have an account? Log in\n'
                  'پہلے سے اکاؤنٹ ہے؟ لاگ ان کریں',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.white.withValues(alpha: 0.5),
                    height: 1.8,
                  ),
                ),
              ),

              const Spacer(flex: 1),

              // ── Footer note ───────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.only(bottom: 32, left: 24, right: 24),
                child: Text(
                  'You can change this anytime in Settings.\n'
                  'آپ اسے کسی بھی وقت ترتیبات میں تبدیل کر سکتی ہیں۔',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.65),
                    height: 1.8,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    return Column(
      children: [
        // Logo
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.favorite_rounded,
            size: 40,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'HerCare',
          style: AppTextStyles.headlineMedium.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Select Your Language',
          style: AppTextStyles.titleMedium.copyWith(
            color: Colors.white.withValues(alpha: 0.8),
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'زبان منتخب کریں',
          style: AppTextStyles.urduBody.copyWith(
            color: Colors.white.withValues(alpha: 0.65),
            fontSize: 16,
          ),
          textDirection: TextDirection.rtl,
        ),
      ],
    );
  }

  Future<void> _selectLanguage(BuildContext context, String code) async {
    final langProvider = context.read<LanguageProvider>();
    final storage = LocalStorageService();

    await storage.setString(AppConstants.languageKey, code);
    langProvider.setLocale(Locale(code));

    if (context.mounted) {
      context.go(AppRoutes.register);
    }
  }
}

/// Individual language option card with ripple and elevation animation.
class _LanguageCard extends StatefulWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final Locale locale;
  final bool isUrdu;
  final VoidCallback onTap;

  const _LanguageCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.locale,
    required this.onTap,
    this.isUrdu = false,
  });

  @override
  State<_LanguageCard> createState() => _LanguageCardState();
}

class _LanguageCardState extends State<_LanguageCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressCtrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
      lowerBound: 0.96,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _pressCtrl;
  }

  @override
  void dispose() {
    _pressCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressCtrl.reverse(),
      onTapUp: (_) {
        _pressCtrl.forward();
        widget.onTap();
      },
      onTapCancel: () => _pressCtrl.forward(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.5,
            ),
          ),
          child: Row(
            textDirection:
                widget.isUrdu ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 30)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: widget.isUrdu
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: widget.isUrdu
                          ? AppTextStyles.urduHeadline.copyWith(
                              color: Colors.white,
                              fontSize: 20,
                            )
                          : AppTextStyles.titleMedium
                              .copyWith(color: Colors.white),
                      textDirection:
                          widget.isUrdu ? TextDirection.rtl : TextDirection.ltr,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: widget.isUrdu
                          ? AppTextStyles.urduLabel.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            )
                          : AppTextStyles.bodySmall.copyWith(
                              color: Colors.white.withValues(alpha: 0.75),
                            ),
                      textDirection:
                          widget.isUrdu ? TextDirection.rtl : TextDirection.ltr,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                widget.isUrdu
                    ? Icons.arrow_back_ios_rounded
                    : Icons.arrow_forward_ios_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
