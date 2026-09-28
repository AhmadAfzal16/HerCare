import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import '../../providers/therapy_provider.dart';

class TherapyHubScreen extends StatefulWidget {
  const TherapyHubScreen({super.key});
  @override
  State<TherapyHubScreen> createState() => _TherapyHubScreenState();
}

class _TherapyHubScreenState extends State<TherapyHubScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<TherapyProvider>().load());
  }

  void _open(TherapyActivity activity) {
    final encoded = Uri.encodeComponent(activity.id);
    switch (activity.type) {
      case 'breathing':
        context.push('${AppRoutes.breathing}?id=$encoded');
        return;
      case 'meditation':
        context.push('${AppRoutes.meditation}?id=$encoded');
        return;
      case 'cbt':
        context.push('${AppRoutes.cbtExercise}?id=$encoded');
        return;
      case 'game':
        context.push('${AppRoutes.therapyGame}?id=$encoded');
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<TherapyProvider>();
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        surfaceTintColor: Colors.transparent,
        title: Text(isUrdu ? 'سکون اور مشقیں' : 'Calm & Activities',
            style: AppTextStyles.titleMedium),
      ),
      body: RefreshIndicator(
        onRefresh: provider.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
          children: [
            _Hero(isUrdu: isUrdu),
            const SizedBox(height: 18),
            if (provider.recommendation != null)
              _RecommendationCard(
                value: provider.recommendation!,
                isUrdu: isUrdu,
                onTap: () => _open(
                    TherapyCatalog.byId(provider.recommendation!.activityId)),
              )
            else if (provider.isLoading)
              const Center(child: CircularProgressIndicator())
            else
              _OfflineRecommendation(
                isUrdu: isUrdu,
                onTap: () => _open(TherapyCatalog.byId('box_breathing')),
              ),
            if (provider.error != null) ...[
              const SizedBox(height: 10),
              Text(provider.error!,
                  textAlign: TextAlign.center,
                  style:
                      AppTextStyles.bodySmall.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: 22),
            if (provider.summary != null) ...[
              _Progress(summary: provider.summary!, isUrdu: isUrdu),
              const SizedBox(height: 22),
            ],
            _Section(
              title: isUrdu ? 'سانس کی مشقیں' : 'Guided breathing',
              icon: Icons.air_rounded,
              color: AppColors.accent,
              values: TherapyCatalog.activities
                  .where((value) => value.type == 'breathing')
                  .toList(),
              isUrdu: isUrdu,
              onTap: _open,
            ),
            _Section(
              title: isUrdu ? 'مراقبہ اور آرام' : 'Meditation & relaxation',
              icon: Icons.self_improvement_rounded,
              color: AppColors.primary,
              values: TherapyCatalog.activities
                  .where((value) => value.type == 'meditation')
                  .toList(),
              isUrdu: isUrdu,
              onTap: _open,
            ),
            _Section(
              title: isUrdu ? 'سی بی ٹی ٹولز' : 'CBT tools',
              icon: Icons.psychology_alt_outlined,
              color: AppColors.secondary,
              values: TherapyCatalog.activities
                  .where((value) => value.type == 'cbt')
                  .toList(),
              isUrdu: isUrdu,
              onTap: _open,
            ),
            _Section(
              title: isUrdu ? 'ہلکے کھیل' : 'Light mini-games',
              icon: Icons.extension_outlined,
              color: AppColors.success,
              values: TherapyCatalog.activities
                  .where((value) => value.type == 'game')
                  .toList(),
              isUrdu: isUrdu,
              onTap: _open,
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.hcSurfaceVariant,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                isUrdu
                    ? 'یہ سرگرمیاں خود مدد کے لیے ہیں، طبی علاج یا تشخیص کا متبادل نہیں۔'
                    : 'These activities support self-care and do not replace professional assessment or treatment.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.isUrdu});
  final bool isUrdu;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppColors.primaryGradient,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .16),
                borderRadius: BorderRadius.circular(16)),
            child: const Icon(Icons.spa_rounded, color: Colors.white, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                    isUrdu
                        ? 'ایک نرم لمحہ اپنے لیے'
                        : 'A gentle moment for you',
                    style:
                        AppTextStyles.titleLarge.copyWith(color: Colors.white)),
                const SizedBox(height: 5),
                Text(
                    isUrdu
                        ? 'مختصر، آف لائن اور آسان سرگرمیاں'
                        : 'Short, offline, and lightweight activities',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: Colors.white.withValues(alpha: .85))),
              ])),
        ]),
      );
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard(
      {required this.value, required this.isUrdu, required this.onTap});
  final TherapyRecommendation value;
  final bool isUrdu;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final activity = TherapyCatalog.byId(value.activityId);
    return Material(
      color: value.safetyPriority
          ? AppColors.errorContainer
          : AppColors.primaryContainer,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap:
            value.safetyPriority ? () => context.push(AppRoutes.crisis) : onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(
                value.safetyPriority
                    ? Icons.health_and_safety_outlined
                    : Icons.auto_awesome_rounded,
                color:
                    value.safetyPriority ? AppColors.error : AppColors.primary),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(isUrdu ? 'آپ کے لیے تجویز' : 'Suggested for you',
                      style: AppTextStyles.labelSmall),
                  const SizedBox(height: 3),
                  Text(isUrdu ? activity.titleUr : activity.title,
                      style: AppTextStyles.titleMedium),
                  const SizedBox(height: 4),
                  Text(isUrdu ? value.reasonUr : value.reason,
                      style: AppTextStyles.bodySmall),
                ])),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ]),
        ),
      ),
    );
  }
}

