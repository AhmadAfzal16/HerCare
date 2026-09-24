import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/main.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/chat_provider.dart';
import 'package:hercare/providers/guardian_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/mood_provider.dart';
import 'package:hercare/providers/risk_provider.dart';
import 'package:hercare/providers/screening_provider.dart';
import 'package:hercare/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('HerCare app shell starts with all feature providers',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'en'});

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
          ChangeNotifierProvider(create: (_) => GuardianProvider()),
          ChangeNotifierProvider(create: (_) => MoodProvider()),
          ChangeNotifierProvider(create: (_) => ScreeningProvider()),
          ChangeNotifierProvider(create: (_) => RiskProvider()),
          ChangeNotifierProvider(create: (_) => ChatProvider()),
        ],
        child: const HerCareApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
