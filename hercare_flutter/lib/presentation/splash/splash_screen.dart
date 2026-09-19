import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/services/local_storage_service.dart';

/// Splash Screen
/// Displays brand logo + animated tagline for [AppConstants.splashDuration],
/// then redirects based on:
///   1. Language not set → Language Selection
///   2. Onboarding not complete → Onboarding Wizard
///   3. Not logged in → Login
///   4. Logged in → Home
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _taglineOpacity;
  late final Animation<Offset> _taglineSlide;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // Logo: scale + fade in
    _logoScale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    // Tagline: slide up + fade in (delayed)
    _taglineOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 0.9, curve: Curves.easeIn),
      ),
    );
    _taglineSlide = Tween<Offset>(
      begin: const Offset(0, 0.4),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.5, 0.9, curve: Curves.easeOutCubic),
      ),
    );

    // Start animation then navigate
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      _controller.forward();
      await Future.delayed(AppConstants.splashDuration);
      if (mounted) _navigate();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _navigate() async {
    final storage = LocalStorageService();
    final language = await storage.getString(AppConstants.languageKey);
    final onboardingDone =
        await storage.getBool(AppConstants.onboardingCompleteKey) ?? false;
    final token =
        await storage.getSecureString(AppConstants.accessTokenKey);

    if (!mounted) return;

    if (language == null) {
      context.go(AppRoutes.languageSelection);
    } else if (!onboardingDone) {
      context.go(AppRoutes.onboarding);
    } else if (token == null) {
      context.go(AppRoutes.login);
    } else {
      context.go(AppRoutes.home);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppColors.splashGradient,
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Logo ──────────────────────────────────────────────────
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, child) => FadeTransition(
                    opacity: _logoOpacity,
                    child: ScaleTransition(
                      scale: _logoScale,
                      child: child,
                    ),
                  ),
                  child: _LogoWidget(),
                ),

                const SizedBox(height: 28),

                // ── App Name ──────────────────────────────────────────────
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, __) => FadeTransition(
                    opacity: _logoOpacity,
                    child: Text(
                      'HerCare',
                      style: AppTextStyles.headlineLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // ── Tagline ───────────────────────────────────────────────
                AnimatedBuilder(
                  animation: _controller,
                  builder: (_, child) => FadeTransition(
                    opacity: _taglineOpacity,
                    child: SlideTransition(
                      position: _taglineSlide,
                      child: child,
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'You are not alone.',
                        style: AppTextStyles.bodyLarge.copyWith(
                          color: Colors.white.withOpacity(0.9),
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'آپ اکیلی نہیں ہیں۔',
                        style: AppTextStyles.urduBody.copyWith(
                          color: Colors.white.withOpacity(0.75),
                          fontSize: 16,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 80),

                // ── Loading indicator ─────────────────────────────────────
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// HerCare brand logo — stylized heart with care mark.
/// Replace with SVG/Lottie asset when design provides one.
class _LogoWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.15),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withOpacity(0.35),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Icon(
        Icons.favorite_rounded,
        size: 50,
        color: Colors.white,
      ),
    );
  }
}
