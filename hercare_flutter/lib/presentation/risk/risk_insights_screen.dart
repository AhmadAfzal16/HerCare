import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/risk_models.dart';
import '../../providers/language_provider.dart';
import '../../providers/risk_provider.dart';

class RiskInsightsScreen extends StatefulWidget {
  const RiskInsightsScreen({super.key});

  @override
  State<RiskInsightsScreen> createState() => _RiskInsightsScreenState();
}

class _RiskInsightsScreenState extends State<RiskInsightsScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<RiskProvider>().initialize(),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<RiskProvider>().refreshPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<RiskProvider>();
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        title: Text(isUrdu ? 'خطرے کی بصیرت' : 'Risk insights'),
      ),
      body: SafeArea(
        child: provider.loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: provider.initialize,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    _PrivacyCard(provider: provider, isUrdu: isUrdu),
                    const SizedBox(height: 14),
                    if (provider.status?.consentTier3 == true &&
                        provider.permissions.isAndroid) ...[
                      _PermissionCard(
                        icon: Icons.notifications_active_outlined,
                        title:
                            isUrdu ? 'پیغام کے اشارے' : 'Message-signal access',
                        description: isUrdu
                            ? 'صرف 100 حروف تک کے پیغام کا آلہ پر تجزیہ ہوتا ہے۔ اصل متن کبھی محفوظ یا اپ لوڈ نہیں ہوتا۔'
                            : 'Up to 100 preview characters are analysed on-device. Raw notification text is never stored or uploaded.',
                        enabled: provider.permissions.notificationAccess,
                        onPressed: provider.openNotificationSettings,
                        isUrdu: isUrdu,
                      ),
                      const SizedBox(height: 12),
                      _PermissionCard(
                        icon: Icons.phone_android_rounded,
                        title: isUrdu
                            ? 'ڈیجیٹل استعمال کی رسائی'
                            : 'Device-usage access',
                        description: isUrdu
                            ? 'صرف مجموعی اسکرین ٹائم، رات کا استعمال اور ایپ تبدیلیوں کی تعداد شیئر ہوتی ہے۔'
                            : 'Only aggregate screen time, late-night use and app-switch counts are shared.',
                        enabled: provider.permissions.usageAccess,
                        onPressed: provider.openUsageSettings,
                        isUrdu: isUrdu,
                      ),
                      const SizedBox(height: 14),
                    ],
                    if (!provider.permissions.isAndroid &&
                        provider.status?.consentTier3 == true)
                      _InfoBanner(
                        text: isUrdu
                            ? 'غیر فعال نگرانی صرف اینڈرائیڈ پر دستیاب ہے۔ اسکریننگ اور موڈ سے خطرے کی بصیرت پھر بھی حاصل کی جا سکتی ہے۔'
                            : 'Passive monitoring is Android-only. Screening and mood data can still produce an insight.',
                      ),
                    if (provider.error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorCard(message: provider.error!),
                    ],
                    const SizedBox(height: 16),
                    _PredictionCard(
                      prediction: provider.latest,
                      isUrdu: isUrdu,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: provider.working
                          ? null
                          : () => provider.syncAndPredict(),
                      icon: provider.working
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_graph_rounded),
                      label: Text(
                        isUrdu ? 'بصیرت تازہ کریں' : 'Refresh risk insight',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isUrdu
                          ? 'HerCare تشخیص نہیں کرتا۔ خطرے کی بصیرت اسکریننگ اور پیشہ ورانہ طبی جائزے کا متبادل نہیں ہے۔'
                          : 'HerCare does not diagnose. Risk insights never replace screening or assessment by a qualified professional.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodySmall.copyWith(
                        color: context.hcTextSecondary,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({required this.provider, required this.isUrdu});
  final RiskProvider provider;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: _decoration(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.privacy_tip_outlined,
                    color: AppColors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isUrdu ? 'نجی نگرانی' : 'Privacy-controlled monitoring',
                    style: AppTextStyles.titleSmall,
                  ),
                ),
                Switch(
                  value: provider.status?.consentTier3 ?? false,
                  onChanged: provider.working ? null : provider.setConsent,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isUrdu
                  ? 'آپ اسے کسی بھی وقت بند کر سکتی ہیں۔ بند کرنے سے آلہ پر پیغامات کا تجزیہ فوراً رک جاتا ہے۔'
                  : 'You can turn this off at any time. Disabling it immediately stops on-device message analysis.',
              style: AppTextStyles.bodySmall,
            ),
          ],
        ),
      );
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.enabled,
    required this.onPressed,
    required this.isUrdu,
  });
  final IconData icon;
  final String title;
  final String description;
  final bool enabled;
  final VoidCallback onPressed;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: _decoration(context),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: enabled ? AppColors.success : AppColors.warning),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTextStyles.titleSmall),
                  const SizedBox(height: 5),
                  Text(description, style: AppTextStyles.bodySmall),
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: onPressed,
                    child: Text(enabled
                        ? (isUrdu ? 'ترتیبات دیکھیں' : 'Review settings')
                        : (isUrdu ? 'رسائی فعال کریں' : 'Enable access')),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              enabled ? Icons.check_circle_rounded : Icons.info_outline_rounded,
              color: enabled ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
      );
}

