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
import 'therapy_sync_recovery.dart';

class TherapyHubScreen extends StatefulWidget {
  const TherapyHubScreen({super.key});
  @override
  State<TherapyHubScreen> createState() => _TherapyHubScreenState();
}

class _TherapyHubScreenState extends State<TherapyHubScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<TherapyProvider>().load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        mounted &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      context.read<TherapyProvider>().load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open(TherapyActivity activity) async {
    final provider = context.read<TherapyProvider>();
    final owner = provider.accountId;
    final encoded = Uri.encodeComponent(activity.id);
    String? route;
    switch (activity.type) {
      case 'breathing':
        route = AppRoutes.breathing;
      case 'meditation':
        route = AppRoutes.meditation;
      case 'cbt':
        route = AppRoutes.cbtExercise;
      case 'game':
        route = AppRoutes.therapyGame;
    }
    if (route != null) {
      await context.push('$route?id=$encoded');
      if (mounted && provider.accountId == owner && provider.canUseAccount) {
        await provider.load();
      }
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
            if (provider.isOffline) ...[
              Text(
                  isUrdu
                      ? 'آف لائن: تجویز اور خلاصہ پرانے ہو سکتے ہیں۔ یہ فوری خطرے کی جانچ نہیں۔'
                      : 'Offline: suggestions and summaries may be older. This is not an urgent safety check.',
                  style: AppTextStyles.bodySmall),
              TextButton.icon(
                onPressed: () => context.push(AppRoutes.crisis),
                icon: const Icon(Icons.health_and_safety_outlined),
                label: Text(isUrdu ? 'فوری مدد' : 'Immediate support'),
              ),
              const SizedBox(height: 12),
            ],
            if (provider.syncWarning != null) ...[
              Text(
                  isUrdu
                      ? 'کچھ آف لائن ریکارڈ ابھی سرور پر محفوظ نہیں ہوئے۔ باقی مشقیں جاری رکھ سکتی ہیں۔'
                      : 'Some offline records have not synced. You can still use other activities.',
                  style: AppTextStyles.bodySmall),
              if (provider.pendingIssues.isNotEmpty)
                TextButton.icon(
                  onPressed: () => showTherapySyncRecovery(context),
                  icon: const Icon(Icons.sync_problem_rounded),
                  label: Text(isUrdu
                      ? 'محفوظ ریکارڈ کا جائزہ'
                      : 'Review pending records'),
                ),
              const SizedBox(height: 12),
            ],
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
              Text(
                  isUrdu
                      ? 'گزشتہ ${provider.summary!.periodDays} دن'
                      : 'Last ${provider.summary!.periodDays} days',
                  style: AppTextStyles.titleSmall),
              const SizedBox(height: 8),
              _Progress(summary: provider.summary!, isUrdu: isUrdu),
              const SizedBox(height: 8),
              Text(
                  isUrdu
                      ? 'موڈ کا فرق صرف آپ کے اختیاری جواب کا اوسط ہے، طبی صحت یابی کا پیمانہ نہیں۔'
                      : 'Mood difference is the average of your optional ratings, not a clinical recovery measure.',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: context.hcTextSecondary)),
              const SizedBox(height: 22),
            ],
            if (provider.history.isNotEmpty) ...[
              Text(isUrdu ? 'حالیہ مشقیں' : 'Recent activities',
                  style: AppTextStyles.titleSmall),
              const SizedBox(height: 8),
              ...provider.history.take(5).map(
                  (session) => _HistoryItem(session: session, isUrdu: isUrdu)),
              const SizedBox(height: 16),
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
              imageAsset: 'assets/images/meditation_seated_posture.jpg',
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
                  Text(
                      value.safetyPriority
                          ? (isUrdu ? 'فوری مدد' : 'Immediate support')
                          : (isUrdu ? activity.titleUr : activity.title),
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
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 440 &&
            MediaQuery.textScalerOf(context).scale(14) <= 21;
        final width =
            wide ? (constraints.maxWidth - 20) / 3 : constraints.maxWidth;
        return Wrap(spacing: 10, runSpacing: 8, children: [
          SizedBox(
              width: width,
              child: _Stat(
                  value: '${summary.completedSessions}',
                  label: isUrdu ? 'سیشن' : 'Sessions')),
          SizedBox(
              width: width,
              child: _Stat(
                  value: '${(summary.totalSeconds / 60).round()}',
                  label: isUrdu ? 'منٹ' : 'Minutes')),
          SizedBox(
              width: width,
              child: _Stat(
                  value: summary.averageMoodChange == null
                      ? '—'
                      : '${summary.averageMoodChange! >= 0 ? '+' : ''}${summary.averageMoodChange!.toStringAsFixed(2)}',
                  label:
                      isUrdu ? 'اختیاری موڈ فرق' : 'Optional mood difference')),
        ]);
      });
}

