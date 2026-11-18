import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/language_provider.dart';
import '../../providers/mood_provider.dart';
import '../../providers/screening_provider.dart';
import 'package:intl/intl.dart';

/// Saved wellbeing summaries and shortcuts; no fabricated measurements.
class WellbeingScreen extends StatefulWidget {
  final bool hideBackButton;

  const WellbeingScreen({super.key, this.hideBackButton = false});

  @override
  State<WellbeingScreen> createState() => _WellbeingScreenState();
}

class _WellbeingScreenState extends State<WellbeingScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh({bool force = false}) async {
    final mood = context.read<MoodProvider>();
    await Future.wait([
      context.read<ScreeningProvider>().loadOverview(force: force),
      if (!mood.isLoading) mood.load(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: !widget.hideBackButton,
        leading: widget.hideBackButton
            ? null
            : IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: context.hcTextPrimary, size: 20),
                onPressed: () => Navigator.of(context).pop(),
              ),
        title: Text(
          isUrdu ? 'آپ کی صحت' : 'Your Wellbeing',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
      ),
      body: RefreshIndicator(
          onRefresh: () => _refresh(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
            children: [
              _SectionHeader(
                title: isUrdu ? 'EPDS اسکور' : 'EPDS Score',
                subtitle: isUrdu ? 'ایڈنبرا اسکریننگ' : 'Edinburgh Screening',
              ),
              const SizedBox(height: 12),
              RepaintBoundary(child: _EpdsScoreCard(isUrdu: isUrdu)),
              const SizedBox(height: 24),
              _SectionHeader(
                title: isUrdu ? 'موڈ کی تاریخ' : 'Mood History',
                subtitle: isUrdu ? 'حالیہ اندراجات' : 'Recent check-ins',
              ),
              const SizedBox(height: 12),
              RepaintBoundary(child: _MoodHistoryCard(isUrdu: isUrdu)),
              const SizedBox(height: 24),
              _SectionHeader(
                title: isUrdu ? 'نیند کے اعداد و شمار' : 'Sleep Stats',
                subtitle:
                    isUrdu ? 'آپ کے درج کردہ اوقات' : 'Your recorded sleep',
              ),
              const SizedBox(height: 12),
              RepaintBoundary(child: _SleepStatsCard(isUrdu: isUrdu)),
              const SizedBox(height: 24),
              _SectionHeader(
                title: isUrdu ? 'سکون اور مشقیں' : 'Calm & Activities',
                subtitle: isUrdu
                    ? 'سانس، مراقبہ، سی بی ٹی اور ہلکے کھیل'
                    : 'Breathing, meditation, CBT, and light games',
              ),
              const SizedBox(height: 12),
              RepaintBoundary(child: _TherapyCard(isUrdu: isUrdu)),
              const SizedBox(height: 24),
              _SectionHeader(
                title: isUrdu ? 'ہم راز AI' : 'Hum-Raaz AI',
                subtitle: isUrdu
                    ? '24/7 ذہنی صحت کا ساتھی'
                    : '24/7 mental health companion',
              ),
              const SizedBox(height: 12),
              RepaintBoundary(child: _HumRaazCard(isUrdu: isUrdu)),
            ],
          )),
    );
  }
}

class _TherapyCard extends StatelessWidget {
  const _TherapyCard({required this.isUrdu});
  final bool isUrdu;

  @override
  Widget build(BuildContext context) => Material(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => context.push(AppRoutes.therapy),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: _cardDecoration(context),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.spa_rounded,
                    color: AppColors.primary, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isUrdu
                          ? 'مختصر آف لائن سرگرمیاں'
                          : 'Short offline activities',
                      style: AppTextStyles.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isUrdu
                          ? 'اپنے موڈ کے مطابق نرم مشق چنیں'
                          : 'Choose a gentle activity for how you feel',
                      style: AppTextStyles.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 16),
            ]),
          ),
        ),
      );
}

// Consistent card styling for the summary sections.
BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
      color: context.hcSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.hcOutline, width: 1),
    );

// --- EPDS Score Card ----------------------------------------------------------

