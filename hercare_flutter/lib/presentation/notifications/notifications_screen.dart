import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    // Dummy notifications for now until backend push notifications are integrated
    final List<Map<String, dynamic>> notifications = [
      {
        'title': isUrdu ? 'نئی اپ ڈیٹ!' : 'New Update!',
        'body': isUrdu
            ? 'آپ کا اگلا ای پی ڈی ایس سکریننگ سیشن شیڈول ہے۔'
            : 'Your next EPDS screening session is scheduled.',
        'time': '10:00 AM',
        'isRead': false,
        'icon': Icons.calendar_today_rounded,
      },
      {
        'title': isUrdu ? 'یاد دہانی' : 'Reminder',
        'body': isUrdu
            ? 'اپنی روزمرہ کی صحت کی تفصیلات شامل کرنا نہ بھولیں۔'
            : 'Do not forget to add your daily health details.',
        'time': 'Yesterday',
        'isRead': true,
        'icon': Icons.favorite_border_rounded,
      },
    ];

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isUrdu ? 'نوٹیفیکیشنز' : 'Notifications',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.hcTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: notifications.isEmpty
          ? Center(
              child: Text(
                isUrdu
                    ? 'کوئی نوٹیفیکیشن موجود نہیں'
                    : 'No notifications available',
                style: AppTextStyles.bodyLarge,
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(24),
              physics: const BouncingScrollPhysics(),
              itemCount: notifications.length,
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return _NotificationTile(
                  title: notification['title'],
                  body: notification['body'],
                  time: notification['time'],
                  isRead: notification['isRead'],
                  icon: notification['icon'],
                );
              },
            ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final String title;
  final String body;
  final String time;
  final bool isRead;
  final IconData icon;

  const _NotificationTile({
    required this.title,
    required this.body,
    required this.time,
    required this.isRead,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRead ? AppColors.surface : AppColors.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: isRead
            ? Border.all(color: AppColors.outline)
            : Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isRead ? AppColors.surfaceVariant : AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isRead ? AppColors.textSecondary : Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: AppTextStyles.titleSmall.copyWith(
                          fontWeight: isRead ? FontWeight.w600 : FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      time,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: context.hcTextSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: context.hcTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