class _HistoryItem extends StatelessWidget {
  const _HistoryItem({required this.session, required this.isUrdu});
  final TherapySession session;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    final activity = TherapyCatalog.byId(session.activityId);
    final seconds = session.durationSeconds;
    final minutes = seconds ~/ 60;
    final remainder = (seconds % 60).toString().padLeft(2, '0');
    final occurred = session.completedAt.toLocal();
    final date = occurred.millisecondsSinceEpoch <= 0
        ? ''
        : '${occurred.year}-${occurred.month.toString().padLeft(2, '0')}-${occurred.day.toString().padLeft(2, '0')}';
    final status = session.completed
        ? (isUrdu ? 'مکمل' : 'Completed')
        : (isUrdu ? 'پہلے روکا' : 'Stopped early');
    final sync = session.isSynced
        ? ''
        : (isUrdu ? ' • ابھی صرف فون پر محفوظ' : ' • Saved on this phone');
    final participation = switch (session.breathingParticipation) {
      'most_cues' => isUrdu ? 'زیادہ تر ہدایات' : 'Followed most cues',
      'some_cues' => isUrdu ? 'کچھ ہدایات' : 'Followed some cues',
      'stopped_early' => isUrdu ? 'جلد رک گئیں' : 'Stopped early',
      _ => null,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
          color: context.hcSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.hcOutline)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isUrdu ? activity.titleUr : activity.title,
              style: AppTextStyles.titleSmall),
          const SizedBox(height: 3),
          Text('$status • $minutes:$remainder$sync',
              style: AppTextStyles.bodySmall),
          if (date.isNotEmpty) Text(date, style: AppTextStyles.bodySmall),
          if (participation != null)
            Text(
                isUrdu
                    ? 'آپ کا جواب: $participation'
                    : 'Self-reported: $participation',
                style: AppTextStyles.bodySmall),
          if (session.moodChange != null)
            Text(
                isUrdu
                    ? 'آپ کا بتایا ہوا موڈ فرق: ${session.moodChange}'
                    : 'Your reported mood difference: ${session.moodChange}',
                style: AppTextStyles.bodySmall),
        ],
      ),
    );
  }
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
          Text(label, style: AppTextStyles.labelSmall)
        ]),
      );
}

class _Section extends StatelessWidget {
  const _Section(
      {required this.title,
      required this.icon,
      this.imageAsset,
      required this.color,
      required this.values,
      required this.isUrdu,
      required this.onTap});
  final String title;
  final IconData icon;
  final String? imageAsset;
  final Color color;
  final List<TherapyActivity> values;
  final bool isUrdu;
  final ValueChanged<TherapyActivity> onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (imageAsset == null)
              Icon(icon, color: color, size: 22)
            else
              ClipOval(
                child: Image.asset(imageAsset!,
                    width: 28, height: 28, fit: BoxFit.cover),
              ),
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
                  leading: imageAsset == null
                      ? null
                      : CircleAvatar(
                          backgroundImage: AssetImage(imageAsset!),
                        ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  title: Text(isUrdu ? activity.titleUr : activity.title,
                      style: AppTextStyles.titleSmall),
                  subtitle: Text(
                      isUrdu ? activity.descriptionUr : activity.description,
                      style: AppTextStyles.bodySmall),
                  trailing: Text('${activity.minutes}m',
                      style: AppTextStyles.labelSmall.copyWith(color: color)),
                ),
              )),
        ]),
      );
}
