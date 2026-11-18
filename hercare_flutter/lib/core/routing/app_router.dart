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
import '../../presentation/epds/tests_screen.dart';
import '../../presentation/epds/epds_result_screen.dart';
import '../../presentation/epds/screening_history_screen.dart';
import '../../presentation/risk/risk_insights_screen.dart';
import '../../data/models/screening_models.dart';
import '../../presentation/notifications/notifications_screen.dart';
import '../../presentation/privacy/privacy_screen.dart';
import '../../presentation/settings/settings_screen.dart';
import '../../presentation/settings/help_support_screen.dart';
import '../../presentation/profile/profile_screen.dart';
import '../../presentation/guardian/guardian_link_screen.dart';
import '../../presentation/guardian/guardian_dashboard_screen.dart';
import '../../presentation/guardian/report_screen.dart';
import '../../presentation/guardian/guardian_home_screen.dart';
import '../../presentation/guardian/guardian_trends_screen.dart';
import '../../providers/auth_provider.dart';
import '../../presentation/mood/mood_journal_screen.dart';
import '../../presentation/mood/journal_account_guard.dart';
import '../../presentation/crisis/crisis_support_screen.dart';
import '../../presentation/chat/secure_chat_screen.dart';
import '../../presentation/hum_raaz/hum_raaz_screen.dart';
import '../../presentation/therapy/therapy_hub_screen.dart';
import '../../presentation/therapy/therapy_account_guard.dart';
import '../../presentation/therapy/breathing_exercise_screen.dart';
import '../../presentation/therapy/meditation_screen.dart';
import '../../presentation/therapy/cbt_exercise_screen.dart';
import '../../presentation/therapy/therapy_game_screen.dart';
import '../../presentation/wellbeing/digital_wellbeing_screen.dart';
import '../../presentation/community/community_screen.dart';
import '../../presentation/content/content_screen.dart';
import '../../presentation/content/content_admin_screen.dart';
import '../../presentation/admin/admin_workspace_screen.dart';

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
  static const String home = '/home';
  static const String guardianHome = '/guardian-home';
  static const String epds = '/epds';
  static const String phq9 = '/phq9';
  static const String tests = '/tests';
  static const String epdsResult = '/epds-result';
  static const String screeningHistory = '/screening-history';
  static const String riskInsights = '/risk-insights';
  static const String notifications = '/notifications';
  static const String privacy = '/privacy';
  static const String settings = '/settings';
  static const String helpSupport = '/help-support';
  static const String profile = '/profile';
  static const String guardianLink = '/guardian-link';
  static const String guardianDashboard = '/guardian-dashboard';
  static const String guardianTrends = '/guardian-wellbeing-trends';
  static const String reports = '/reports';
  static const String mood = '/mood';
  static const String journal = '/journal';
  static const String chatbot = '/chatbot';
  static const String crisis = '/crisis';
  static const String secureChat = '/secure-chat';
  static const String therapy = '/therapy';
  static const String digitalWellbeing = '/digital-wellbeing';
  static const String community = '/community';
  static const String content = '/content';
  static const String contentManage = '/content-manage';
  static const String breathing = '/therapy/breathing';
  static const String meditation = '/therapy/meditation';
  static const String cbtExercise = '/therapy/cbt';
  static const String therapyGame = '/therapy/game';
}

