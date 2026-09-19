import 'package:flutter/material.dart';

/// HerCare Brand Color Palette
/// Derived from the UI/UX mockups: warm rose-violet palette
/// evoking care, calm, and trust — appropriate for maternal mental health.
///
/// To update the brand, only change values here. Theme picks them up automatically.
abstract final class AppColors {
  AppColors._();

  // ─── Primary (Deep Violet-Purple) ────────────────────────────────────────
  static const Color primary = Color(0xFF7C3AED);         // Violet 600
  static const Color primaryLight = Color(0xFFA78BFA);    // Violet 400
  static const Color primaryDark = Color(0xFF5B21B6);     // Violet 800
  static const Color primaryContainer = Color(0xFFEDE9FE); // Violet 100
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color onPrimaryContainer = Color(0xFF4C1D95); // Violet 900

  // ─── Secondary (Warm Rose) ────────────────────────────────────────────────
  static const Color secondary = Color(0xFFEC4899);       // Pink 500
  static const Color secondaryLight = Color(0xFFF9A8D4);  // Pink 300
  static const Color secondaryDark = Color(0xFFBE185D);   // Pink 700
  static const Color secondaryContainer = Color(0xFFFCE7F3); // Pink 100
  static const Color onSecondary = Color(0xFFFFFFFF);
  static const Color onSecondaryContainer = Color(0xFF831843); // Pink 900

  // ─── Accent / Success (Teal) ──────────────────────────────────────────────
  static const Color accent = Color(0xFF06B6D4);          // Cyan 500
  static const Color success = Color(0xFF10B981);         // Emerald 500
  static const Color successContainer = Color(0xFFD1FAE5); // Emerald 100

  // ─── Warning ──────────────────────────────────────────────────────────────
  static const Color warning = Color(0xFFF59E0B);         // Amber 500
  static const Color warningContainer = Color(0xFFFEF3C7); // Amber 100

  // ─── Error (Crisis Red) ───────────────────────────────────────────────────
  static const Color error = Color(0xFFEF4444);           // Red 500
  static const Color errorContainer = Color(0xFFFEE2E2);  // Red 100
  static const Color onError = Color(0xFFFFFFFF);

  // ─── Crisis / Emergency ───────────────────────────────────────────────────
  static const Color crisis = Color(0xFFDC2626);          // Red 600 — urgent
  static const Color crisisContainer = Color(0xFFFEF2F2);

  // ─── Background / Surface ─────────────────────────────────────────────────
  static const Color background = Color(0xFFFDF4FF);      // Faint violet-white
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF3F4F6);  // Gray 100
  static const Color outline = Color(0xFFD1D5DB);         // Gray 300
  static const Color inputFill = Color(0xFFF9F5FF);       // Very light violet

  // ─── Text ─────────────────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFF1A1135);     // Near-black violet
  static const Color textSecondary = Color(0xFF6B7280);   // Gray 500
  static const Color textHint = Color(0xFF9CA3AF);        // Gray 400
  static const Color textOnDark = Color(0xFFFFFFFF);

  // ─── Gradient Presets ─────────────────────────────────────────────────────
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [primary, secondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient splashGradient = LinearGradient(
    colors: [Color(0xFF5B21B6), Color(0xFF7C3AED), Color(0xFFEC4899)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    stops: [0.0, 0.5, 1.0],
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFFFDF4FF), Color(0xFFFCE7F3)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // ─── Onboarding Step Colors ───────────────────────────────────────────────
  static const List<Color> onboardingStepColors = [
    Color(0xFF7C3AED), // Step 1 – Personal
    Color(0xFFEC4899), // Step 2 – Obstetric
    Color(0xFF06B6D4), // Step 3 – Family
    Color(0xFF10B981), // Step 4 – Consent
  ];
}
