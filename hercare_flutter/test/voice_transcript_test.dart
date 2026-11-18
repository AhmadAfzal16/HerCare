import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/data/models/voice_transcript.dart';
import 'package:hercare/data/models/mood_models.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/mood_provider.dart';
import 'package:hercare/services/mood_service.dart';
import 'package:hercare/presentation/mood/voice_transcript_screen.dart';

VoiceTranscript transcript(String status) => VoiceTranscript.fromJson({
      'journal_id': 'test-journal',
      'status': status,
      'revision': 1,
      'draft': status == 'review' ? 'I feel calm and supported.' : null,
      'safety_hint': status == 'review',
      'model_version': 'test-only',
      'failure_code': null
    });
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
    FlutterSecureStorage.setMockInitialValues({});
  });
  for (final language in ['en', 'ur']) {
    for (final status in [
      'none',
      'review',
      'failed',
      'no_speech',
      'confirmed'
    ]) {
      testWidgets(
          'M5 transcript $status $language fits 320x480 at 200% with keyboard',
          (tester) async {
        final service = _Voice()
          ..value = status == 'none' ? null : transcript(status);
        await _pump(tester, service: service, language: language);
        expect(tester.takeException(), isNull);
        if (status == 'none' || status == 'failed' || status == 'no_speech') {
          await _reveal(tester, find.byKey(const ValueKey('voice-request')));
        }
        if (status == 'review') {
          await _reveal(tester, find.byKey(const ValueKey('voice-confirm')));
        }
        final list = find.byType(ListView);
        for (var i = 0; i < 22; i++) {
          await tester.drag(list, const Offset(0, -160));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
  testWidgets(
      'M5 failed confirmation retry retains corrections and request identity',
      (tester) async {
    final service = _Voice()
      ..value = transcript('review')
      ..failFirst = true;
    await _pump(tester, service: service);
    await _reveal(tester, find.byKey(const ValueKey('voice-draft')));
    await tester.enterText(find.byKey(const ValueKey('voice-draft')),
        'These are my corrected words.');
    tester.testTextInput.hide();
    await _reveal(tester, find.byKey(const ValueKey('voice-confirm')));
    await tester.tap(find.byKey(const ValueKey('voice-confirm')));
    await tester.pumpAndSettle();
    expect(service.contents.single, 'These are my corrected words.');
    await _reveal(tester, find.byKey(const ValueKey('voice-confirm')));
    await tester.tap(find.byKey(const ValueKey('voice-confirm')));
    await tester.pumpAndSettle();
    expect(service.ids.length, 2);
    expect(service.ids.toSet().length, 1);
    expect(find.textContaining('Confirmed and analyzed'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-draft')), findsNothing);
  });
  testWidgets(
      'M5 typed private draft disappears immediately on server access denial',
      (tester) async {
    final service = _Voice()..value = transcript('review');
    await _pump(tester, service: service);
    service.denied = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(
        find.textContaining('Private access is unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-draft')), findsNothing);
  });
  testWidgets('M5 late prior-account draft is not rendered', (tester) async {
    final auth = _Auth('mother-a');
    final pending = Completer<VoiceTranscript?>();
    final service = _Voice()..pending = pending.future;
    await _pump(tester, service: service, auth: auth, settle: false);
    auth.change('mother-b');
    await tester.pump();
    pending.complete(transcript('review'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(find.byKey(const ValueKey('voice-draft')), findsNothing);
  });
  test(
      'M5 account change clears provider memory and discards late journal responses',
      () async {
    final pending = Completer<List<JournalEntry>>();
    final provider = MoodProvider(service: _LateMood(pending.future));
    provider.bindAccount('mother-a');
    final work = provider.searchJournals('');
    provider.bindAccount('mother-b');
    pending.complete([
      JournalEntry(
          id: 'old',
          entryType: 'text',
          language: 'en',
          processingStatus: 'complete',
          content: 'PRIVATE_OTHER_ACCOUNT',
          containsDanger: false,
          createdAt: DateTime.now())
    ]);
    await work;
    expect(provider.journals, isEmpty);
    expect(provider.isLoading, isFalse);
    provider.dispose();
  });
}

Future<void> _pump(WidgetTester tester,
    {required _Voice service,
    String language = 'en',
    _Auth? auth,
    bool settle = true}) async {
  SharedPreferences.setMockInitialValues({'app_language': language});
  await tester.binding.setSurfaceSize(const Size(320, 480));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider<AuthProvider>.value(
            value: auth ?? _Auth('mother-a'))
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                  textScaler: const TextScaler.linear(2),
                  viewInsets: const EdgeInsets.only(bottom: 160)),
              child: Directionality(
                  textDirection:
                      language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
                  child: child!)),
          home: VoiceTranscriptScreen(
              journalId: 'test-journal',
              accountId: 'mother-a',
              service: service))));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 150 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView).last, const Offset(0, -100));
    await tester.pumpAndSettle();
  }
  expect(finder.hitTestable(), findsWidgets);
}

class _Voice extends MoodService {
  VoiceTranscript? value;
  bool failFirst = false, denied = false;
  Future<VoiceTranscript?>? pending;
  final ids = <String>[], contents = <String>[];
  @override
  Future<VoiceTranscript?> getTranscript(String id) async {
    if (denied) throw MoodAccessException();
    return pending == null ? value : await pending!;
  }

  @override
  Future<bool> confirmTranscript(
      String id, String content, int revision, String requestId) async {
    ids.add(requestId);
    contents.add(content);
    if (failFirst && ids.length == 1) throw Exception('offline');
    value = transcript('confirmed');
    return false;
  }
}

class _Auth extends AuthProvider {
  _Auth(this.id);
  String? id;
  @override
  UserModel? get user => id == null
      ? null
      : UserModel(
          id: id!,
          phone: 'test-only',
          role: 'mother',
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime.utc(2026));
  void change(String? value) {
    id = value;
    notifyListeners();
  }
}

class _LateMood extends MoodService {
  _LateMood(this.pending);
  final Future<List<JournalEntry>> pending;
  @override
  Future<List<JournalEntry>> getJournals({int limit = 30}) => pending;
}
