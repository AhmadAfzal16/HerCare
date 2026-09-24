import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hercare/data/models/screening_models.dart';
import 'package:hercare/presentation/epds/epds_result_screen.dart';
import 'package:hercare/presentation/epds/epds_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/screening_provider.dart';
import 'package:hercare/services/screening_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(const {'app_language': 'en'});
  });

  testWidgets('screening question remains overflow-free on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
          ChangeNotifierProvider(
            create: (_) => ScreeningProvider(service: _FakeScreeningService()),
          ),
        ],
        child: const MaterialApp(home: EpdsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1/10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('screening result scrolls without overflow on a small phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => LanguageProvider(),
        child: MaterialApp(
          home: EpdsResultScreen(assessment: _assessment(status: 'completed')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Your screening result'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeScreeningService extends ScreeningService {
  @override
  Future<ScreeningInstrument> getInstrument(String type) async =>
      ScreeningInstrument(
        type: type,
        name: 'Edinburgh Postnatal Depression Scale',
        version: 'test-v1',
        scoringVersion: 'test-v1',
        timeframeDays: 7,
        maxScore: 30,
        crisisQuestion: 10,
        questions: List.generate(
          10,
          (questionIndex) => ScreeningQuestion(
            number: questionIndex + 1,
            textEn:
                'A deliberately long screening question that must wrap safely on narrow displays',
            textUr: 'ایک طویل سوال جو چھوٹی اسکرین پر محفوظ طریقے سے دکھائی دے',
            options: List.generate(
              4,
              (optionIndex) => ScreeningOption(
                index: optionIndex,
                textEn: 'A long response option that wraps without overflowing',
                textUr: 'ایک طویل جواب جو اسکرین سے باہر نہیں نکلتا',
                score: optionIndex,
              ),
            ),
          ),
        ),
      );

  @override
  Future<({Map<int, int> answers, String id})?> readLocalDraft() async => null;

  @override
  Future<ScreeningAssessment> start({
    required String instrumentType,
    required String language,
  }) async =>
      _assessment(instrumentType: instrumentType);

  @override
  Future<ScreeningAssessment?> getLatest({String type = 'epds'}) async => null;

  @override
  Future<List<ScreeningAssessment>> getHistory({
    String type = 'epds',
    int limit = 20,
  }) async =>
      const [];

  @override
  Future<ScreeningReminder> getReminder({String type = 'epds'}) async =>
      ScreeningReminder(instrumentType: type, due: true);
}

ScreeningAssessment _assessment({
  String instrumentType = 'epds',
  String status = 'draft',
}) {
  final now = DateTime.utc(2026, 9, 24);
  return ScreeningAssessment(
    id: '11111111-1111-4111-8111-111111111111',
    instrumentType: instrumentType,
    instrumentVersion: 'test-v1',
    scoringVersion: 'test-v1',
    language: 'en',
    status: status,
    totalScore: status == 'completed' ? 14 : null,
    riskLevel: status == 'completed' ? 'high' : null,
    selfHarmPositive: status == 'completed',
    startedAt: now,
    completedAt: status == 'completed' ? now : null,
    updatedAt: now,
  );
}
