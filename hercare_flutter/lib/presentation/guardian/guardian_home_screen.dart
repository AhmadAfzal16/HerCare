import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/language_provider.dart';

class GuardianHomeScreen extends StatefulWidget {
  const GuardianHomeScreen({super.key});

  @override
  State<GuardianHomeScreen> createState() => _GuardianHomeScreenState();
}

class _GuardianHomeScreenState extends State<GuardianHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    final provider = context.read<GuardianProvider>();
    await provider.loadLink();
    if (!mounted || !provider.hasActiveLink) return;
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    await Future.wait([
      provider.loadDashboard(lang: isUrdu ? 'ur' : 'en'),
      provider.loadAlerts(),
      provider.loadReports(type: 'weekly'),
    ]);
  }

  Future<void> _logout() async {
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    context.read<GuardianProvider>().reset();
    context.go(AppRoutes.login);
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<GuardianProvider>();
    final dashboard = provider.dashboard;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: context.hcSurface,
        surfaceTintColor: Colors.transparent,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUrdu ? 'HerCare سرپرست' : 'HerCare Guardian',
              style: AppTextStyles.titleMedium,
            ),
            Text(
              isUrdu ? 'محفوظ معاونت کا مرکز' : 'Private support workspace',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: isUrdu ? 'پروفائل' : 'Profile',
            onPressed: () => context.push(AppRoutes.profile),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
            tooltip: isUrdu ? 'لاگ آؤٹ' : 'Log out',
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
          children: [
            _ConnectionHero(
              isUrdu: isUrdu,
              isLinked: provider.hasActiveLink,
              isLoading: provider.isLoading,
              onConnect: () => context.push(AppRoutes.guardianLink),
            ),
            if (provider.error != null) ...[
              const SizedBox(height: 14),
              _ErrorBanner(
                message: provider.error!,
                onRetry: _refresh,
                isUrdu: isUrdu,
              ),
            ],
            const SizedBox(height: 20),
            if (provider.hasActiveLink) ...[
              _HealthSnapshot(
                dashboard: dashboard,
                isUrdu: isUrdu,
                onOpen: () => context.push(AppRoutes.guardianDashboard),
              ),
              const SizedBox(height: 18),
              _QuickActions(
                isUrdu: isUrdu,
                unreadAlerts: provider.unreadAlertCount,
                onDashboard: () => context.push(AppRoutes.guardianDashboard),
                onReports: () => context.push(AppRoutes.reports),
                onChat: () => context.push(AppRoutes.secureChat),
              ),
              const SizedBox(height: 22),
              _Recommendations(
                isUrdu: isUrdu,
                values: (dashboard?['recommendations'] as List<dynamic>?)
                        ?.map((value) => value.toString())
                        .toList() ??
                    const [],
              ),
              if (provider.alerts.isNotEmpty) ...[
                const SizedBox(height: 22),
                _RecentAlerts(
                  isUrdu: isUrdu,
                  alerts: provider.alerts.take(3).toList(),
                  onAcknowledge: () => provider.markAlertsRead(),
                ),
              ],
            ] else ...[
              _GettingStarted(
                isUrdu: isUrdu,
                onConnect: () => context.push(AppRoutes.guardianLink),
              ),
            ],
            const SizedBox(height: 22),
            _PrivacyNotice(isUrdu: isUrdu),
          ],
        ),
      ),
    );
  }
}

class _ConnectionHero extends StatelessWidget {
  const _ConnectionHero({
    required this.isUrdu,
    required this.isLinked,
    required this.isLoading,
    required this.onConnect,
  });

