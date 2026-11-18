import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';

/// Administrative work stays separate from the mother/guardian care interface.
class AdminWorkspaceScreen extends StatelessWidget {
  const AdminWorkspaceScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final ur = context.watch<LanguageProvider>().isUrdu;
    if (!auth.isAuthenticated || auth.user?.role != 'admin') {
      return Scaffold(
          body: Center(
              child: Text(ur ? 'رسائی دستیاب نہیں' : 'Access unavailable')));
    }
    return Scaffold(
        appBar: AppBar(
            title: Text(ur ? 'HerCare انتظام' : 'HerCare administration'),
            actions: [
              IconButton(
                  tooltip: ur ? 'لاگ آؤٹ' : 'Log out',
                  icon: const Icon(Icons.logout),
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (context.mounted) context.go(AppRoutes.login);
                  }),
            ]),
        body: ListView(padding: const EdgeInsets.all(20), children: [
          Text(ur
              ? 'مواد اور حلقے کا جائزہ۔ مریضوں کا نجی روزنامچہ یا چیٹ یہاں شامل نہیں۔'
              : 'Review content and community submissions. Private journals and chats are not part of this workspace.'),
          const SizedBox(height: 20),
          Card(
              child: ListTile(
                  leading: const Icon(Icons.diversity_1_outlined),
                  title: Text(ur
                      ? 'ساتھیوں کے حلقے کی نگرانی'
                      : 'Community moderation'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.community))),
          Card(
              child: ListTile(
                  leading: const Icon(Icons.library_books_outlined),
                  title: Text(ur
                      ? 'تجویز کردہ مواد کا انتظام'
                      : 'Recommendation catalog'),
                  subtitle: Text(ur
                      ? 'ماخذ، ترجمہ اور اشاعت کا جائزہ'
                      : 'Sources, translations, review and publication'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.contentManage))),
        ]));
  }
}
