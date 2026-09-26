import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/onboarding_model.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/presentation/auth/login_screen.dart';
import 'package:hercare/presentation/auth/register_screen.dart';
import 'package:hercare/presentation/guardian/guardian_link_screen.dart';
import 'package:hercare/presentation/guardian/report_screen.dart';
import 'package:hercare/presentation/onboarding/steps/personal_info_step.dart';
import 'package:hercare/presentation/onboarding/steps/obstetric_info_step.dart';
import 'package:hercare/presentation/onboarding/steps/family_support_step.dart';
import 'package:hercare/presentation/onboarding/steps/consent_step.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/guardian_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/mood_provider.dart';
import 'package:hercare/presentation/mood/mood_journal_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final language in ['en', 'ur']) {
    for (final name in [
      'login',
      'register',
      'invite',
      'reports',
      'mood',
      'journal',
      'personal',
      'obstetric',
      'family',
      'consent'
    ]) {
      testWidgets('$name: $language, compact screen, large text',
          (tester) async {
        SharedPreferences.setMockInitialValues({'app_language': language});
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final data = OnboardingData();
        final key = GlobalKey<FormState>();
        final urdu = language == 'ur';
        final Widget screen = switch (name) {
          'login' => const LoginScreen(),
          'mood' => const MoodJournalScreen(),
          'journal' => const MoodJournalScreen(initialTab: 1),
          'register' => const RegisterScreen(),
          'invite' => const GuardianLinkScreen(),
          'reports' => const ReportScreen(),
          'personal' => Scaffold(
              body: PersonalInfoStep(formKey: key, data: data, isUrdu: urdu)),
          'obstetric' => Scaffold(
              body: ObstetricInfoStep(formKey: key, data: data, isUrdu: urdu)),
          'family' => Scaffold(
              body: FamilySupportStep(formKey: key, data: data, isUrdu: urdu)),
          _ => Scaffold(
              body: ConsentStep(
                  formKey: key, data: data, isUrdu: urdu, onChanged: () {})),
        };
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => LanguageProvider()),
            ChangeNotifierProvider<MoodProvider>(create: (_) => _Mood()),
            ChangeNotifierProvider<AuthProvider>(create: (_) => _Auth()),
            ChangeNotifierProvider<GuardianProvider>(
                create: (_) => _Guardian()),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.5)),
              child: Directionality(
                  textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
                  child: child!),
            ),
            home: screen,
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scrollables = find.byType(Scrollable);
        if (scrollables.evaluate().isNotEmpty) {
          await tester.drag(scrollables.first, const Offset(0, -1200));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}

class _Auth extends AuthProvider {
  @override
  UserModel get user => UserModel(
      id: 'test',
      phone: '',
      role: 'mother',
      language: 'en',
      onboardingComplete: true,
      createdAt: DateTime(2026));
}

class _Mood extends MoodProvider {
  @override
  Future<void> load({bool includeJournals = false}) async {}
}

class _Guardian extends GuardianProvider {
  @override
  String get inviteCode => 'ABCDEFGH2345';
  @override
  Future<void> loadLink() async {}
  @override
  Future<void> loadOrGenerateInvite() async {}
  @override
  Future<void> loadReports({String type = 'weekly'}) async {}
}
