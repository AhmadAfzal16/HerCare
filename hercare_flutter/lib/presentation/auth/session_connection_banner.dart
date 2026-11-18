import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../core/routing/app_router.dart';

/// Cached identity is clearly distinguished from live server verification.
class SessionConnectionBanner extends StatefulWidget {
  const SessionConnectionBanner({super.key, required this.child});
  final Widget child;
  @override
  State<SessionConnectionBanner> createState() =>
      _SessionConnectionBannerState();
}

class _SessionConnectionBannerState extends State<SessionConnectionBanner> {
  bool _retrying = false;
  Future<void> _retry() async {
    setState(() => _retrying = true);
    final auth = context.read<AuthProvider>();
    try {
      await auth.refreshCurrentUser();
      if (mounted && auth.status == AuthStatus.unauthenticated) {
        AppRouter.router.go(AppRoutes.login);
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ur = context.watch<LanguageProvider>().isUrdu;
    return Column(children: [
      if (auth.isOfflineSession)
        Material(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: SafeArea(
                bottom: false,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: Text(
                            ur
                                ? 'محفوظ سیشن استعمال ہو رہا ہے۔ آن لائن خصوصیات کے لیے دوبارہ جڑیں۔'
                                : 'Using saved sign-in. Reconnect for live features.',
                            style: Theme.of(context).textTheme.bodySmall)),
                    TextButton(
                        onPressed: _retrying ? null : _retry,
                        child: Text(ur ? 'دوبارہ کوشش' : 'Retry'))
                  ]),
                ))),
      Expanded(child: widget.child),
    ]);
  }
}
