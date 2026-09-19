import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';
import '../../core/constants/app_constants.dart';

class EpdsResultScreen extends StatelessWidget {
  final int score;
  
  const EpdsResultScreen({super.key, required this.score});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    // Determine risk band
    Color ringColor;
    String riskEn;
    String riskUr;
    String descEn;
    String descUr;

    if (score <= AppConstants.epdsLowThreshold) {
      ringColor = AppColors.success;
      riskEn = 'Normal';
      riskUr = 'عام';
      descEn = "You're taking great steps for your well-being. A 'Normal' score suggests you are adapting well to motherhood. Keep prioritizing self-care.";
      descUr = "آپ اپنی صحت کے لیے بہترین اقدامات کر رہی ہیں۔ 'عام' اسکور ظاہر کرتا ہے کہ آپ زچگی کے ساتھ اچھی طرح ڈھل رہی ہیں۔ اپنا خیال رکھنا جاری رکھیں۔";
    } else if (score <= AppConstants.epsModerateThreshold) {
      ringColor = AppColors.warning;
      riskEn = 'Mild Risk';
      riskUr = 'کم خطرہ';
      descEn = "A 'Mild Risk' suggests you might be experiencing early signs of stress or mood changes common in motherhood. Early support makes a significant difference, and we're here for you.";
      descUr = "یہ اسکور ظاہر کرتا ہے کہ آپ زچگی میں عام تناؤ یا موڈ میں تبدیلی کی ابتدائی علامات محسوس کر سکتی ہیں۔ ابتدائی مدد بہت اہم ہے اور ہم آپ کے لیے موجود ہیں۔";
    } else {
      ringColor = AppColors.error;
      riskEn = 'High Risk';
      riskUr = 'زیادہ خطرہ';
      descEn = "Your score indicates you are experiencing significant distress. You are not alone and help is available. We strongly recommend speaking to a professional or connecting with Hum-Raaz immediately.";
      descUr = "آپ کا اسکور ظاہر کرتا ہے کہ آپ کافی تکلیف میں ہیں۔ آپ اکیلی نہیں ہیں اور مدد دستیاب ہے۔ ہم سختی سے مشورہ دیتے ہیں کہ فوری طور پر ہم راز یا کسی ماہر سے بات کریں۔";
    }

    return Scaffold(
      backgroundColor: context.hcBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isUrdu ? 'اسکریننگ کا نتیجہ' : 'Post-Assessment Score',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium,
              ),
              const SizedBox(height: 48),

              // ─── Circular Score Indicator ────────────────────────────────────
              Center(
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: context.hcSurface,
                    boxShadow: [
                      BoxShadow(
                        color: ringColor.withValues(alpha: 0.15),
                        blurRadius: 40,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 200,
                        height: 200,
                        child: CircularProgressIndicator(
                          value: score / AppConstants.epdsMaxScore,
                          strokeWidth: 12,
                          backgroundColor: ringColor.withValues(alpha: 0.2),
                          valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$score',
                                style: AppTextStyles.headlineLarge.copyWith(
                                  fontSize: 48,
                                  fontWeight: FontWeight.w900,
                                  color: context.hcTextPrimary,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8, left: 4),
                                child: Text(
                                  '/ 30',
                                  style: AppTextStyles.titleMedium.copyWith(
                                    color: context.hcTextSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isUrdu ? riskUr : riskEn,
                            style: AppTextStyles.titleSmall.copyWith(
                              color: ringColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 48),

              // ─── Advice Text ──────────────────────────────────────────────────
              Text(
                isUrdu ? descUr : descEn,
                textAlign: TextAlign.center,
                textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                style: (isUrdu ? AppTextStyles.urduBody : AppTextStyles.bodyMedium).copyWith(
                  height: 1.6,
                  color: AppColors.textPrimary.withValues(alpha: 0.8),
                ),
              ),
              
              const Spacer(),

              // ─── Action Buttons ───────────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      // Navigate to chatbot (Phase 1 placeholder)
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isUrdu ? 'ہم راز کے ساتھ چیٹ کریں' : 'Chat with Hum-Raaz',
                          style: AppTextStyles.labelLarge.copyWith(
                              color: Colors.white, fontSize: 16),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: OutlinedButton(
                  onPressed: () {
                    context.goNamed('home');
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: BorderSide(
                        color: AppColors.outline.withValues(alpha: 0.5), width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    isUrdu ? 'ہوم پر واپس جائیں' : 'Back to Home',
                    style: AppTextStyles.labelLarge.copyWith(fontSize: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
