import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';

/// Central theme configuration for HerCare.
/// All colour, typography and component styling lives here, so every screen
/// shares one calm, consistent look. Change values in [AppColors] or
/// [AppTextStyles] to update the brand globally.
class AppTheme {
  AppTheme._(); // prevent instantiation

  // Dark palette (soft night violet, never pure black).
  static const darkBg = Color(0xFF13111C);
  static const darkSurface = Color(0xFF1D1A2B);
  static const darkSurfaceVariant = Color(0xFF282339);
  static const darkText = Color(0xFFF1EEFA);
  static const darkSubText = Color(0xFFADA7C6);
  static const darkHint = Color(0xFF7D7797);
  static const darkOutline = Color(0xFF38324F);
  static const darkPrimary = Color(0xFFB4A6FF);

  static ThemeData get lightTheme => _build(Brightness.light);
  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final bg = dark ? darkBg : AppColors.background;
    final surface = dark ? darkSurface : AppColors.surface;
    final surfaceVariant = dark ? darkSurfaceVariant : AppColors.surfaceVariant;
    final text = dark ? darkText : AppColors.textPrimary;
    final subText = dark ? darkSubText : AppColors.textSecondary;
    final hint = dark ? darkHint : AppColors.textHint;
    final outline = dark ? darkOutline : AppColors.outline;
    final primary = dark ? darkPrimary : AppColors.primary;
    final onPrimary = dark ? const Color(0xFF23146B) : AppColors.onPrimary;
    final primaryContainer =
        dark ? const Color(0xFF362A73) : AppColors.primaryContainer;
    final onPrimaryContainer =
        dark ? const Color(0xFFE9E4FF) : AppColors.onPrimaryContainer;

    final scheme = ColorScheme(
      brightness: brightness,
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      onPrimaryContainer: onPrimaryContainer,
      secondary: dark ? AppColors.secondaryLight : AppColors.secondary,
      onSecondary: dark ? const Color(0xFF5A0F2E) : AppColors.onSecondary,
      secondaryContainer:
          dark ? const Color(0xFF5C1D3A) : AppColors.secondaryContainer,
      onSecondaryContainer:
          dark ? const Color(0xFFFFE3EC) : AppColors.onSecondaryContainer,
      tertiary: dark ? const Color(0xFF6FD3E0) : AppColors.accent,
      onTertiary: dark ? const Color(0xFF003740) : Colors.white,
      tertiaryContainer:
          dark ? const Color(0xFF0F4B55) : AppColors.accentContainer,
      onTertiaryContainer:
          dark ? const Color(0xFFCFF4F8) : const Color(0xFF00424C),
      error: AppColors.error,
      onError: AppColors.onError,
      errorContainer: dark ? const Color(0xFF5C1A1E) : AppColors.errorContainer,
      onErrorContainer:
          dark ? const Color(0xFFFFDADB) : const Color(0xFF7A1418),
      surface: surface,
      onSurface: text,
      onSurfaceVariant: subText,
      surfaceContainerLowest: surface,
      surfaceContainerLow:
          dark ? const Color(0xFF211D31) : const Color(0xFFFBFAFE),
      surfaceContainer:
          dark ? const Color(0xFF242036) : const Color(0xFFF7F5FC),
      surfaceContainerHigh:
          dark ? const Color(0xFF282339) : const Color(0xFFF4F1FB),
      surfaceContainerHighest: surfaceVariant,
      outline: outline,
      outlineVariant: dark ? const Color(0xFF2E2942) : const Color(0xFFEAE6F4),
      shadow: AppColors.shadow,
      inverseSurface: dark ? darkText : const Color(0xFF2A2440),
      onInverseSurface: dark ? darkBg : Colors.white,
      inversePrimary: dark ? AppColors.primary : AppColors.primaryLight,
      surfaceTint: Colors.transparent,
    );

    final textTheme =
        AppTextStyles.textTheme.apply(bodyColor: text, displayColor: text);
    const pill = StadiumBorder();
    final buttonText = AppTextStyles.labelLarge;
    final softBorder = BorderSide(
        color: dark ? darkOutline : const Color(0xFFE6E1F3), width: 1.2);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      canvasColor: bg,
      fontFamily: GoogleFonts.nunito().fontFamily,
      textTheme: textTheme,
      splashFactory: InkSparkle.splashFactory,
      // No global iconTheme: an explicit one overrides the white icons that
      // filled IconButtons (e.g. the chat send button) draw on violet.

