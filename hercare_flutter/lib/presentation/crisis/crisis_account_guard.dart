import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import 'crisis_help_screen.dart';

/// Nested private routes cannot retain an old account's view during logout.
class CrisisAccountGuard extends StatelessWidget {
  const CrisisAccountGuard(
      {super.key, required this.accountId, required this.child});
  final String accountId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider?>();
    if (auth != null &&
        (auth.user?.id != accountId || auth.user?.isMother != true)) {
      return const CrisisSupportScreen();
    }
    return child;
  }
}
