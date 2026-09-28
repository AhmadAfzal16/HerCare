import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/presentation/wellbeing/digital_wellbeing_screen.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/digital_wellbeing_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final language in ['en', 'ur']) {
    for (final granted in [false, true]) {
      testWidgets(
          'sleep and usage $language access=$granted at large text on small screen',
          (tester) async {
        SharedPreferences.setMockInitialValues({'app_language': language});
        await tester.binding.setSurfaceSize(const Size(320, 480));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ChangeNotifierProvider(
            create: (_) => LanguageProvider(),
            child: MaterialApp(
                builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(1.5)),
                    child: Directionality(
                        textDirection: language == 'ur'
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: child!)),
                home: DigitalWellbeingScreen(service: _Fake(granted)))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final log = find.text(language == 'ur' ? 'نیند درج یا درست کریں' : 'Log / correct sleep');
        for (var i = 0; i < 30 && log.hitTestable().evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView).first, const Offset(0, -180));
          await tester.pumpAndSettle();
        }
        await tester.tap(log);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final save = find.text(language == 'ur' ? 'نیند محفوظ کریں' : 'Save sleep');
        for (var i = 0; i < 30 && save.hitTestable().evaluate().isEmpty; i++) {
          await tester.drag(find.byType(ListView).last, const Offset(0, -150));
          await tester.pumpAndSettle();
        }
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _Fake extends DigitalWellbeingService {
  _Fake(this.granted);
  final bool granted;
  @override
  Future<Map<String, dynamic>> usage() async => {
        'supported': true,
        'permission': granted,
        'available': true,
        'screen_minutes': 330,
        'social_minutes': 300,
        'late_night_minutes': 40,
        'apps': [
          {
            'name':
                'A very long application name that must wrap without overflow',
            'minutes': 330
          }
        ],
      };
  @override
  Future<Map<String, dynamic>> sleep() async => {
        'summary': {'average_minutes': 420},
        'records': [
          {
            'sleep_date': '2026-09-25',
            'sleep_minutes': '420',
            'bedtime': '2026-09-24T18:00:00Z',
            'wake_time': '2026-09-25T01:30:00Z',
            'quality': 3,
            'awakenings': 2
          }
        ],
      };
}
