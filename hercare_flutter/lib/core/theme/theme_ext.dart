import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_theme.dart';

/// Theme-aware color helpers.
/// Use `context.hcBg`, `context.hcSurface`, etc. everywhere instead of
/// `AppColors.background` / `AppColors.surface` so dark mode works.
extension HerCareTheme on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  // ── Backgrounds ───────────────────────────────────────────────────────────
  Color get hcBg => isDark ? AppTheme.darkBg : AppColors.background;

  Color get hcSurface => isDark ? AppTheme.darkSurface : AppColors.surface;

  Color get hcSurfaceVariant =>
      isDark ? AppTheme.darkSurfaceVariant : AppColors.surfaceVariant;

  Color get hcInputFill =>
      isDark ? AppTheme.darkSurfaceVariant : AppColors.inputFill;

  // ── Text ──────────────────────────────────────────────────────────────────
  Color get hcTextPrimary => isDark ? AppTheme.darkText : AppColors.textPrimary;

  Color get hcTextSecondary =>
      isDark ? AppTheme.darkSubText : AppColors.textSecondary;

  Color get hcTextHint => isDark ? AppTheme.darkHint : AppColors.textHint;

  // ── Borders ───────────────────────────────────────────────────────────────
  Color get hcOutline => isDark ? AppTheme.darkOutline : AppColors.outline;

  // ── Shadows ───────────────────────────────────────────────────────────────
  /// Soft, violet-tinted shadow for floating cards (none in dark mode).
  List<BoxShadow> get hcSoftShadow => isDark
      ? const []
      : [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ];

  // ── Convenience shorthand ─────────────────────────────────────────────────
  /// Scaffold background — use as backgroundColor on Scaffold / AppBar.
  Color get bg => hcBg;

  /// Card / Container surface.
  Color get sf => hcSurface;
}
