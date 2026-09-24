import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/screening_models.dart';
import '../../providers/language_provider.dart';

class EpdsResultScreen extends StatelessWidget {
  const EpdsResultScreen({super.key, required this.assessment});

  final ScreeningAssessment assessment;

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final presentation = _presentation(assessment.riskLevel ?? 'low', isUrdu);
    final score = assessment.totalScore ?? 0;
    final maxScore = assessment.instrumentType == 'phq9' ? 27 : 30;

    return Scaffold(
      backgroundColor: context.hcBg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          children: [
            Text(
              isUrdu ? 'اسکریننگ کا نتیجہ' : 'Your screening result',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              isUrdu
                  ? 'یہ تشخیص نہیں ہے۔ ضرورت پڑنے پر ذہنی صحت کے ماہر سے رابطہ کریں۔'
                  : 'This result is not a diagnosis. A qualified professional can provide a full assessment.',
              textAlign: TextAlign.center,
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
              style: AppTextStyles.bodySmall.copyWith(
                color: context.hcTextSecondary,
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: SizedBox.square(
                dimension: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 200,
                      child: CircularProgressIndicator(
                        value: score / maxScore,
                        strokeWidth: 12,
                        strokeCap: StrokeCap.round,
                        backgroundColor:
                            presentation.color.withValues(alpha: .15),
                        valueColor: AlwaysStoppedAnimation(presentation.color),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$score',
                            style: AppTextStyles.headlineLarge.copyWith(
                              fontSize: 48,
                              fontWeight: FontWeight.w800,
                            )),
                        Text('/ $maxScore', style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 5),
                        Text(
                          presentation.label,
                          style: AppTextStyles.titleSmall.copyWith(
                            color: presentation.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: context.hcSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: presentation.color.withValues(alpha: .25),
                ),
              ),
              child: Text(
                presentation.description,
                textAlign: TextAlign.center,
                textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                style:
                    (isUrdu ? AppTextStyles.urduBody : AppTextStyles.bodyMedium)
                        .copyWith(height: 1.65),
              ),
            ),
            if (assessment.selfHarmPositive) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  isUrdu
                      ? 'آپ کے حفاظتی جواب کی وجہ سے فوری مدد ضروری ہے۔ کسی قابل اعتماد شخص کے ساتھ رہیں اور پیشہ ورانہ یا ایمرجنسی مدد حاصل کریں۔'
                      : 'Your safety response needs immediate attention. Stay with someone you trust and seek professional or emergency support now.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                onPressed: () => context.push(AppRoutes.crisis),
                icon: const Icon(Icons.health_and_safety_rounded),
                label: Text(
                    isUrdu ? 'فوری مدد حاصل کریں' : 'Open immediate support'),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.home),
              icon: const Icon(Icons.home_outlined),
              label: Text(isUrdu ? 'ہوم پر واپس جائیں' : 'Back to home'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => context.push(AppRoutes.screeningHistory),
              icon: const Icon(Icons.history_rounded),
              label: Text(
                  isUrdu ? 'پچھلی جانچیں دیکھیں' : 'View screening history'),
            ),
          ],
        ),
      ),
    );
  }

  _ResultPresentation _presentation(String risk, bool isUrdu) {
    switch (risk) {
      case 'moderate':
        return _ResultPresentation(
          AppColors.warning,
          isUrdu ? 'درمیانی علامات' : 'Moderate indicators',
          isUrdu
              ? 'آپ کے جوابات کچھ جذباتی مشکلات ظاہر کرتے ہیں۔ کسی قابل اعتماد شخص سے بات کریں اور اگر علامات برقرار رہیں تو ماہر سے رابطہ کریں۔'
              : 'Your answers show some emotional difficulties. Talk with someone you trust and consider professional support if these feelings continue.',
        );
      case 'high':
        return _ResultPresentation(
          Colors.deepOrange,
          isUrdu ? 'زیادہ علامات' : 'High indicators',
          isUrdu
              ? 'آپ کے جوابات مزید ذہنی صحت کے جائزے کی ضرورت ظاہر کرتے ہیں۔ جلد کسی ڈاکٹر یا ذہنی صحت کے ماہر سے رابطہ کریں۔'
              : 'Your answers indicate that a further mental-health assessment would be appropriate. Please contact a doctor or mental-health professional soon.',
        );
      case 'severe':
        return _ResultPresentation(
          AppColors.error,
          isUrdu ? 'شدید علامات' : 'Severe indicators',
          isUrdu
              ? 'فوری پیشہ ورانہ مدد کی سفارش کی جاتی ہے۔ کسی قابل اعتماد شخص کو بتائیں اور آج ہی ڈاکٹر یا ذہنی صحت کے ماہر سے رابطہ کریں۔'
              : 'Urgent professional support is recommended. Tell someone you trust and contact a doctor or mental-health professional today.',
        );
      default:
        return _ResultPresentation(
          AppColors.success,
          isUrdu ? 'کم علامات' : 'Low indicators',
          isUrdu
              ? 'آپ کے موجودہ جوابات کم علامات ظاہر کرتے ہیں۔ اپنی کیفیت پر نظر رکھیں اور اگر آپ پریشان ہوں تو مدد حاصل کریں۔'
              : 'Your current answers show low indicators. Continue checking in and seek support whenever you are concerned.',
        );
    }
  }
}

class _ResultPresentation {
  const _ResultPresentation(this.color, this.label, this.description);
  final Color color;
  final String label;
  final String description;
}