  final bool isUrdu;
  final bool isLinked;
  final bool isLoading;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: isLinked
            ? const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF06B6D4)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: (isLinked ? AppColors.accent : AppColors.primary)
                .withOpacity(0.22),
            blurRadius: 22,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  isLinked ? Icons.verified_user_rounded : Icons.link_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.16),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isLinked
                      ? (isUrdu ? 'محفوظ ربط' : 'Securely linked')
                      : (isUrdu ? 'ربط درکار ہے' : 'Connection required'),
                  style: AppTextStyles.labelSmall.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            isLinked
                ? (isUrdu
                    ? 'آپ معاونت کے لیے تیار ہیں'
                    : 'You are ready to support')
                : (isUrdu
                    ? 'ماں کے اکاؤنٹ سے جڑیں'
                    : 'Connect to a mother account'),
            style: AppTextStyles.headlineSmall.copyWith(color: Colors.white),
          ),
          const SizedBox(height: 8),
          Text(
            isLinked
                ? (isUrdu
                    ? 'تازہ مجموعی معلومات، الرٹس اور مدد کی تجاویز دیکھیں۔'
                    : 'Review aggregate trends, alerts, and practical support guidance.')
                : (isUrdu
                    ? 'ماں کی طرف سے بھیجا گیا 12 حروف کا دعوتی کوڈ درج کریں۔'
                    : 'Enter the private 12-character invitation code shared by the mother.'),
            style: AppTextStyles.bodySmall.copyWith(
              color: Colors.white.withOpacity(0.86),
            ),
          ),
          if (!isLinked) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: isLoading ? null : onConnect,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
              ),
              icon: const Icon(Icons.vpn_key_rounded),
              label:
                  Text(isUrdu ? 'دعوتی کوڈ درج کریں' : 'Enter invitation code'),
            ),
          ],
        ],
      ),
    );
  }
}

class _HealthSnapshot extends StatelessWidget {
  const _HealthSnapshot({
    required this.dashboard,
    required this.isUrdu,
    required this.onOpen,
  });

