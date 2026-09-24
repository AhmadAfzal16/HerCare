import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../presentation/splash/splash_screen.dart';
import '../../presentation/language_selection/language_selection_screen.dart';
import '../../presentation/onboarding/onboarding_wizard.dart';
import '../../presentation/auth/register_screen.dart';
import '../../presentation/auth/login_screen.dart';
import '../../presentation/auth/account_type_screen.dart';
import '../../presentation/home/home_screen.dart';
import '../../presentation/epds/epds_screen.dart';
import '../../presentation/epds/epds_result_screen.dart';
import '../../presentation/epds/screening_history_screen.dart';
import '../../presentation/risk/risk_insights_screen.dart';
import '../../data/models/screening_models.dart';
import '../../presentation/notifications/notifications_screen.dart';
import '../../presentation/privacy/privacy_screen.dart';
import '../../presentation/settings/settings_screen.dart';
import '../../presentation/profile/profile_screen.dart';
import '../../presentation/guardian/guardian_link_screen.dart';
import '../../presentation/guardian/guardian_dashboard_screen.dart';
import '../../presentation/guardian/report_screen.dart';
import '../../presentation/guardian/guardian_home_screen.dart';
import '../../providers/auth_provider.dart';
import '../../presentation/mood/mood_journal_screen.dart';
import '../../presentation/crisis/crisis_support_screen.dart';
import '../../presentation/chat/secure_chat_screen.dart';

/// Central routing configuration using go_router.
///
/// Route names are string constants — update here only, never inline strings.
/// Guards (redirect) check auth state and onboarding completion.
abstract final class AppRoutes {
  AppRoutes._();
  static const String splash = '/';
  static const String languageSelection = '/language';
  static const String onboarding = '/onboarding';
  static const String register = '/register';
  static const String accountType = '/account-type';
  static const String login = '/login';
  static const String home = '/home'; // Phase 2
  static const String guardianHome = '/guardian-home';
  static const String epds = '/epds'; // Phase 1
  static const String phq9 = '/phq9';
  static const String epdsResult = '/epds-result'; // Phase 1
  static const String screeningHistory = '/screening-history';
  static const String riskInsights = '/risk-insights';
  static const String notifications = '/notifications';
  static const String privacy = '/privacy';
  static const String settings = '/settings';
  static const String helpSupport = '/help-support';
  static const String profile = '/profile';
  static const String guardianLink = '/guardian-link';
  static const String guardianDashboard = '/guardian-dashboard';
  static const String reports = '/reports';
  static const String mood = '/mood';
  static const String journal = '/journal';
  static const String chatbot = '/chatbot'; // Phase 2
  static const String crisis = '/crisis'; // Phase 3
  static const String secureChat = '/secure-chat';
}

abstract final class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.languageSelection,
        name: 'languageSelection',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LanguageSelectionScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const OnboardingWizard(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        name: 'register',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RegisterScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.accountType,
        name: 'account-type',
        redirect: (_, state) =>
            state.extra is PendingRegistration ? null : AppRoutes.register,
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: AccountTypeScreen(
            registration: state.extra! as PendingRegistration,
          ),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const LoginScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const _RoleAwareHome(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.guardianHome,
        name: 'guardian-home',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const _RoleAwareHome(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.epds,
        name: 'epds',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const EpdsScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.phq9,
        name: 'phq9',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const EpdsScreen(instrumentType: 'phq9'),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.epdsResult,
        name: 'epds-result',
        redirect: (_, state) =>
            state.extra is ScreeningAssessment ? null : AppRoutes.epds,
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: EpdsResultScreen(
            assessment: state.extra! as ScreeningAssessment,
          ),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.screeningHistory,
        name: 'screening-history',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ScreeningHistoryScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.riskInsights,
        name: 'risk-insights',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const RiskInsightsScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        name: 'notifications',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const NotificationsScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        name: 'privacy',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const PrivacyScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SettingsScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ProfileScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.helpSupport,
        name: 'help-support',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const _HelpSupportScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.guardianLink,
        name: 'guardian-link',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const GuardianLinkScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.guardianDashboard,
        name: 'guardian-dashboard',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const GuardianDashboardScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.reports,
        name: 'reports',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const ReportScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.mood,
        name: 'mood',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: MoodJournalScreen(initialMood: state.extra as int?),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.journal,
        name: 'journal',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const MoodJournalScreen(initialTab: 1),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.crisis,
        name: 'crisis',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const CrisisSupportScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.secureChat,
        name: 'secure-chat',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: const SecureChatScreen(),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
    ],

    // 404 fallback
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Text('Page not found: ${state.uri}'),
      ),
    ),
  );

  // ─── Shared Page Transition ───────────────────────────────────────────────
  static Widget _fadeSlideTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.05, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      )),
      child: FadeTransition(opacity: animation, child: child),
    );
  }
}

/// Keeps role-specific home interfaces separated even when an old bookmark or
/// deep link points at the other role's route.
class _RoleAwareHome extends StatelessWidget {
  const _RoleAwareHome();

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    if (user?.isGuardian == true) return const GuardianHomeScreen();
    if (user?.isMother == true) return const HomeScreen();

    // Splash restores the server session before normal navigation. This
    // fallback avoids exposing either role interface during a direct deep link.
    return const SplashScreen();
  }
}

/// Placeholder Help & Support screen
class _HelpSupportScreen extends StatelessWidget {
  const _HelpSupportScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFDF4FF),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Help & Support'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const Center(
        child: Text('Help & Support — Coming Soon'),
      ),
    );
  }
}
