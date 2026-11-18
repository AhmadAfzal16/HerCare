import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../providers/language_provider.dart';
import '../../../providers/mood_provider.dart';

/// Daily mood entry point. The selection is carried into the check-in form.
class MoodHeroCard extends StatefulWidget {
  const MoodHeroCard({super.key});

  @override
  State<MoodHeroCard> createState() => _MoodHeroCardState();
}

class _MoodHeroCardState extends State<MoodHeroCard> {
  static const _moods = ['😔', '😟', '😐', '🙂', '😊'];
  static const _moodLabelsEn = ['Very low', 'Low', 'Okay', 'Good', 'Great'];
  static const _moodLabelsUr = ['بہت کم', 'کم', 'ٹھیک ہے', 'اچھا', 'بہترین'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<MoodProvider>();
      if (provider.today == null && !provider.isLoading) provider.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final today = context.watch<MoodProvider>().today;
    final selectedMood = today == null ? null : today.moodRating - 1;
    final theme = Theme.of(context);
    final dark = context.isDark;
    const ink = AppColors.textPrimary;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      decoration: BoxDecoration(
        gradient: dark
            ? const LinearGradient(
                colors: [Color(0xFF2E2556), Color(0xFF3A2245)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : AppColors.heroGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: context.hcSoftShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Soft decorative bubbles.
          PositionedDirectional(
            end: -30,
            top: -40,
            child: _Bubble(size: 140, alpha: dark ? 0.06 : 0.45),
          ),
          PositionedDirectional(
            end: 50,
            bottom: -50,
            child: _Bubble(size: 100, alpha: dark ? 0.04 : 0.30),
          ),
          PositionedDirectional(
            end: 18,
            top: 18,
            child: Icon(Icons.favorite_rounded,
                size: 34,
                color:
                    AppColors.secondary.withValues(alpha: dark ? 0.35 : 0.22)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: dark ? 0.12 : 0.75),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.wb_twilight_rounded,
                        size: 14,
                        color:
                            dark ? AppColors.primaryLight : AppColors.primary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        isUrdu ? 'روزانہ موڈ' : 'Daily mood',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: dark
                                ? AppColors.primaryLight
                                : AppColors.primary),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 40),
                  child: Text(
                    isUrdu
                        ? 'آج آپ کیسا محسوس کر رہی ہیں؟'
                        : 'How are you feeling today?',
                    style: theme.textTheme.titleLarge?.copyWith(
                        fontSize: 21, color: dark ? Colors.white : ink),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  selectedMood == null
                      ? (isUrdu
                          ? 'اپنا موڈ چنیں، بس ایک لمحہ لگے گا'
                          : 'Pick a face — it only takes a moment')
                      : (isUrdu
                          ? 'آج کا موڈ: ${_moodLabelsUr[selectedMood]}'
                          : 'Today: ${_moodLabelsEn[selectedMood]}'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                      color: dark
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  children: List.generate(_moods.length, (i) {
                    final selected = selectedMood == i;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsetsDirectional.only(
                            end: i == _moods.length - 1 ? 0 : 8),
                        child: Semantics(
                          button: true,
                          selected: selected,
                          label: isUrdu ? _moodLabelsUr[i] : _moodLabelsEn[i],
                          child: _MoodFace(
                            emoji: _moods[i],
                            selected: selected,
                            onTap: () =>
                                context.push(AppRoutes.mood, extra: i + 1),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.size, required this.alpha});
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: alpha),
        ),
      );
}

class _MoodFace extends StatelessWidget {
  const _MoodFace(
      {required this.emoji, required this.selected, required this.onTap});
  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = context.isDark;
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? (dark ? Colors.white.withValues(alpha: 0.22) : Colors.white)
              : Colors.white.withValues(alpha: dark ? 0.08 : 0.62),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: selected ? AppColors.primary : Colors.transparent,
              width: 2),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.22),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  )
                ]
              : const [],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(emoji,
                      textScaler: TextScaler.noScaling,
                      style: TextStyle(fontSize: selected ? 28 : 25)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