class _EpdsScoreCard extends StatelessWidget {
  const _EpdsScoreCard({required this.isUrdu});
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    final screening = context.watch<ScreeningProvider>();
    final latest = screening.latest;
    final date = latest?.completedAt;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            latest?.totalScore == null
                ? (screening.overviewLoaded
                    ? (isUrdu
                        ? 'ابھی کوئی مکمل جانچ نہیں'
                        : 'No completed screening yet')
                    : (isUrdu
                        ? 'جانچ کا خلاصہ دستیاب نہیں'
                        : 'Screening summary unavailable'))
                : '${latest!.totalScore} / 30',
            style: AppTextStyles.titleLarge),
        if (date != null) ...[
          const SizedBox(height: 8),
          Text(DateFormat.yMMMd(isUrdu ? 'ur' : 'en').format(date.toLocal())),
        ],
        const SizedBox(height: 12),
        Text(
            isUrdu
                ? 'جانچ علامات سمجھنے میں مدد کرتی ہے، تشخیص نہیں ہے۔'
                : 'Screening helps you understand symptoms; it is not a diagnosis.',
            style: AppTextStyles.bodySmall),
        Wrap(spacing: 8, runSpacing: 4, children: [
          TextButton.icon(
              onPressed: () => context.push(AppRoutes.tests),
              icon: const Icon(Icons.assignment_outlined),
              label: Text(isUrdu ? 'میری جانچیں' : 'My tests')),
          if (latest != null)
            TextButton(
                onPressed: () => context.push(AppRoutes.screeningHistory),
                child: Text(isUrdu ? 'پچھلی جانچیں' : 'Screening history')),
          if (!screening.overviewLoaded)
            TextButton(
                onPressed: () => screening.loadOverview(force: true),
                child: Text(isUrdu ? 'دوبارہ کوشش' : 'Retry')),
        ]),
      ]),
    );
  }
}

// --- Mood History Card --------------------------------------------------------

class _MoodHistoryCard extends StatelessWidget {
  final bool isUrdu;
  const _MoodHistoryCard({required this.isUrdu});

  static const _moods = ['😔', '😟', '😐', '🙂', '😊'];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoodProvider>();
    final entries = provider.history.take(7).toList().reversed.toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                isUrdu
                    ? 'موڈ کی تاریخ بنانے کے لیے آج اندراج کریں'
                    : 'Check in today to start your mood history',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
            )
          else
            Row(
              children: List.generate(entries.length, (i) {
                final entry = entries[i];
                final now = DateTime.now();
                final isToday = DateUtils.isSameDay(entry.entryDate, now);
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppColors.secondaryContainer
                            : context.hcSurfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_moods[entry.moodRating - 1],
                          style: TextStyle(fontSize: isToday ? 20.0 : 16.0)),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      child: Text(
                          '${entry.entryDate.day}/${entry.entryDate.month}',
                          style: AppTextStyles.labelSmall.copyWith(
                            fontSize: 9,
                            color: isToday
                                ? AppColors.secondary
                                : context.hcTextSecondary,
                            fontWeight:
                                isToday ? FontWeight.w700 : FontWeight.w400,
                          )),
                    ),
                  ],
                );
              }).map((child) => Expanded(child: child)).toList(),
            ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.insights_rounded,
                    color: AppColors.secondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.summary?.average == null
                        ? (isUrdu
                            ? 'مزید اندراجات سے بہتر رجحان بنے گا۔'
                            : 'More check-ins will build a clearer trend.')
                        : '${isUrdu ? "ہفتہ وار اوسط" : "Weekly average"}: ${provider.summary!.average!.toStringAsFixed(1)}/5',
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.secondary,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => context.push(AppRoutes.mood),
              child: Text(isUrdu ? 'موڈ کا اندراج' : 'Open mood check-in'),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Sleep Stats Card ---------------------------------------------------------

class _SleepStatsCard extends StatelessWidget {
  final bool isUrdu;
  const _SleepStatsCard({required this.isUrdu});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(18),
        decoration: _cardDecoration(context),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(
              isUrdu
                  ? 'نیند اور فون کے استعمال کا ریکارڈ'
                  : 'Your sleep and phone usage',
              style: AppTextStyles.titleSmall),
          const SizedBox(height: 8),
          Text(isUrdu
              ? 'حقیقی استعمال دیکھیں، رسائی دیں اور نیند کے اوقات محفوظ کریں۔'
              : 'Record bedtime and wake time. Sleep details and phone access are optional.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => context.push(AppRoutes.digitalWellbeing),
            icon: const Icon(Icons.bedtime_outlined),
            label: Text(isUrdu
                ? 'نیند اور استعمال کھولیں'
                : 'Open sleep & phone usage'),
          ),
        ]),
      );
}

// --- Hum-Raaz Card ------------------------------------------------------------

class _HumRaazCard extends StatelessWidget {
  final bool isUrdu;
  const _HumRaazCard({required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0EA5E9),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.chat_bubble_rounded,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(isUrdu ? 'ہم راز' : 'Hum-Raaz',
                    style: AppTextStyles.titleMedium
                        .copyWith(color: Colors.white)),
                const SizedBox(height: 3),
                Text(
                  isUrdu
                      ? 'اپنی پسند کی زبان میں جذباتی معاونت'
                      : 'Emotional support in your preferred language',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => context.push(AppRoutes.chatbot),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0EA5E9),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            child: Text(isUrdu ? 'چیٹ' : 'Chat',
                style: AppTextStyles.labelLarge
                    .copyWith(color: const Color(0xFF0EA5E9))),
          ),
        ],
      ),
    );
  }
}

// --- Section Header -----------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.titleSmall.copyWith(fontSize: 16)),
            Text(subtitle,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
          ],
        )),
      ],
    );
  }
}
