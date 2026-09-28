import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';
import '../../data/models/epds_question_model.dart';


class EpdsScreen extends StatefulWidget {
  final bool hideBackButton;
  
  const EpdsScreen({super.key, this.hideBackButton = false});

  @override
  State<EpdsScreen> createState() => _EpdsScreenState();
}

class _EpdsScreenState extends State<EpdsScreen> {
  int _currentIndex = 0;
  int _totalScore = 0;

  void _handleAnswer(int score) {
    _totalScore += score;

    if (_currentIndex < epdsQuestions.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      // Quiz complete!
      // Pass the score to the result screen
      context.goNamed('epds-result', extra: _totalScore);
    }
  }

  void _handleBack() {
    if (_currentIndex > 0) {
      // Note: Going back doesn't currently subtract the score of the previous answer
      // A more robust implementation would save the history of chosen scores.
      // For phase 1, we will just pop if they hit back, or we can disable back button inside the quiz.
      // Let's just pop out of the quiz entirely if they hit back to keep state simple.
      context.pop();
    } else {
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final question = epdsQuestions[_currentIndex];
    final progress = (_currentIndex + 1) / epdsQuestions.length;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: !widget.hideBackButton,
        leading: widget.hideBackButton 
            ? null 
            : IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded,
                    color: context.hcTextPrimary, size: 20),
                onPressed: _handleBack,
              ),
        title: Text(
          isUrdu ? 'صحت کی جانچ' : 'Maternal Wellness Check-in',
          style: AppTextStyles.titleSmall.copyWith(
              color: context.hcTextPrimary, fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ─── Progress Bar ──────────────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: AppColors.primaryContainer,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isUrdu
                    ? 'سوال ${_currentIndex + 1} از ${epdsQuestions.length}'
                    : 'QUESTION ${_currentIndex + 1} OF ${epdsQuestions.length}',
                textAlign: TextAlign.center,
                style: AppTextStyles.labelMedium.copyWith(
                  color: context.hcTextSecondary,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 24),

              // ─── Question Card ─────────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                decoration: BoxDecoration(
                  color: context.hcSurface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Align(
                      alignment: Alignment.topRight,
                      child: Text('🤱', style: TextStyle(fontSize: 20)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      question.questionEn,
                      style: AppTextStyles.titleMedium.copyWith(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      question.questionUr,
                      style: AppTextStyles.urduHeadline.copyWith(
                        fontSize: 20,
                        color: AppColors.primaryDark,
                        height: 1.6,
                      ),
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ─── Answer Choices ────────────────────────────────────────────────
              Expanded(
                child: ListView.separated(
                  physics: const BouncingScrollPhysics(),
                  itemCount: question.answers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 16),
                  itemBuilder: (context, index) {
                    final answer = question.answers[index];
                    return _AnswerCard(
                      answer: answer,
                      isUrdu: isUrdu,
                      onTap: () => _handleAnswer(answer.score),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  final EpdsAnswer answer;
  final bool isUrdu;
  final VoidCallback onTap;

  const _AnswerCard({
    required this.answer,
    required this.isUrdu,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: context.hcSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.primaryContainer, width: 2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Text(
              answer.textEn,
              style: AppTextStyles.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              answer.textUr,
              style: AppTextStyles.urduLabel.copyWith(
                color: context.hcTextSecondary,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }
}
