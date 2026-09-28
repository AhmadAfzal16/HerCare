/// Application-wide constants.
/// Never hard-code these values elsewhere in the codebase.
abstract final class AppConstants {
  AppConstants._();

  // ─── API ──────────────────────────────────────────────────────────────────
  /// Uses localhost via `adb reverse tcp:5000 tcp:5000` tunnel.
  /// Run: adb reverse tcp:5000 tcp:5000  before flutter run.
  static const String apiBaseUrl = 'http://localhost:5000/api/v1';
  static const Duration apiTimeout = Duration(seconds: 30);
  static const int maxRetryAttempts = 3;

  // ─── Auth ─────────────────────────────────────────────────────────────────
  static const String accessTokenKey = 'access_token';
  static const String refreshTokenKey = 'refresh_token';
  static const String userIdKey = 'user_id';
  static const String languageKey = 'app_language';
  static const String onboardingCompleteKey = 'onboarding_complete';

  // ─── Onboarding ───────────────────────────────────────────────────────────
  static const int totalOnboardingSteps = 4;

  // ─── Screening ────────────────────────────────────────────────────────────
  static const int epdsQuestionCount = 10;
  static const int epdsMaxScore = 30;

  // EPDS threshold bands (clinical cutoffs)
  static const int epdsLowThreshold = 9;
  static const int epsModerateThreshold = 12;
  static const int epdsHighThreshold = 20;

  // ─── Crisis ───────────────────────────────────────────────────────────────
  /// EPDS Q10 — any non-zero answer triggers crisis flow
  static const int epdsQ10Index = 9;

  // ─── Helplines ────────────────────────────────────────────────────────────
  static const String umangHelpline = '0317-4288665';
  static const String rozanHelpline = '051-2890505';
  static const String taskeen = '0311-7786264';

  // ─── Validation ───────────────────────────────────────────────────────────
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int phoneOtpLength = 6;

  // ─── Pagination ───────────────────────────────────────────────────────────
  static const int defaultPageSize = 20;

  // ─── Animation durations ──────────────────────────────────────────────────
  static const Duration animFast = Duration(milliseconds: 200);
  static const Duration animNormal = Duration(milliseconds: 350);
  static const Duration animSlow = Duration(milliseconds: 600);
  static const Duration splashDuration = Duration(milliseconds: 2500);
}