class _PredictionCard extends StatelessWidget {
  const _PredictionCard({required this.prediction, required this.isUrdu});
  final RiskPrediction? prediction;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    final value = prediction;
    if (value == null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: _decoration(context),
        child: Column(
          children: [
            const Icon(Icons.insights_rounded,
                size: 42, color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              isUrdu
                  ? 'ابھی تک خطرے کی بصیرت موجود نہیں۔'
                  : 'No risk insight has been generated yet.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge,
            ),
          ],
        ),
      );
    }
    final color = _riskColor(value.riskLevel);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _decoration(context).copyWith(
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                _riskLabel(value.riskLevel, isUrdu),
                style: AppTextStyles.headlineSmall.copyWith(color: color),
              ),
              Chip(
                label: Text(value.isClinicalForecast
                    ? (isUrdu ? '14 دن کی پیش گوئی' : '14-day forecast')
                    : (isUrdu ? 'تحقیقی بنیادی ماڈل' : 'Research baseline')),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _MetricRow(
            label: isUrdu ? 'ماڈل کا امکان' : 'Model probability',
            value: '${(value.depressionProbability * 100).round()}%',
          ),
          _MetricRow(
            label: isUrdu ? 'اعتماد' : 'Confidence',
            value: '${(value.confidence * 100).round()}%',
          ),
          _MetricRow(
            label: isUrdu ? 'ڈیٹا مکمل' : 'Data completeness',
            value: '${(value.dataCompleteness * 100).round()}%',
          ),
          if (!value.isClinicalForecast) ...[
            const SizedBox(height: 10),
            _InfoBanner(
              text: isUrdu
                  ? 'PERI_DEP ڈیٹا مستقبل کے 14 دن کا نتیجہ فراہم نہیں کرتا، اس لیے یہ بنیادی تعلق ہے، طبی پیش گوئی نہیں۔'
                  : 'PERI_DEP does not contain a future 14-day outcome, so this is a baseline association—not a clinical forecast.',
            ),
          ],
          if (value.contributors.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(isUrdu ? 'اہم اشارے' : 'Leading signals',
                style: AppTextStyles.titleSmall),
            const SizedBox(height: 8),
            ...value.contributors.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 7, color: AppColors.primary),
                    const SizedBox(width: 9),
                    Expanded(child: Text(_factorLabel(item.factor, isUrdu))),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.bodyMedium)),
            const SizedBox(width: 12),
            Text(value,
                style: AppTextStyles.labelLarge
                    .copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: AppColors.primaryContainer.withValues(alpha: .6),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(text, style: AppTextStyles.bodySmall),
      );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Text(message,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
      );
}

BoxDecoration _decoration(BuildContext context) => BoxDecoration(
      color: context.hcSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.hcOutline),
    );

Color _riskColor(String risk) => switch (risk) {
      'moderate' => AppColors.warning,
      'high' => Colors.deepOrange,
      'severe' => AppColors.error,
      _ => AppColors.success,
    };

String _riskLabel(String risk, bool isUrdu) => switch (risk) {
      'moderate' => isUrdu ? 'درمیانی خطرہ' : 'Moderate indicators',
      'high' => isUrdu ? 'زیادہ خطرہ' : 'High indicators',
      'severe' => isUrdu ? 'شدید خطرہ' : 'Severe indicators',
      _ => isUrdu ? 'کم خطرہ' : 'Low indicators',
    };

String _factorLabel(String factor, bool isUrdu) => switch (factor) {
      'recent_screening' => isUrdu ? 'حالیہ اسکریننگ' : 'Recent screening',
      'low_mood' => isUrdu ? 'حالیہ کم موڈ' : 'Recent low mood',
      'distress_signals' =>
        isUrdu ? 'پریشانی کے مجموعی اشارے' : 'Aggregate distress signals',
      'late_night_use' =>
        isUrdu ? 'رات گئے آلہ استعمال' : 'Late-night device use',
      'limited_support' => isUrdu ? 'محدود مدد' : 'Limited support',
      _ => isUrdu ? 'دیگر اشارہ' : 'Other signal',
    };
