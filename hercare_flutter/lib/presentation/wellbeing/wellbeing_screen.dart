import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/language_provider.dart';
import '../../providers/mood_provider.dart';

/// Full Wellbeing screen � deeper view of EPDS, mood, sleep, and chat.
/// Navigated to from "View all ?" on the Home Dashboard.
class WellbeingScreen extends StatelessWidget {
  final bool hideBackButton;

  const WellbeingScreen({super.key, this.hideBackButton = false});

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
        automaticallyImplyLeading: !hideBackButton,
        leading: hideBackButton
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
      body: ListView(
        physics: const BouncingScrollPhysics(),
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
            subtitle: isUrdu ? 'پچھلے 7 دن' : 'Last 7 days',
          ),
          const SizedBox(height: 12),
          RepaintBoundary(child: _MoodHistoryCard(isUrdu: isUrdu)),
          const SizedBox(height: 24),
          _SectionHeader(
            title: isUrdu ? 'نیند کے اعداد و شمار' : 'Sleep Stats',
            subtitle: isUrdu ? 'اس ہفتہ' : 'This week',
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
      ),
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

// Shared border-only card decoration.
// BoxShadow with blurRadius is CPU-rendered on Android and causes scroll jank.
// A simple 1px border achieves the same visual depth at zero GPU overhead.
BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
      color: context.hcSurface,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: context.hcOutline, width: 1),
    );

// --- EPDS Score Card ----------------------------------------------------------

class _EpdsScoreCard extends StatelessWidget {
  final bool isUrdu;
  const _EpdsScoreCard({required this.isUrdu});

  static const _history = [6, 8, 7, 9, 8, 7, 8];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _daysUr = [
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
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(isUrdu ? 'موجودہ اسکور' : 'Current Score',
                      style: AppTextStyles.bodySmall),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('8',
                          style: AppTextStyles.headlineMedium.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800)),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 4),
                        child: Text('/ 30'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.successContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isUrdu ? '😐 معتدل خطرہ' : '😐 Mild Risk',
                  style: AppTextStyles.labelMedium.copyWith(
                      color: AppColors.success, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              Text(isUrdu ? '2 دن پہلے' : '2 days ago',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
            ],
          ),
          const SizedBox(height: 20),
          Text(isUrdu ? 'پچھلی 7 اسکریننگز' : 'Last 7 screenings',
              style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
          const SizedBox(height: 10),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_history.length, (i) {
                final isLast = i == _history.length - 1;
                final barH = (_history[i] / 30 * 56).clamp(8.0, 56.0);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text('${_history[i]}',
                        style: AppTextStyles.labelSmall.copyWith(
                          fontSize: 10,
                          color: isLast
                              ? AppColors.primary
                              : context.hcTextSecondary,
                          fontWeight:
                              isLast ? FontWeight.w700 : FontWeight.w400,
                        )),
                    const SizedBox(height: 3),
                    Container(
                      width: 26,
                      height: barH,
                      decoration: BoxDecoration(
                        color: isLast
                            ? AppColors.primary
                            : AppColors.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(isUrdu ? _daysUr[i] : _days[i],
                        style: AppTextStyles.labelSmall.copyWith(fontSize: 9)),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _RiskChip(
                  label: isUrdu ? 'معمول' : 'Normal',
                  color: AppColors.success,
                  range: '0–8'),
              _RiskChip(
                  label: isUrdu ? 'معتدل' : 'Mild',
                  color: AppColors.warning,
                  range: '9–12'),
              _RiskChip(
                  label: isUrdu ? 'زیادہ' : 'High',
                  color: AppColors.error,
                  range: '13+'),
            ],
          ),
        ],
      ),
    );
  }
}

class _RiskChip extends StatelessWidget {
  final String label;
  final Color color;
  final String range;
  const _RiskChip(
      {required this.label, required this.color, required this.range});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text('$label ($range)',
          style: AppTextStyles.labelSmall.copyWith(
              color: color, fontWeight: FontWeight.w600, fontSize: 10)),
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
                final isToday = i == entries.length - 1;
                return Column(
                  children: [
                    // Rounded rect instead of BoxShape.circle � much cheaper paint
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
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _SleepStat(
                      icon: Icons.bedtime_rounded,
                      color: AppColors.accent,
                      label: isUrdu ? 'اوسط نیند' : 'Avg Sleep',
                      value: '6h 20m',
                      sub: isUrdu ? 'اوسط سے کم' : 'Below avg',
                      subColor: AppColors.warning)),
              const SizedBox(width: 12),
              Expanded(
                  child: _SleepStat(
                      icon: Icons.nightlight_round,
                      color: AppColors.primary,
                      label: isUrdu ? 'سونے کا وقت' : 'Bedtime',
                      value: '11:30 PM',
                      sub: isUrdu ? 'دیر' : 'Late',
                      subColor: AppColors.warning)),
              const SizedBox(width: 12),
              Expanded(
                  child: _SleepStat(
                      icon: Icons.wb_sunny_rounded,
                      color: AppColors.secondary,
                      label: isUrdu ? 'جاگنے کا وقت' : 'Wake time',
                      value: '5:50 AM',
                      sub: isUrdu ? 'مستقل' : 'Consistent',
                      subColor: AppColors.success)),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: context.isDark
                  ? const Color(0xFF0A3340)
                  : const Color(0xFFE0F7FA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.tips_and_updates_outlined,
                    color: AppColors.accent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isUrdu
                        ? 'رات 10 بجے تک سونے کی کوشش کریں — بہتر نیند PPD کا خطرہ کم کرتی ہے۔'
                        : 'Try sleeping by 10 PM — better sleep reduces PPD risk.',
                    style: AppTextStyles.bodySmall.copyWith(
                        color: AppColors.accent, fontWeight: FontWeight.w500),
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

class _SleepStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String sub;
  final Color subColor;
  const _SleepStat(
      {required this.icon,
      required this.color,
      required this.label,
      required this.value,
      required this.sub,
      required this.subColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(label,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 10),
              textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text(value,
              style:
                  AppTextStyles.titleSmall.copyWith(fontSize: 13, color: color),
              textAlign: TextAlign.center),
          const SizedBox(height: 3),
          Text(sub,
              style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 9, color: subColor, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// --- Hum-Raaz Card ------------------------------------------------------------

class _HumRaazCard extends StatelessWidget {
  final bool isUrdu;
  const _HumRaazCard({required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    // Solid color only  no LinearGradient + BoxShadow combo (expensive)
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
            child:
                const Icon(Icons.chat_bubble_rounded, color: Colors.white, size: 26),
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
                      ? '24/7 ذہنی صحت کا AI ساتھی'
                      : '24/7 AI mental health companion',
                  style: AppTextStyles.bodySmall
                      .copyWith(color: Colors.white.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {},
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
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyles.titleSmall.copyWith(fontSize: 16)),
            Text(subtitle,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 11)),
          ],
        ),
      ],
    );
  }
}
