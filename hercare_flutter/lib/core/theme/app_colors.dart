import 'package:flutter/material.dart';

/// HerCare brand palette — "soft sunrise".
///
/// A calm iris-violet brand colour with fresh, happy accents (rose, mint, sky,
/// peach) on an airy lavender-white background. Every text/background pair used
/// for body text meets WCAG AA contrast.
///
/// To update the brand, only change values here. Theme picks them up automatically.
abstract final class AppColors {
  AppColors._();

  // ─── Primary (Iris violet) ───────────────────────────────────────────────
  static const Color primary = Color(0xFF6B4EE6);
  static const Color primaryLight = Color(0xFFA594F9);
  static const Color primaryDark = Color(0xFF4F35C2);
  static const Color primaryContainer = Color(0xFFEFEBFF);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF2C1D7A);

  // ─── Secondary (Warm rose) ───────────────────────────────────────────────
  static const Color secondary = Color(0xFFD6457A);
  static const Color secondaryLight = Color(0xFFF7A1BF);
  static const Color secondaryDark = Color(0xFFA82E5C);
  static const Color secondaryContainer = Color(0xFFFFE6EE);
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF6E1238);

  // ─── Fresh accents ───────────────────────────────────────────────────────
  static const Color accent = Color(0xFF0E9AAE); // Lagoon teal
  static const Color accentContainer = Color(0xFFDDF5F8);
  static const Color success = Color(0xFF17A077); // Mint
  static const Color successContainer = Color(0xFFDCF5EC);
  static const Color sky = Color(0xFF3B7FE8);
  static const Color skyContainer = Color(0xFFE3EDFF);
  static const Color peach = Color(0xFFE9774F);
  static const Color peachContainer = Color(0xFFFFEBE2);

  // ─── Warning ─────────────────────────────────────────────────────────────
  static const Color warning = Color(0xFFD98324);
  static const Color warningContainer = Color(0xFFFFF0DC);

  // ─── Error (Crisis red) ──────────────────────────────────────────────────
  static const Color error = Color(0xFFE0434A);
  static const Color errorContainer = Color(0xFFFFE5E6);
  static const Color onError = Color(0xFFFFFFFF);

  // ─── Crisis / Emergency ──────────────────────────────────────────────────
  static const Color crisis = Color(0xFFD12F35);
  static const Color crisisContainer = Color(0xFFFFF0F0);

  // ─── Background / Surface ────────────────────────────────────────────────
  static const Color background = Color(0xFFF7F5FC); // Airy lavender-white
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF2EFFA);
  static const Color outline = Color(0xFFDDD7EE);
  static const Color inputFill = Color(0xFFFAF8FF);

  // ─── Text ────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1F1B33); // Deep ink
  static const Color textSecondary = Color(0xFF625C7A);
  static const Color textHint = Color(0xFF9B96B0);
  static const Color textOnDark = Color(0xFFFFFFFF);

  // ─── Soft shadow used by cards and floating surfaces ─────────────────────
  static const Color shadow = Color(0xFF3C2A8C);

  // ─── Gradient presets ────────────────────────────────────────────────────
  /// Brand gradient for buttons, avatars and badges (white text is readable).
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFF6B4EE6), Color(0xFF9B55D6)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Light "sunrise" wash for hero cards (use dark ink text on top).
  static const LinearGradient heroGradient = LinearGradient(
    colors: [Color(0xFFE9E3FF), Color(0xFFFBE4F0), Color(0xFFFFEFE2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF4F35C2), Color(0xFF6B4EE6), Color(0xFFC0569C)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFF6F2FF), Color(0xFFFFEEF4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ─── Onboarding step colours ─────────────────────────────────────────────
  static const List<Color> onboardingStepColors = [
    primary, // Step 1 – Personal
    secondary, // Step 2 – Obstetric
    accent, // Step 3 – Family
    success, // Step 4 – Consent
  ];
}
