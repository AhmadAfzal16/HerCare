import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';

/// A route/dialog belongs to the account that opened it, never the next login.
/// Replacing the subtree disposes its drafts and ignores outstanding replies.
class CommunityAccountScope extends StatefulWidget {
  const CommunityAccountScope(
      {super.key, required this.builder, this.accountId});
  final Widget Function(BuildContext context, String? accountId) builder;
  final String? accountId;

  static bool current(BuildContext context, String? accountId) {
    final auth = context.read<AuthProvider?>();
    if (auth == null) return accountId == null;
    return auth.isAuthenticated &&
        auth.user?.id == accountId &&
        (auth.user?.isMother == true || auth.user?.role == 'admin') &&
        auth.user?.onboardingComplete == true;
  }

  @override
  State<CommunityAccountScope> createState() => _CommunityAccountScopeState();
}

class _CommunityAccountScopeState extends State<CommunityAccountScope> {
  String? _accountId;
  bool _captured = false;
  bool _invalidated = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider?>();
    if (!_captured) {
      _captured = true;
      _accountId = widget.accountId ?? auth?.user?.id;
    }
    if (auth != null && !CommunityAccountScope.current(context, _accountId)) {
      _invalidated = true;
    }
    if (_invalidated) {
      final ur = context.watch<LanguageProvider?>()?.isUrdu == true;
      return Material(
          color: Theme.of(context).colorScheme.surface,
          child: SafeArea(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.lock_outline),
                    const SizedBox(height: 16),
                    Text(ur
                        ? 'اکاؤنٹ بدل گیا ہے یا رسائی دستیاب نہیں۔ حلقہ دوبارہ کھولیں۔'
                        : 'Your account changed or access is unavailable. Reopen the community.'),
                    TextButton(
                        onPressed: () => Navigator.maybePop(context),
                        child: Text(ur ? 'واپس' : 'Back')),
                  ]))));
    }
    return widget.builder(context, _accountId);
  }
}