      // ─── App bar ──────────────────────────────────────────────────────────
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: true,
        titleTextStyle:
            AppTextStyles.titleLarge.copyWith(color: text, fontSize: 19),
        iconTheme: IconThemeData(color: text),
        actionsIconTheme: IconThemeData(color: text),
      ),

      // ─── Buttons ──────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          disabledBackgroundColor: outline.withValues(alpha: 0.6),
          minimumSize: const Size(double.infinity, 52),
          shape: pill,
          elevation: 0,
          shadowColor: Colors.transparent,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        ),
      ),
      // Colours are left to the defaults so FilledButton.tonal stays tonal.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 50),
          shape: pill,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          minimumSize: const Size(double.infinity, 52),
          side: BorderSide(color: primary.withValues(alpha: 0.45), width: 1.4),
          shape: pill,
          textStyle: buttonText,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: buttonText,
          shape: pill,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: onPrimary,
        elevation: 2,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        extendedTextStyle: buttonText,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: const WidgetStatePropertyAll(pill),
          side: WidgetStatePropertyAll(softBorder),
          textStyle: WidgetStatePropertyAll(AppTextStyles.labelMedium),
          backgroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? primaryContainer
                  : surface),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.selected)
                  ? onPrimaryContainer
                  : subText),
        ),
      ),

      // ─── Inputs ───────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? darkSurfaceVariant : AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: softBorder,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: softBorder,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error, width: 1.3),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide:
              softBorder.copyWith(color: outline.withValues(alpha: 0.4)),
        ),
        labelStyle: AppTextStyles.bodyMedium.copyWith(color: subText),
        floatingLabelStyle: AppTextStyles.bodyMedium
            .copyWith(color: primary, fontWeight: FontWeight.w700),
        hintStyle: AppTextStyles.bodyMedium.copyWith(color: hint),
        helperStyle: AppTextStyles.bodySmall.copyWith(color: subText),
        errorStyle: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
        prefixIconColor: subText,
        suffixIconColor: subText,
      ),

      // ─── Cards & surfaces ─────────────────────────────────────────────────
      cardTheme: CardThemeData(
        color: surface,
        elevation: dark ? 0 : 2,
        shadowColor: AppColors.shadow.withValues(alpha: 0.10),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: dark ? const BorderSide(color: darkOutline) : BorderSide.none,
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        textColor: text,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        minLeadingWidth: 28,
        horizontalTitleGap: 14,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        subtitleTextStyle: AppTextStyles.bodySmall.copyWith(color: subText),
      ),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const RoundedRectangleBorder(side: BorderSide.none),
        collapsedShape: const RoundedRectangleBorder(side: BorderSide.none),
        iconColor: primary,
        collapsedIconColor: subText,
        textColor: text,
        collapsedTextColor: text,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        titleTextStyle: AppTextStyles.titleLarge.copyWith(color: text),
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(color: subText),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        modalBackgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        dragHandleColor: outline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: AppTextStyles.bodyMedium.copyWith(color: text),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(surface),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
        ),
      ),

      // ─── Chips ────────────────────────────────────────────────────────────
      chipTheme: ChipThemeData(
        backgroundColor: surfaceVariant,
        selectedColor: primaryContainer,
        secondarySelectedColor: primaryContainer,
        disabledColor: surfaceVariant.withValues(alpha: 0.5),
        checkmarkColor: dark ? onPrimaryContainer : AppColors.primary,
        side: BorderSide.none,
        shape: pill,
        labelStyle: AppTextStyles.labelMedium.copyWith(color: text),
        secondaryLabelStyle:
            AppTextStyles.labelMedium.copyWith(color: onPrimaryContainer),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        iconTheme: IconThemeData(color: primary, size: 18),
      ),

      // ─── Selection controls ───────────────────────────────────────────────
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return outline;
          return states.contains(WidgetState.selected)
              ? (dark ? onPrimary : Colors.white)
              : (dark ? darkSubText : AppColors.textHint);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return surfaceVariant;
          return states.contains(WidgetState.selected)
              ? primary
              : (dark ? darkSurfaceVariant : const Color(0xFFE9E5F5));
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.transparent;
        }),
        checkColor: WidgetStatePropertyAll(onPrimary),
        side: BorderSide(color: primary, width: 1.8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return subText;
        }),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: primary,
        inactiveTrackColor: primaryContainer,
        thumbColor: primary,
        overlayColor: primary.withValues(alpha: 0.12),
        valueIndicatorColor: primary,
        valueIndicatorTextStyle:
            AppTextStyles.labelMedium.copyWith(color: onPrimary),
        trackHeight: 6,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: primaryContainer,
        circularTrackColor: primaryContainer,
      ),

      // ─── Navigation ───────────────────────────────────────────────────────
      tabBarTheme: TabBarThemeData(
        labelColor: primary,
        unselectedLabelColor: subText,
        labelStyle: AppTextStyles.labelLarge,
        unselectedLabelStyle:
            AppTextStyles.labelLarge.copyWith(fontWeight: FontWeight.w600),
        indicatorColor: primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: outline.withValues(alpha: 0.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primaryContainer,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            AppTextStyles.labelSmall.copyWith(
                color:
                    states.contains(WidgetState.selected) ? primary : subText,
                fontWeight: states.contains(WidgetState.selected)
                    ? FontWeight.w800
                    : FontWeight.w600)),
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : subText,
            size: 24)),
      ),

      // ─── Feedback ─────────────────────────────────────────────────────────
      dividerTheme: DividerThemeData(
        color: outline.withValues(alpha: dark ? 0.8 : 0.6),
        thickness: 1,
        space: 20,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? darkSurfaceVariant : const Color(0xFF2A2440),
        contentTextStyle: AppTextStyles.bodyMedium
            .copyWith(color: dark ? darkText : Colors.white),
        actionTextColor: dark ? darkPrimary : AppColors.primaryLight,
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? darkSurfaceVariant : const Color(0xFF2A2440),
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: AppTextStyles.bodySmall
            .copyWith(color: dark ? darkText : Colors.white),
      ),
      badgeTheme: const BadgeThemeData(
        backgroundColor: AppColors.secondary,
        textColor: Colors.white,
      ),

      // ─── Page transition ──────────────────────────────────────────────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
