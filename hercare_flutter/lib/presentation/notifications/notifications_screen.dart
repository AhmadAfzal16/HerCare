import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/language_provider.dart';
import '../../services/push_notification_service.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.read<AuthProvider>().user?.isGuardian == true) {
        context.read<GuardianProvider>().loadAlerts();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final isGuardian = context.watch<AuthProvider>().user?.isGuardian == true;
    final guardian = context.watch<GuardianProvider>();
    final push = context.watch<PushNotificationService>();
    final items = isGuardian ? guardian.alerts : push.messages;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        title: Text(isUrdu ? 'نوٹیفیکیشنز' : 'Notifications',
            style: AppTextStyles.titleMedium),
        actions: [
          if (isGuardian && items.isNotEmpty)
            TextButton(
              onPressed: () => guardian.markAlertsRead(),
              child: Text(isUrdu ? 'سب پڑھیں' : 'Read all'),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (isGuardian) await guardian.loadAlerts();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            if (!push.isConfigured)
              SliverToBoxAdapter(child: _SetupNotice(isUrdu: isUrdu)),
            if (guardian.isLoading && items.isEmpty)
              const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()))
            else if (items.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      isUrdu
                          ? 'ابھی کوئی نوٹیفیکیشن موجود نہیں'
                          : 'No notifications yet',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyLarge
                          .copyWith(color: context.hcTextSecondary),
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                sliver: SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    if (isGuardian) {
                      final alert = items[index] as Map<String, dynamic>;
                      return _NotificationTile(
                        title: _titleFor(alert['alert_type'] as String?),
                        body: alert['message'] as String? ??
                            'A wellbeing update is available.',
                        time: _relativeTime(alert['triggered_at']),
                        isRead: alert['is_read'] == true,
                        urgent: const ['crisis', 'risk_severe']
                            .contains(alert['alert_type']),
                        onTap: () => guardian
                            .markAlertsRead(alertIds: [alert['id'] as String]),
                      );
                    }
                    final message = items[index] as ReceivedPush;
                    return _NotificationTile(
                      title: message.title,
                      body: message.body,
                      time: _relativeTime(message.receivedAt),
                      isRead: false,
                      urgent: message.data['type'] == 'guardian_alert',
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _titleFor(String? type) => switch (type) {
        'crisis' => 'Urgent support needed',
        'risk_severe' => 'Severe risk update',
        'risk_high' => 'High risk update',
        'mood_drop' => 'Mood trend update',
        'epds_spike' => 'Screening update',
        _ => 'HerCare update',
      };

  String _relativeTime(dynamic value) {
    final date =
        value is DateTime ? value : DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return '';
    final difference = DateTime.now().difference(date.toLocal());
    if (difference.inMinutes < 1) return 'Now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    return '${difference.inDays}d';
  }
}

class _SetupNotice extends StatelessWidget {
  const _SetupNotice({required this.isUrdu});
  final bool isUrdu;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(
          isUrdu
              ? 'اس بلڈ میں پش نوٹیفیکیشن ابھی کنفیگر نہیں ہیں۔'
              : 'Push notifications are not configured in this build yet.',
          style:
              AppTextStyles.bodySmall.copyWith(color: context.hcTextSecondary),
        ),
      );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile(
      {required this.title,
      required this.body,
      required this.time,
      required this.isRead,
      required this.urgent,
      this.onTap});
  final String title;
  final String body;
  final String time;
  final bool isRead;
  final bool urgent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: isRead
            ? context.hcSurface
            : AppColors.primaryContainer.withValues(alpha: 0.30),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
              color: urgent
                  ? Colors.red.withValues(alpha: 0.35)
                  : context.hcOutline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                backgroundColor:
                    urgent ? Colors.red.shade50 : AppColors.primaryContainer,
                child: Icon(
                    urgent
                        ? Icons.health_and_safety_rounded
                        : Icons.notifications_rounded,
                    color: urgent ? Colors.red.shade700 : AppColors.primary),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Expanded(
                          child: Text(title, style: AppTextStyles.titleSmall)),
                      if (time.isNotEmpty)
                        Text(time,
                            style: AppTextStyles.labelSmall
                                .copyWith(color: context.hcTextSecondary)),
                    ]),
                    const SizedBox(height: 6),
                    Text(body,
                        style: AppTextStyles.bodyMedium
                            .copyWith(color: context.hcTextSecondary)),
                  ])),
            ]),
          ),
        ),
      );
}
