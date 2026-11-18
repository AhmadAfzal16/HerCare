import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/presentation/guardian/guardian_trends_screen.dart';
import 'package:hercare/providers/guardian_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/services/guardian_service.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('guardian switches among all three periods at large text size',
      (tester) async {
    SharedPreferences.setMockInitialValues(const {});
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final service = _TrendService(Future.value(_trends));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(
            create: (_) => GuardianProvider(service: service)),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const GuardianTrendsScreen(),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Score improving'), findsOneWidget);
    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(find.text('Score declining'), findsOneWidget);
    await tester.tap(find.text('14 days'));
    await tester.pumpAndSettle();
    expect(find.text('Not enough comparable records'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Insufficient data'), 120);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    expect(service.requests, 1);
  });

  test('provider discards results after a guardian account change', () async {
    final oldResponse = Completer<Map<String, dynamic>>();
    final service = _TrendService(oldResponse.future);
    final provider = GuardianProvider(service: service);
    addTearDown(provider.dispose);
    provider.bindAccount('first');
    final oldRequest = provider.loadWellbeingTrends();
    provider.bindAccount('second');
    service.response = Future.value({'as_of': '2026-11-17'});
    await provider.loadWellbeingTrends();
    oldResponse.complete(_trends);
    await oldRequest;
    expect(provider.wellbeingTrends, {'as_of': '2026-11-17'});
    provider.bindAccount(null);
    expect(provider.wellbeingTrends, isNull);
  });

  test('provider clears chart when guardian access is denied', () async {
    final service = _TrendService(Future.value(_trends));
    final provider = GuardianProvider(service: service);
    addTearDown(provider.dispose);
    await provider.loadWellbeingTrends();
    expect(provider.wellbeingTrends, isNotNull);
    service.response =
        Future.error(const GuardianAccessException('Sharing withdrawn'));
    await provider.loadWellbeingTrends();
    expect(provider.wellbeingTrends, isNull);
    expect(provider.loadingWellbeingTrends, isFalse);
  });
}

const _trends = <String, dynamic>{
  'periods': {
    'weekly': {
      'direction': 'improving',
      'bars': [_scoredBar]
    },
    'daily': {
      'direction': 'declining',
      'bars': [_scoredBar]
    },
    'fortnightly': {
      'direction': 'insufficient_data',
      'bars': [
        {'start_date': '2026-11-04', 'end_date': '2026-11-17', 'score': null},
      ],
    },
  },
};

const _scoredBar = {
  'start_date': '2026-11-17',
  'end_date': '2026-11-17',
  'score': 75.0,
  'measures': ['mood'],
};

class _TrendService extends GuardianService {
  _TrendService(this.response);

  Future<Map<String, dynamic>> response;
  int requests = 0;

  @override
  Future<Map<String, dynamic>> getWellbeingTrends() {
    requests++;
    return response;
  }
}
