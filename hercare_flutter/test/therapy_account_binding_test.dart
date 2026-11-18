import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/data/models/user_model.dart';
import 'package:hercare/presentation/therapy/therapy_account_guard.dart';
import 'package:hercare/providers/auth_provider.dart';
import 'package:hercare/providers/language_provider.dart';
import 'package:hercare/providers/therapy_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthProvider {
  String? id = 'mother-a';
  String role = 'mother';
  @override
  bool get isAuthenticated => id != null;
  @override
  UserModel? get user => id == null
      ? null
      : UserModel(
          id: id!,
          phone: 'test-only',
          role: role,
          language: 'en',
          onboardingComplete: true,
          createdAt: DateTime.utc(2026));
  void change(String? value, {String role = 'mother'}) {
    id = value;
    this.role = role;
    notifyListeners();
  }
}

class _PrivateActivity extends StatefulWidget {
  const _PrivateActivity(this.onDispose);
  final VoidCallback onDispose;
  @override
  State<_PrivateActivity> createState() => _PrivateActivityState();
}

class _PrivateActivityState extends State<_PrivateActivity> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Text('Private worksheet');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({'app_language': 'en'});
  });

  testWidgets(
      'production M9 proxy safely binds and clears on switch/logout/guardian',
      (tester) async {
    final auth = _Auth();
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProxyProvider<AuthProvider, TherapyProvider>(
            create: (_) => TherapyProvider(),
            update: (_, actor, therapy) => therapy!
              ..bindAccount(
                  actor.isAuthenticated && actor.user?.isMother == true
                      ? actor.user?.id
                      : null),
          ),
        ],
        child: MaterialApp(
            home: Consumer<TherapyProvider>(
                builder: (_, therapy, __) => Text(
                    '${therapy.accountId ?? 'signed-out'}:${therapy.history.length}')))));
    await tester.pumpAndSettle();
    expect(find.text('mother-a:0'), findsOneWidget);
    auth.change('mother-b');
    await tester.pumpAndSettle();
    expect(find.text('mother-b:0'), findsOneWidget);
    auth.change('guardian', role: 'guardian');
    await tester.pumpAndSettle();
    expect(find.text('signed-out:0'), findsOneWidget);
    auth.change(null);
    await tester.pumpAndSettle();
    expect(find.text('signed-out:0'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'account guard disposes private activity instead of leaving its timer/audio alive',
      (tester) async {
    final auth = _Auth();
    var disposals = 0;
    await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthProvider>.value(value: auth),
          ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ],
        child: MaterialApp(
            home: TherapyAccountGuard(
                accountId: 'mother-a',
                child: _PrivateActivity(() => disposals++)))));
    await tester.pumpAndSettle();
    expect(find.text('Private worksheet'), findsOneWidget);
    auth.change('mother-b');
    await tester.pumpAndSettle();
    expect(find.text('Private worksheet'), findsNothing);
    expect(disposals, 1);
    expect(find.textContaining('Your account changed'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
