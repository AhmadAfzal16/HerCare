import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/data/models/voice_transcript.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/mood_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'M5 production provider wiring clears state safely during auth changes',
      (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final auth = _Auth();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProxyProvider<AuthProvider, MoodProvider>(
            create: (_) => MoodProvider(),
            update: (_, actor, mood) => mood!..bindAccount(actor.user?.id),
          ),
        ],
        child: MaterialApp(home: Consumer<MoodProvider>(builder: (_, mood, __) {
          final count = mood.journals.length;
          return Text('Entries: $count');
        }))));
    await tester.pumpAndSettle();
    auth.change('mother-b');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    auth.change(null);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  test(
      'M5 transcript revision parsing rejects fractional, absent and nonfinite data',
      () {
    final json = {'journal_id': 'synthetic', 'status': 'queued', 'revision': 1};
    expect(VoiceTranscript.fromJson({...json, 'revision': '1'}).revision, 1);
    for (final value in [null, 0, 1.5, double.nan, double.infinity, 'bad']) {
      expect(() => VoiceTranscript.fromJson({...json, 'revision': value}),
          throwsFormatException);
    }
  });
}

class _Auth extends AuthProvider {
  String? id = 'mother-a';
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
