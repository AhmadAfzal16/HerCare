import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/language_provider.dart';

/// Daily Islamic verse card — cycles through curated Quranic ayahs.
class DailyVerseCard extends StatefulWidget {
  const DailyVerseCard({super.key});

  @override
  State<DailyVerseCard> createState() => _DailyVerseCardState();
}

class _DailyVerseCardState extends State<DailyVerseCard>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnim;

  // Curated verses relevant to mothers, hope, and resilience
  static const _verses = [
    _Verse(
      arabic: 'وَمَن يَتَّقِ اللَّهَ يَجْعَل لَّهُ مَخْرَجًا',
      urdu: 'اور جو اللہ سے ڈرے، وہ اس کے لیے راستہ نکال دیتا ہے',
      source: 'Surah At-Talaq 65:2',
    ),
    _Verse(
      arabic: 'إِنَّ مَعَ الْعُسْرِ يُسْرًا',
      urdu: 'بے شک تکلیف کے ساتھ آسانی ہے',
      source: 'Surah Ash-Sharh 94:6',
    ),
    _Verse(
      arabic: 'وَعَسَىٰ أَن تَكْرَهُوا شَيْئًا وَهُوَ خَيْرٌ لَّكُمْ',
      urdu: 'اور ہو سکتا ہے کہ تم کسی چیز کو ناپسند کرو اور وہ تمہارے لیے بہتر ہو',
      source: 'Surah Al-Baqarah 2:216',
    ),
    _Verse(
      arabic: 'فَإِنَّ مَعَ الْعُسْرِ يُسْرًا',
      urdu: 'پس بے شک تکلیف کے ساتھ آسانی ہے',
      source: 'Surah Ash-Sharh 94:5',
    ),
    _Verse(
      arabic: 'وَهُوَ مَعَكُمْ أَيْنَ مَا كُنتُمْ',
      urdu: 'اور وہ تمہارے ساتھ ہے جہاں بھی تم ہو',
      source: 'Surah Al-Hadid 57:4',
    ),
    _Verse(
      arabic: 'لَا تَحْزَنْ إِنَّ اللَّهَ مَعَنَا',
      urdu: 'غم نہ کرو، بے شک اللہ ہمارے ساتھ ہے',
      source: 'Surah At-Tawbah 9:40',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.value = 1.0;
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _nextVerse() async {
    await _fadeController.reverse();
    setState(() => _index = (_index + 1) % _verses.length);
    await _fadeController.forward();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final verse = _verses[_index];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isUrdu ? 'آج آپ کے لیے' : 'Today for You',
            style: AppTextStyles.titleSmall.copyWith(fontSize: 16),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: AppColors.cardGradient,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Crescent decoration
                const Positioned(
                  top: 14,
                  right: 16,
                  child: Text('🌙', style: TextStyle(fontSize: 22)),
                ),

                // Verse counter dots
                Positioned(
                  bottom: 16,
                  right: 20,
                  child: Row(
                    children: List.generate(_verses.length, (i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: const EdgeInsets.only(left: 4),
                        width: _index == i ? 16 : 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _index == i
                              ? AppColors.primary
                              : AppColors.primary.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 48, 44),
                  child: FadeTransition(
                    opacity: _fadeAnim,
                    child: Column(
                      children: [
                        // Arabic
                        Text(
                          verse.arabic,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          style: AppTextStyles.urduHeadline.copyWith(
                            fontSize: 20,
                            color: AppColors.primaryDark,
                            height: 2.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                            height: 1,
                            color: AppColors.primary.withValues(alpha: 0.12)),
                        const SizedBox(height: 10),

                        // Urdu translation
                        Text(
                          verse.urdu,
                          textAlign: TextAlign.center,
                          textDirection: TextDirection.rtl,
                          style: AppTextStyles.urduLabel.copyWith(
                            color: context.hcTextPrimary,
                            fontSize: 14,
                            height: 2.0,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // Source
                        Text(
                          verse.source,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodySmall.copyWith(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Next verse button
                        GestureDetector(
                          onTap: _nextVerse,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  isUrdu ? 'اگلی آیت' : 'Next verse',
                                  style: AppTextStyles.labelSmall.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_forward_rounded,
                                    color: AppColors.primary, size: 14),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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

class _Verse {
  final String arabic;
  final String urdu;
  final String source;
  const _Verse({
    required this.arabic,
    required this.urdu,
    required this.source,
  });
}


