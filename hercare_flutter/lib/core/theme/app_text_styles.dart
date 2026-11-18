import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Typography: Nunito (soft, rounded and very readable) for Latin text and
/// Noto Nastaliq Urdu for Urdu text. Follows the Material 3 type scale, with
/// tighter letter spacing so labels stay compact on small phones. Line height is
/// left to each font so Urdu fallback glyphs keep their natural, taller lines.
abstract final class AppTextStyles {
  AppTextStyles._();

  static TextStyle _nunito(double size, FontWeight weight,
          {double spacing = 0}) =>
      GoogleFonts.nunito(
          fontSize: size, fontWeight: weight, letterSpacing: spacing);

  // ─── Display ─────────────────────────────────────────────────────────────
  static TextStyle get displayLarge =>
      _nunito(54, FontWeight.w800, spacing: -1);
  static TextStyle get displayMedium =>
      _nunito(42, FontWeight.w800, spacing: -0.8);
  static TextStyle get displaySmall =>
      _nunito(34, FontWeight.w800, spacing: -0.5);

  // ─── Headline ────────────────────────────────────────────────────────────
  static TextStyle get headlineLarge =>
      _nunito(30, FontWeight.w800, spacing: -0.4);
  static TextStyle get headlineMedium =>
      _nunito(26, FontWeight.w800, spacing: -0.3);
  static TextStyle get headlineSmall =>
      _nunito(22, FontWeight.w800, spacing: -0.2);

  // ─── Title ───────────────────────────────────────────────────────────────
  static TextStyle get titleLarge =>
      _nunito(20, FontWeight.w800, spacing: -0.1);
  static TextStyle get titleMedium => _nunito(16, FontWeight.w700);
  static TextStyle get titleSmall => _nunito(14.5, FontWeight.w700);

  // ─── Body ────────────────────────────────────────────────────────────────
  static TextStyle get bodyLarge => _nunito(16, FontWeight.w500, spacing: 0.1);
  static TextStyle get bodyMedium => _nunito(14, FontWeight.w500, spacing: 0.1);
  static TextStyle get bodySmall =>
      _nunito(12.5, FontWeight.w500, spacing: 0.1);

  // ─── Label ───────────────────────────────────────────────────────────────
  static TextStyle get labelLarge =>
      _nunito(14.5, FontWeight.w800, spacing: 0.1);
  static TextStyle get labelMedium =>
      _nunito(12.5, FontWeight.w700, spacing: 0.1);
  static TextStyle get labelSmall =>
      _nunito(11.5, FontWeight.w700, spacing: 0.2);

  // ─── Urdu Typography ─────────────────────────────────────────────────────
  /// Use for Urdu body text, questions (EPDS), and journal entries.
  static TextStyle get urduBody => GoogleFonts.notoNastaliqUrdu(
        fontSize: 18,
        height: 2.2, // Nastaliq needs extra line height
        color: AppColors.textPrimary,
      );

  static TextStyle get urduHeadline => GoogleFonts.notoNastaliqUrdu(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 2.2,
        color: AppColors.textPrimary,
      );

  static TextStyle get urduLabel => GoogleFonts.notoNastaliqUrdu(
        fontSize: 14,
        height: 2.0,
        color: AppColors.textSecondary,
      );

  // ─── Material 3 TextTheme ────────────────────────────────────────────────
  static TextTheme get textTheme => TextTheme(
        displayLarge: displayLarge,
        displayMedium: displayMedium,
        displaySmall: displaySmall,
        headlineLarge: headlineLarge,
        headlineMedium: headlineMedium,
        headlineSmall: headlineSmall,
        titleLarge: titleLarge,
        titleMedium: titleMedium,
        titleSmall: titleSmall,
        bodyLarge: bodyLarge,
        bodyMedium: bodyMedium,
        bodySmall: bodySmall,
        labelLarge: labelLarge,
        labelMedium: labelMedium,
        labelSmall: labelSmall,
      );
}
