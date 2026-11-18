import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/presentation/onboarding/onboarding_wizard.dart';
import 'package:hercare/presentation/shared/app_language_bar.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('two essential answers reach consent; language switch keeps form',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await tester.binding.setSurfaceSize(const Size(320, 560));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: const MaterialApp(home: AppLanguageBar(child: OnboardingWizard())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('More about you (optional)'), findsOneWidget);
    expect(find.text('Education (optional)'), findsNothing);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField).at(0), '27');
    await tester.enterText(find.byType(TextFormField).at(1), '3');
    await tester.tap(find.text('اردو'));
    await tester.pumpAndSettle();
    expect(find.text('عمر (سال)'), findsOneWidget);
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        '27');
    await tester.tap(find.text('اگلا'));
    await tester.pumpAndSettle();
    expect(find.text('رازداری اور رضامندی'), findsOneWidget);
    await tester.tap(find.byType(OutlinedButton));
    await tester.pumpAndSettle();
    final inputs =
        tester.widgetList<EditableText>(find.byType(EditableText)).toList();
    expect(inputs.map((input) => input.controller.text), ['27', '3']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('optional details remain accessible without blocking consent',
      (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => LanguageProvider(),
      child: const MaterialApp(home: AppLanguageBar(child: OnboardingWizard())),
    ));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '27');
    await tester.enterText(find.byType(TextFormField).at(1), '3');
    await tester.tap(find.text('Add health and family details (optional)'));
    await tester.pumpAndSettle();
    expect(find.text('Your Birth Journey'), findsOneWidget);
    await tester.tap(find.text('Skip remaining optional questions'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy & Consent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
