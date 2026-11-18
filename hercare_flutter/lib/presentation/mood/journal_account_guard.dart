import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';

class JournalAccountGuard extends StatelessWidget {
  const JournalAccountGuard(
      {super.key, required this.accountId, required this.child});
  final String? accountId;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider?>();
    if (accountId != null &&
        auth != null &&
        (auth.user?.id != accountId || auth.user?.isMother != true)) {
      final ur = context.watch<LanguageProvider>().isUrdu;
      return Scaffold(
          appBar: AppBar(title: Text(ur ? 'نجی جریدہ' : 'Private journal')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(ur
                      ? 'اکاؤنٹ بدل گیا ہے۔ اپنا جریدہ دوبارہ کھولیں۔'
                      : 'Your account changed. Reopen your own journal.'))));
    }
    return child;
  }
}
