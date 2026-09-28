import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Theme-aware color helpers.
/// Use `context.hcBg`, `context.hcSurface`, etc. everywhere instead of
/// `AppColors.background` / `AppColors.surface` so dark mode works.
extension HerCareTheme on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // ── Backgrounds ───────────────────────────────────────────────────────────
  Color get hcBg =>
      isDark ? const Color(0xFF0F0A1E) : AppColors.background;

  Color get hcSurface =>
      isDark ? const Color(0xFF1C1531) : AppColors.surface;

  Color get hcSurfaceVariant =>
      isDark ? const Color(0xFF251E3A) : AppColors.surfaceVariant;

  Color get hcInputFill =>
      isDark ? const Color(0xFF251E3A) : AppColors.inputFill;

  // ── Text ──────────────────────────────────────────────────────────────────
  Color get hcTextPrimary =>
      isDark ? const Color(0xFFF3EEFF) : AppColors.textPrimary;

  Color get hcTextSecondary =>
      isDark ? const Color(0xFF9E8FBD) : AppColors.textSecondary;

  Color get hcTextHint =>
      isDark ? const Color(0xFF6B5F8A) : AppColors.textHint;

  // ── Borders ───────────────────────────────────────────────────────────────
  Color get hcOutline =>
      isDark ? const Color(0xFF3A2F5A) : AppColors.outline;

  // ── Convenience shorthand ─────────────────────────────────────────────────
  /// Scaffold background — use as backgroundColor on Scaffold / AppBar.
  Color get bg => hcBg;

  /// Card / Container surface.
  Color get sf => hcSurface;
}
