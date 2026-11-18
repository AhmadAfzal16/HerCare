import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';

/// Disposes active timers, audio and private worksheets on account changes.
class TherapyAccountGuard extends StatelessWidget {
  const TherapyAccountGuard(
      {super.key, required this.accountId, required this.child});
  final String? accountId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider?>();
    if (accountId != null &&
        auth != null &&
        (!auth.isAuthenticated ||
            auth.user?.id != accountId ||
            auth.user?.isMother != true)) {
      final ur = context.watch<LanguageProvider>().isUrdu;
      return Scaffold(
          appBar: AppBar(title: Text(ur ? 'آرام کی مشقیں' : 'Calm activities')),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(ur
                      ? 'اکاؤنٹ بدل گیا ہے۔ مشق دوبارہ کھولیں۔'
                      : 'Your account changed. Reopen activities for your own account.'))));
    }
    return child;
  }
}
