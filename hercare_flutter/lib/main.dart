import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/language_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/guardian_provider.dart';
import 'providers/mood_provider.dart';
import 'providers/screening_provider.dart';
import 'providers/risk_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/therapy_provider.dart';
import 'providers/content_provider.dart';
import 'services/push_notification_service.dart';
import 'presentation/auth/session_connection_banner.dart';
import 'presentation/shared/app_language_bar.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  try {
    await dotenv.load(fileName: '.env');
  } catch (e) {
    // .env missing — safe to continue in release (uses AppConstants defaults)
    // ignore: avoid_print
    print('[HerCare] WARNING: .env not loaded: $e');
  }

  await PushNotificationService.instance.initialize();

  // Lock to portrait mode
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Status bar style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProxyProvider<AuthProvider, GuardianProvider>(
          create: (_) => GuardianProvider(),
          update: (_, auth, guardian) => guardian!
            ..bindAccount(auth.isAuthenticated &&
                    (auth.user?.isMother == true ||
                        auth.user?.isGuardian == true)
                ? auth.user?.id
                : null),
        ),
        ChangeNotifierProxyProvider<AuthProvider, MoodProvider>(
          create: (_) => MoodProvider(),
          update: (_, auth, mood) => mood!
            ..bindAccount(auth.isAuthenticated && auth.user?.isMother == true
                ? auth.user?.id
                : null),
        ),
        ChangeNotifierProxyProvider<AuthProvider, ScreeningProvider>(
          create: (_) => ScreeningProvider(),
          update: (_, auth, screening) => screening!
            ..bindAccount(auth.isAuthenticated && auth.user?.isMother == true
                ? auth.user?.id
                : null),
        ),
        ChangeNotifierProxyProvider<AuthProvider, RiskProvider>(
          create: (_) => RiskProvider(),
          update: (_, auth, risk) => risk!
            ..bindAccount(auth.isAuthenticated &&
                    auth.user?.isMother == true &&
                    auth.user?.onboardingComplete == true
                ? auth.user?.id
                : null),
        ),
        ChangeNotifierProxyProvider<AuthProvider, ChatProvider>(
          create: (_) => ChatProvider(),
          update: (_, auth, chat) => chat!
            ..bindAccount(
                auth.isAuthenticated &&
                        auth.user?.onboardingComplete == true &&
                        (auth.user?.isMother == true ||
                            auth.user?.isGuardian == true)
                    ? auth.user?.id
                    : null,
                role: auth.user?.role),
        ),
        ChangeNotifierProxyProvider<AuthProvider, TherapyProvider>(
          create: (_) => TherapyProvider(),
          update: (_, auth, therapy) => therapy!
            ..bindAccount(auth.isAuthenticated && auth.user?.isMother == true
                ? auth.user?.id
                : null),
        ),
        ChangeNotifierProxyProvider4<AuthProvider, MoodProvider,
            TherapyProvider, ScreeningProvider, ContentProvider>(
          create: (_) => ContentProvider(),
          update: (_, auth, mood, therapy, screening, content) => content!
            ..bindAccount(
                auth.isAuthenticated &&
                        auth.user?.onboardingComplete == true &&
                        (auth.user?.isMother == true ||
                            auth.user?.isGuardian == true)
                    ? auth.user?.id
                    : null,
                role: auth.user?.role ?? '')
            // Opaque change marker only; the server reads its own authorized
            // records. No scores, journals or chat are sent with a feed request.
            ..observeCareRevision([
              mood.today?.id,
              mood.today?.moodRating,
              mood.today?.sleepQuality,
              mood.today?.isSynced,
              therapy.history.firstOrNull?.id,
              therapy.history.firstOrNull?.isSynced,
              screening.latest?.id,
              screening.latest?.status,
              screening.latest?.updatedAt.toIso8601String(),
            ].join('|')),
        ),
        ChangeNotifierProvider.value(value: PushNotificationService.instance),
      ],
      child: const HerCareApp(),
    ),
  );
}

class HerCareApp extends StatelessWidget {
  const HerCareApp({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final themeProvider = context.watch<ThemeProvider>();

    return MaterialApp.router(
      scaffoldMessengerKey: PushNotificationService.messengerKey,
      title: 'HerCare',
      debugShowCheckedModeBanner: false,

      // Theming
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeProvider.themeMode,

      // Routing
      routerConfig: AppRouter.router,
      builder: (context, child) => AppLanguageBar(
        child: SessionConnectionBanner(child: child ?? const SizedBox.shrink()),
      ),

      // Localization
      locale: languageProvider.locale,
      supportedLocales: LanguageProvider.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