abstract final class AppRouter {
  AppRouter._();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: kDebugMode,
    routes: [
      GoRoute(
        path: AppRoutes.tests,
        redirect: (context, _) {
          final user = context.read<AuthProvider>().user;
          if (user == null) return AppRoutes.splash;
          if (!user.isMother) return AppRoutes.home;
          return user.onboardingComplete ? null : AppRoutes.onboarding;
        },
        builder: (context, _) =>
            TestsScreen(key: ValueKey(context.watch<AuthProvider>().user?.id)),
      ),
      GoRoute(
          path: AppRoutes.community,
          builder: (context, _) => CommunityScreen(
              key: ValueKey(context.watch<AuthProvider>().user?.id))),
      GoRoute(
          path: AppRoutes.content,
          redirect: (context, _) {
            final auth = context.read<AuthProvider>();
            final user = auth.user;
            if (!auth.isAuthenticated || user == null) return AppRoutes.splash;
            if (!user.onboardingComplete) return AppRoutes.onboarding;
            if (!user.isMother && !user.isGuardian) return AppRoutes.home;
            return null;
          },
          builder: (context, state) => ContentScreen(
              key: ValueKey(context.watch<AuthProvider>().user?.id),
              initialItemId: state.uri.queryParameters['id'],
              initialCategory: state.uri.queryParameters['category'],
              initialSaved: state.uri.queryParameters['saved'] == 'true')),
      GoRoute(
          path: AppRoutes.contentManage,
          redirect: (context, _) {
            final auth = context.read<AuthProvider>();
            if (!auth.isAuthenticated || auth.user == null) {
              return AppRoutes.splash;
            }
            return auth.user?.role == 'admin' ? null : AppRoutes.home;
          },
          builder: (context, _) => ContentAdminScreen(
              key: ValueKey(context.watch<AuthProvider>().user?.id))),
      GoRoute(
          path: AppRoutes.digitalWellbeing,
          redirect: (context, _) {
            final user = context.read<AuthProvider>().user;
            if (user == null) return AppRoutes.splash;
            if (!user.isMother) return AppRoutes.home;
            return user.onboardingComplete ? null : AppRoutes.onboarding;
          },
          builder: (context, _) => DigitalWellbeingScreen(
              key: ValueKey(context.watch<AuthProvider>().user?.id),
              accountId: context.watch<AuthProvider>().user?.id)),
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
          child: EpdsScreen(assessmentId: state.uri.queryParameters['draft']),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.phq9,
        name: 'phq9',
        pageBuilder: (_, state) => CustomTransitionPage(
          key: state.pageKey,
          child: EpdsScreen(
              instrumentType: 'phq9',
              assessmentId: state.uri.queryParameters['draft']),
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
        redirect: (context, _) {
          final auth = context.read<AuthProvider>();
          final user = auth.user;
          if (!auth.isAuthenticated || user == null) return AppRoutes.splash;
          if (!user.isMother) return AppRoutes.home;
          return user.onboardingComplete ? null : AppRoutes.onboarding;
        },
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: RiskInsightsScreen(
            key: ValueKey(context.watch<AuthProvider>().user?.id),
          ),
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
          child: const HelpSupportScreen(),
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
        path: AppRoutes.guardianTrends,
        redirect: (context, _) {
          final user = context.read<AuthProvider>().user;
          if (user == null) return AppRoutes.splash;
          return user.isGuardian ? null : AppRoutes.home;
        },
        builder: (context, _) => GuardianTrendsScreen(
          key: ValueKey(context.watch<AuthProvider>().user?.id),
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
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: JournalAccountGuard(
              accountId: context.read<AuthProvider>().user?.id,
              child: MoodJournalScreen(
                  key: ValueKey(context.read<AuthProvider>().user?.id),
                  accountId: context.read<AuthProvider>().user?.id,
                  initialMood: state.extra as int?)),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.journal,
        name: 'journal',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: JournalAccountGuard(
              accountId: context.read<AuthProvider>().user?.id,
              child: MoodJournalScreen(
                  key: ValueKey(context.read<AuthProvider>().user?.id),
                  accountId: context.read<AuthProvider>().user?.id,
                  initialTab: 1)),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.crisis,
        name: 'crisis',
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: CrisisSupportScreen(
            key: ValueKey(context.watch<AuthProvider>().user?.id),
            accountId: context.watch<AuthProvider>().user?.isMother == true
                ? context.watch<AuthProvider>().user!.id
                : null,
            isGuardian: context.watch<AuthProvider>().user?.isGuardian == true,
          ),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.chatbot,
        name: 'chatbot',
        redirect: (context, _) {
          final user = context.read<AuthProvider>().user;
          if (user == null) return AppRoutes.splash;
          if (!user.isMother) return AppRoutes.home;
          return user.onboardingComplete ? null : AppRoutes.onboarding;
        },
        builder: (context, _) => HumRaazScreen(
          key: ValueKey(context.watch<AuthProvider>().user?.id),
        ),
      ),
      GoRoute(
        path: AppRoutes.secureChat,
        name: 'secure-chat',
        redirect: (context, _) {
          final auth = context.read<AuthProvider>();
          final user = auth.user;
          if (!auth.isAuthenticated || user == null) return AppRoutes.splash;
          if (!user.isMother && !user.isGuardian) return AppRoutes.home;
          return user.onboardingComplete ? null : AppRoutes.onboarding;
        },
        pageBuilder: (context, state) => CustomTransitionPage(
          key: state.pageKey,
          child: SecureChatScreen(
              key: ValueKey(context.watch<AuthProvider>().user?.id)),
          transitionsBuilder: _fadeSlideTransition,
        ),
      ),
      GoRoute(
        path: AppRoutes.therapy,
        name: 'therapy',
        redirect: _therapyRedirect,
        pageBuilder: (context, state) =>
            _therapyPage(context, state, const TherapyHubScreen()),
      ),
      GoRoute(
        path: AppRoutes.breathing,
        name: 'breathing',
        redirect: _therapyRedirect,
        pageBuilder: (context, state) => _therapyPage(
          context,
          state,
          BreathingExerciseScreen(
            patternId: state.uri.queryParameters['id'] ?? 'box_breathing',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.meditation,
        name: 'meditation',
        redirect: _therapyRedirect,
        pageBuilder: (context, state) => _therapyPage(
          context,
          state,
          MeditationScreen(
            activityId: state.uri.queryParameters['id'] ?? 'mindfulness',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.cbtExercise,
        name: 'cbt-exercise',
        redirect: _therapyRedirect,
        pageBuilder: (context, state) => _therapyPage(
          context,
          state,
          CbtExerciseScreen(
            activityId: state.uri.queryParameters['id'] ?? 'thought_challenge',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.therapyGame,
        name: 'therapy-game',
        redirect: _therapyRedirect,
        pageBuilder: (context, state) => _therapyPage(
          context,
          state,
          TherapyGameScreen(
            gameId: state.uri.queryParameters['id'] ?? 'memory_match',
          ),
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

  static String? _therapyRedirect(BuildContext context, GoRouterState state) {
    final auth = context.read<AuthProvider>();
    final user = auth.user;
    if (!auth.isAuthenticated || user == null) return AppRoutes.splash;
    if (!user.isMother) return AppRoutes.guardianHome;
    return user.onboardingComplete ? null : AppRoutes.onboarding;
  }

  static CustomTransitionPage<void> _therapyPage(
      BuildContext context, GoRouterState state, Widget child) {
    final owner = context.read<AuthProvider>().user?.id;
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: TherapyAccountGuard(accountId: owner, child: child),
      transitionsBuilder: _fadeSlideTransition,
    );
  }

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
    if (user?.isGuardian == true) {
      return GuardianHomeScreen(key: ValueKey(user!.id));
    }
    if (user?.role == 'admin') {
      return AdminWorkspaceScreen(key: ValueKey(user!.id));
    }
    if (user?.isMother == true) return HomeScreen(key: ValueKey(user!.id));

    // Splash restores the server session before normal navigation. This
    // fallback avoids exposing either role interface during a direct deep link.
    return const SplashScreen();
  }
}