  final Map<String, dynamic>? dashboard;
  final bool isUrdu;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final risk = dashboard?['risk_level'] as String?;
    final epds = dashboard?['epds_score'];
    final mood = dashboard?['avg_mood'];
    final riskColor = switch (risk) {
      'severe' || 'high' => AppColors.error,
      'moderate' => AppColors.warning,
      'low' => AppColors.success,
      _ => Colors.grey,
    };
    final riskText = switch (risk) {
      'severe' => isUrdu ? 'شدید' : 'Severe',
      'high' => isUrdu ? 'زیادہ' : 'High',
      'moderate' => isUrdu ? 'معتدل' : 'Moderate',
      'low' => isUrdu ? 'کم' : 'Low',
      _ => isUrdu ? 'ڈیٹا دستیاب نہیں' : 'Waiting for health data',
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hcOutline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isUrdu ? 'مجموعی صحت کا خلاصہ' : 'Aggregate health snapshot',
                  style: AppTextStyles.titleSmall,
                ),
              ),
              TextButton(
                  onPressed: onOpen, child: Text(isUrdu ? 'تفصیل' : 'Details')),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Metric(
                label: isUrdu ? 'خطرہ' : 'Risk',
                value: riskText,
                color: riskColor,
              ),
              const SizedBox(width: 10),
              _Metric(
                label: 'EPDS',
                value: epds == null ? '--' : '$epds/30',
                color: AppColors.primary,
              ),
              const SizedBox(width: 10),
              _Metric(
                label: isUrdu ? 'اوسط موڈ' : 'Avg mood',
                value: mood?.toString() ?? '--',
                color: AppColors.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              textAlign: TextAlign.center,
              style: AppTextStyles.labelLarge.copyWith(color: color),
            ),
            const SizedBox(height: 3),
            Text(label,
                textAlign: TextAlign.center, style: AppTextStyles.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.isUrdu,
    required this.unreadAlerts,
    required this.onDashboard,
    required this.onReports,
    required this.onChat,
  });

  final bool isUrdu;
  final int unreadAlerts;
  final VoidCallback onDashboard;
  final VoidCallback onReports;
  final VoidCallback onChat;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _ActionTile(
          icon: Icons.monitor_heart_outlined,
          label: isUrdu ? 'جائزہ' : 'Overview',
          color: AppColors.primary,
          onTap: onDashboard,
        ),
        const SizedBox(width: 10),
        _ActionTile(
          icon: Icons.assessment_outlined,
          label: isUrdu ? 'رپورٹس' : 'Reports',
          color: AppColors.secondary,
          onTap: onReports,
        ),
        const SizedBox(width: 10),
        _ActionTile(
          icon: Icons.forum_outlined,
          label: isUrdu ? 'چیٹ' : 'Chat',
          color: AppColors.success,
          badge: unreadAlerts,
          onTap: onChat,
        ),
      ],
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.hcOutline),
            ),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: color, size: 25),
                    if (badge > 0)
                      Positioned(
                        right: -9,
                        top: -8,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: AppColors.error,
                            shape: BoxShape.circle,
                          ),
                          child: Text(
                            badge > 9 ? '9+' : '$badge',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 8),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(label, style: AppTextStyles.labelSmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Recommendations extends StatelessWidget {
  const _Recommendations({required this.isUrdu, required this.values});

  final bool isUrdu;
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isUrdu ? 'آپ کیسے مدد کر سکتے ہیں' : 'How you can help',
            style: AppTextStyles.titleSmall),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryContainer.withOpacity(0.45),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: values
                .map(
                  (value) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 18, color: AppColors.success),
                        const SizedBox(width: 9),
                        Expanded(
                            child: Text(value, style: AppTextStyles.bodySmall)),
                      ],
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _RecentAlerts extends StatelessWidget {
  const _RecentAlerts({
    required this.isUrdu,
    required this.alerts,
    required this.onAcknowledge,
  });

  final bool isUrdu;
  final List<dynamic> alerts;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(isUrdu ? 'حالیہ الرٹس' : 'Recent alerts',
                  style: AppTextStyles.titleSmall),
            ),
            TextButton(
              onPressed: onAcknowledge,
              child: Text(isUrdu ? 'پڑھا ہوا' : 'Mark read'),
            ),
          ],
        ),
        ...alerts.map((raw) {
          final alert = raw as Map<String, dynamic>;
          final unread = alert['is_read'] == false;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: unread
                  ? AppColors.warningContainer.withOpacity(0.55)
                  : context.hcSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: context.hcOutline),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: unread ? AppColors.warning : context.hcTextHint,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alert['message']?.toString() ?? '',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.bodySmall,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _GettingStarted extends StatelessWidget {
  const _GettingStarted({required this.isUrdu, required this.onConnect});

  final bool isUrdu;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.hcOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isUrdu ? 'شروع کرنے کے مراحل' : 'Getting started',
              style: AppTextStyles.titleSmall),
          const SizedBox(height: 14),
          _Step(
              number: '1',
              text: isUrdu
                  ? 'ماں سے دعوتی کوڈ لیں'
                  : 'Ask the mother for an invitation code'),
          _Step(
              number: '2',
              text: isUrdu
                  ? 'اپنا رشتہ منتخب کریں'
                  : 'Enter the code and your relationship'),
          _Step(
              number: '3',
              text: isUrdu
                  ? 'محفوظ خلاصے دیکھیں'
                  : 'Review privacy-safe summaries'),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onConnect,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(isUrdu ? 'ابھی جوڑیں' : 'Connect now'),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primaryContainer,
            child: Text(number,
                style: AppTextStyles.labelSmall
                    .copyWith(color: AppColors.primary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppTextStyles.bodySmall)),
        ],
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice({required this.isUrdu});

  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.successContainer.withOpacity(0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.privacy_tip_outlined, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isUrdu
                  ? 'آپ صرف مجموعی طبی پیمائش دیکھ سکتے ہیں۔ ذاتی ڈائری، چیٹ اور خام جذباتی اندراجات نجی رہتے ہیں۔'
                  : 'You can view aggregate clinical measurements only. Journals, chats, and raw emotional entries always remain private.',
              style: AppTextStyles.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.onRetry,
    required this.isUrdu,
  });

  final String message;
  final VoidCallback onRetry;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: AppTextStyles.bodySmall)),
          TextButton(
              onPressed: onRetry, child: Text(isUrdu ? 'دوبارہ' : 'Retry')),
        ],
      ),
    );
  }
}
