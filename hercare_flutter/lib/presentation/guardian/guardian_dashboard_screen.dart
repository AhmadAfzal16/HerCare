import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/language_provider.dart';

/// Guardian dashboard — what the linked guardian/spouse sees about the mother.
class GuardianDashboardScreen extends StatefulWidget {
  const GuardianDashboardScreen({super.key});

  @override
  State<GuardianDashboardScreen> createState() =>
      _GuardianDashboardScreenState();
}

class _GuardianDashboardScreenState extends State<GuardianDashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final isUrdu = context.read<LanguageProvider>().isUrdu;
      context
          .read<GuardianProvider>()
          .loadDashboard(lang: isUrdu ? 'ur' : 'en');
      context.read<GuardianProvider>().loadAlerts();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<GuardianProvider>();
    final dashboard = provider.dashboard;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.hcTextPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isUrdu ? 'سرپرست ڈیش بورڈ' : 'Guardian Dashboard',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
        actions: [
          if (provider.unreadAlertCount > 0)
            Stack(
              children: [
                IconButton(
                  icon: Icon(Icons.notifications_rounded,
                      color: context.hcTextPrimary),
                  onPressed: () =>
                      context.read<GuardianProvider>().markAlertsRead(),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    width: 16,
                    height: 16,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${provider.unreadAlertCount}',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: provider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : provider.error != null
              ? _buildError(context, isUrdu, provider)
              : dashboard == null
                  ? _buildNotLinked(context, isUrdu)
                  : RefreshIndicator(
                      onRefresh: () => context
                          .read<GuardianProvider>()
                          .loadDashboard(lang: isUrdu ? 'ur' : 'en'),
                      child: ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          // Risk banner
                          _RiskBanner(
                            riskLevel:
                                dashboard['risk_level'] as String? ?? 'unknown',
                            epdsScore: dashboard['epds_score'] as int?,
                            isUrdu: isUrdu,
                          ),
                          const SizedBox(height: 20),

                          // Mood trend chart
                          _MoodTrendCard(
                            moodTrend:
                                (dashboard['mood_trend'] as List<dynamic>?)
                                        ?.map((e) => (e as num).toDouble())
                                        .toList() ??
                                    [],
                            isUrdu: isUrdu,
                          ),
                          const SizedBox(height: 20),

                          // How to help
                          _HowToHelpCard(
                            recommendations:
                                (dashboard['recommendations'] as List<dynamic>?)
                                        ?.map((e) => e.toString())
                                        .toList() ??
                                    [],
                            isUrdu: isUrdu,
                          ),
                          const SizedBox(height: 20),

                          // Recent alerts
                          if ((provider.alerts).isNotEmpty) ...[
                            Text(
                              isUrdu ? 'حالیہ الرٹس' : 'Recent Alerts',
                              style: AppTextStyles.titleSmall,
                            ),
                            const SizedBox(height: 10),
                            ...provider.alerts.take(3).map((a) => _AlertTile(
                                  alert: a as Map<String, dynamic>,
                                  isUrdu: isUrdu,
                                )),
                          ],

                          const SizedBox(height: 12),
                          // Last updated
                          if (dashboard['last_updated'] != null)
                            Center(
                              child: Text(
                                '${isUrdu ? "آخری اپ ڈیٹ" : "Last updated"}: '
                                '${_formatDate(dashboard['last_updated'] as String)}',
                                style: AppTextStyles.bodySmall.copyWith(
                                  fontSize: 10,
                                  color: context.hcTextHint,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
    );
  }

  Widget _buildNotLinked(BuildContext context, bool isUrdu) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off_rounded, size: 64, color: context.hcTextHint),
            const SizedBox(height: 16),
            Text(
              isUrdu
                  ? 'آپ کسی اکاؤنٹ سے نہیں جڑے'
                  : 'Not linked to any account',
              style: AppTextStyles.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isUrdu
                  ? 'گارڈین لنک اسکرین میں کوڈ درج کریں'
                  : 'Enter an invite code in Guardian Link screen',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(
      BuildContext context, bool isUrdu, GuardianProvider provider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, size: 48, color: AppColors.error),
          const SizedBox(height: 12),
          Text(provider.error ?? 'Something went wrong',
              style: AppTextStyles.bodyMedium),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => context
                .read<GuardianProvider>()
                .loadDashboard(lang: isUrdu ? 'ur' : 'en'),
            child: Text(isUrdu ? 'دوبارہ کوشش کریں' : 'Retry'),
          ),
        ],
      ),
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate).toLocal();
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _RiskBanner extends StatelessWidget {
  final String riskLevel;
  final int? epdsScore;
  final bool isUrdu;
  const _RiskBanner(
      {required this.riskLevel, required this.epdsScore, required this.isUrdu});

  Color get _color {
    switch (riskLevel) {
      case 'severe':
        return AppColors.error;
      case 'high':
        return AppColors.error.withOpacity(0.8);
      case 'moderate':
        return AppColors.warning;
      case 'low':
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  String get _emoji {
    switch (riskLevel) {
      case 'severe':
        return '🚨';
      case 'high':
        return '🔴';
      case 'moderate':
        return '🟡';
      case 'low':
        return '🟢';
      default:
        return '—';
    }
  }

  String _label(bool isUrdu) {
    switch (riskLevel) {
      case 'severe':
        return isUrdu ? 'شدید خطرہ' : 'Severe Risk';
      case 'high':
        return isUrdu ? 'زیادہ خطرہ' : 'High Risk';
      case 'moderate':
        return isUrdu ? 'معتدل خطرہ' : 'Moderate Risk';
      case 'low':
        return isUrdu ? 'کم خطرہ' : 'Low Risk';
      default:
        return isUrdu ? 'ابھی کافی ڈیٹا نہیں' : 'Not enough data yet';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withOpacity(0.3), width: 1.5),
      ),
      child: Row(
        children: [
          Text(_emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _label(isUrdu),
                  style: AppTextStyles.titleMedium.copyWith(
                    color: _color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (epdsScore != null)
                  Text(
                    'EPDS: $epdsScore / 30',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: _color.withOpacity(0.8)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MoodTrendCard extends StatelessWidget {
  final List<double> moodTrend;
  final bool isUrdu;
  const _MoodTrendCard({required this.moodTrend, required this.isUrdu});

  static const _dayLabelsEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _dayLabelsUr = [
    'پیر',
    'منگل',
    'بدھ',
    'جمعرات',
    'جمعہ',
    'ہفتہ',
    'اتوار'
  ];

  @override
  Widget build(BuildContext context) {
    final maxVal =
        moodTrend.isEmpty ? 5.0 : moodTrend.reduce((a, b) => a > b ? a : b);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hcOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.insights_rounded,
                  color: AppColors.secondary, size: 20),
              const SizedBox(width: 8),
              Text(isUrdu ? 'ہفتے کا موڈ' : 'Mood This Week',
                  style: AppTextStyles.titleSmall),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(moodTrend.length, (i) {
                final isToday = i == moodTrend.length - 1;
                final barH = maxVal > 0
                    ? ((moodTrend[i] / maxVal) * 56).clamp(8.0, 56.0)
                    : 8.0;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      width: 26,
                      height: barH,
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.secondary
                            : AppColors.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isUrdu ? _dayLabelsUr[i] : _dayLabelsEn[i],
                      style: AppTextStyles.labelSmall.copyWith(fontSize: 9),
                    ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowToHelpCard extends StatelessWidget {
  final List<String> recommendations;
  final bool isUrdu;
  const _HowToHelpCard({required this.recommendations, required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.volunteer_activism_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(isUrdu ? 'آپ کیسے مدد کر سکتے ہیں؟' : 'How You Can Help',
                  style: AppTextStyles.titleSmall
                      .copyWith(color: AppColors.primary)),
            ],
          ),
          const SizedBox(height: 12),
          ...recommendations.map((tip) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('• ',
                        style:
                            TextStyle(color: AppColors.primary, fontSize: 16)),
                    Expanded(
                      child: Text(tip,
                          style:
                              AppTextStyles.bodySmall.copyWith(fontSize: 12)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  final Map<String, dynamic> alert;
  final bool isUrdu;
  const _AlertTile({required this.alert, required this.isUrdu});

  Color get _color {
    switch (alert['alert_type'] as String?) {
      case 'risk_severe':
        return AppColors.error;
      case 'risk_high':
        return AppColors.error.withOpacity(0.7);
      case 'crisis':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: _color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              alert['message'] as String? ?? '',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