class _OfflineRecommendation extends StatelessWidget {
  const _OfflineRecommendation({required this.isUrdu, required this.onTap});
  final bool isUrdu;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.offline_bolt_outlined),
        label: Text(isUrdu
            ? 'آف لائن باکس بریتھنگ شروع کریں'
            : 'Start offline box breathing'),
      );
}

class _Progress extends StatelessWidget {
  const _Progress({required this.summary, required this.isUrdu});
  final TherapySummary summary;
  final bool isUrdu;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: _Stat(
                value: '${summary.completedSessions}',
                label: isUrdu ? 'سیشن' : 'Sessions')),
        const SizedBox(width: 10),
        Expanded(
            child: _Stat(
                value: '${(summary.totalSeconds / 60).round()}',
                label: isUrdu ? 'منٹ' : 'Minutes')),
        const SizedBox(width: 10),
        Expanded(
            child: _Stat(
                value: summary.averageMoodChange == null
                    ? '—'
                    : '${summary.averageMoodChange! >= 0 ? '+' : ''}${summary.averageMoodChange}',
                label: isUrdu ? 'موڈ فرق' : 'Mood change')),
      ]);
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 13),
        decoration: BoxDecoration(
            color: context.hcSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: context.hcOutline)),
        child: Column(children: [
          Text(value,
              style:
                  AppTextStyles.titleMedium.copyWith(color: AppColors.primary)),
          const SizedBox(height: 2),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall)
        ]),
      );
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title,
      required this.icon,
      required this.color,
      required this.values,
      required this.isUrdu,
      required this.onTap});
  final String title;
  final IconData icon;
  final Color color;
  final List<TherapyActivity> values;
  final bool isUrdu;
  final ValueChanged<TherapyActivity> onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: AppTextStyles.titleMedium))
          ]),
          const SizedBox(height: 10),
          ...values.map((activity) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: context.hcSurface,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                    side: BorderSide(color: context.hcOutline)),
                child: ListTile(
                  onTap: () => onTap(activity),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: Text(isUrdu ? activity.titleUr : activity.title,
                      style: AppTextStyles.titleSmall),
                  subtitle: Text(
                      isUrdu ? activity.descriptionUr : activity.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall),
                  trailing: Text('${activity.minutes}m',
                      style: AppTextStyles.labelSmall.copyWith(color: color)),
                ),
              )),
        ]),
      );
}
