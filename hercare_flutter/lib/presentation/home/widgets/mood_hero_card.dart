import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../providers/language_provider.dart';
import 'package:provider/provider.dart';

/// Gradient hero card — mood check-in + postpartum day badge.
class MoodHeroCard extends StatefulWidget {
  const MoodHeroCard({super.key});

  @override
  State<MoodHeroCard> createState() => _MoodHeroCardState();
}

class _MoodHeroCardState extends State<MoodHeroCard> {
  int? _selectedMood; // 0–4

  static const _moods = ['😔', '😐', '🙂', '😊', '😍'];
  static const _moodLabelsEn = ['Very low', 'Low', 'Okay', 'Good', 'Great'];
  static const _moodLabelsUr = ['بہت کم', 'کم', 'ٹھیک ہے', 'اچھا', 'بہترین'];

  // Placeholder — will come from onboarding_data / backend in Phase 2
  static const int _dayPostpartum = 47;

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative heart glow (top-right)
          Positioned(
            right: -16,
            top: -16,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            right: 16,
            top: 16,
            child: Icon(
              Icons.favorite_rounded,
              color: Colors.white.withOpacity(0.20),
              size: 52,
            ),
          ),

          // Main content
          Padding(
            padding: EdgeInsets.fromLTRB(20, isUrdu ? 12 : 18, 20, isUrdu ? 12 : 18),
            child: Column(
              crossAxisAlignment: isUrdu
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Day badge
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isUrdu
                        ? 'زچگی کے بعد $_dayPostpartum واں دن'
                        : 'Day $_dayPostpartum Postpartum',
                    style: AppTextStyles.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                SizedBox(height: isUrdu ? 8 : 12),

                // Title
                Text(
                  isUrdu ? 'آج آپ کیسا محسوس کر رہی ہیں؟' : 'How are you feeling today?',
                  style: AppTextStyles.titleLarge.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: isUrdu ? 16 : 20,
                  ),
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                ),
                SizedBox(height: isUrdu ? 2 : 4),
                Text(
                  _selectedMood == null
                      ? (isUrdu ? 'موڈ لاگ کرنے کے لیے ٹیپ کریں' : 'Tap to log your mood')
                      : (isUrdu
                          ? _moodLabelsUr[_selectedMood!]
                          : _moodLabelsEn[_selectedMood!]),
                  style: AppTextStyles.bodySmall.copyWith(
                    color: Colors.white.withOpacity(0.80),
                    fontSize: 13,
                  ),
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                ),
                SizedBox(height: isUrdu ? 10 : 16),

                // Emoji mood row — use Wrap to avoid RTL overflow
                Wrap(
                  direction: Axis.horizontal,
                  alignment: isUrdu
                      ? WrapAlignment.end
                      : WrapAlignment.start,
                  spacing: 8,
                  children: List.generate(_moods.length, (i) {
                    final selected = _selectedMood == i;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedMood = i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: selected ? 52 : 46,
                        height: selected ? 52 : 46,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withOpacity(0.30)
                              : Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                          border: selected
                              ? Border.all(
                                  color: Colors.white.withOpacity(0.8),
                                  width: 2)
                              : null,
                          boxShadow: selected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : [],
                        ),
                        child: Center(
                          child: Text(
                            _moods[i],
                            style: TextStyle(fontSize: selected ? 26 : 22),
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
