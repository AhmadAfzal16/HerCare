import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/screening_models.dart';
import '../../providers/language_provider.dart';
import '../../providers/screening_provider.dart';

class EpdsScreen extends StatefulWidget {
  const EpdsScreen({
    super.key,
    this.hideBackButton = false,
    this.instrumentType = 'epds',
  });

  final bool hideBackButton;
  final String instrumentType;

  @override
  State<EpdsScreen> createState() => _EpdsScreenState();
}

class _EpdsScreenState extends State<EpdsScreen> {
  int _currentIndex = 0;
  bool _q10SafetyOpened = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final language = context.read<LanguageProvider>().isUrdu ? 'ur' : 'en';
    await context.read<ScreeningProvider>().initialize(
          language: language,
          instrumentType: widget.instrumentType,
        );
    if (!mounted) return;
    final provider = context.read<ScreeningProvider>();
    if (provider.answers.isNotEmpty && provider.instrument != null) {
      final firstMissing = provider.instrument!.questions.indexWhere(
        (question) => !provider.answers.containsKey(question.number),
      );
      setState(() => _currentIndex = firstMissing < 0
          ? provider.instrument!.questions.length - 1
          : firstMissing);
    }
  }

  Future<void> _select(
    ScreeningQuestion question,
    ScreeningOption option,
  ) async {
    await context
        .read<ScreeningProvider>()
        .chooseAnswer(question.number, option.index);
    if (!mounted) return;
    final instrument = context.read<ScreeningProvider>().instrument;
    if (instrument != null &&
        question.number == instrument.crisisQuestion &&
        option.score > 0 &&
        !_q10SafetyOpened) {
      _q10SafetyOpened = true;
      await context.push(AppRoutes.crisis);
      if (mounted) _q10SafetyOpened = false;
    }
  }

  Future<void> _next() async {
    final provider = context.read<ScreeningProvider>();
    final instrument = provider.instrument!;
    final question = instrument.questions[_currentIndex];
    if (!provider.answers.containsKey(question.number)) {
      _showMessage(
          'Please select the answer that best describes the past seven days.');
      return;
    }
    if (_currentIndex < instrument.questions.length - 1) {
      setState(() => _currentIndex += 1);
      return;
    }
    if (!provider.isComplete) {
      final missing = instrument.questions.indexWhere(
        (item) => !provider.answers.containsKey(item.number),
      );
      setState(() => _currentIndex = missing < 0 ? 0 : missing);
      _showMessage('Please answer every question before submitting.');
      return;
    }
    final result = await provider.submit();
    if (!mounted) return;
    if (result != null) {
      context.goNamed('epds-result', extra: result);
    } else if (provider.error != null) {
      _showMessage(provider.error!);
    }
  }

  void _back() {
    if (_currentIndex > 0) {
      setState(() => _currentIndex -= 1);
    } else if (!widget.hideBackButton && context.canPop()) {
      context.pop();
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScreeningProvider>();
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.hideBackButton
            ? null
            : IconButton(
                onPressed: _back,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
        title: Text(widget.instrumentType == 'phq9'
            ? (isUrdu ? 'PHQ-9 فالو اپ' : 'PHQ-9 Follow-up')
            : (isUrdu
                ? 'زچگی کے بعد صحت کی جانچ'
                : 'Maternal Wellness Check-in')),
        actions: [
          IconButton(
            tooltip: isUrdu ? 'پچھلی جانچیں' : 'Screening history',
            onPressed: () => context.push(AppRoutes.screeningHistory),
            icon: const Icon(Icons.history_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.instrument == null || provider.current == null
                ? _LoadError(
                    message: provider.error,
                    onRetry: _initialize,
                    isUrdu: isUrdu,
                  )
                : _assessment(provider, isUrdu),
      ),
    );
  }

  Widget _assessment(ScreeningProvider provider, bool isUrdu) {
    final instrument = provider.instrument!;
    final question = instrument.questions[_currentIndex];
    final selected = provider.answers[question.number];
    final isLast = _currentIndex == instrument.questions.length - 1;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value:
                            (_currentIndex + 1) / instrument.questions.length,
                        minHeight: 8,
                        backgroundColor: AppColors.primaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${_currentIndex + 1}/${instrument.questions.length}',
                    style: AppTextStyles.labelMedium,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primaryContainer.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  isUrdu
                      ? 'گزشتہ ${instrument.timeframeDays == 7 ? 'سات' : 'چودہ'} دنوں کے مطابق جواب دیں۔ یہ جانچ تشخیص نہیں بلکہ مدد کی ضرورت پہچاننے کا ذریعہ ہے۔'
                      : 'Answer for the past ${instrument.timeframeDays} days. This is a screening tool, not a diagnosis.',
                  textAlign: TextAlign.center,
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  style: (isUrdu
                          ? AppTextStyles.urduLabel
                          : AppTextStyles.bodySmall)
                      .copyWith(color: AppColors.primaryDark),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: context.hcSurface,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: .08),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Text(
                      question.textEn,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.titleMedium.copyWith(fontSize: 17),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      question.textUr,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.rtl,
                      style: AppTextStyles.urduHeadline.copyWith(
                        color: AppColors.primaryDark,
                        fontSize: 19,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              ...question.options.map(
                (option) => _AnswerCard(
                  option: option,
                  isSelected: selected == option.index,
                  onTap: () => _select(question, option),
                ),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          decoration: BoxDecoration(
            color: context.hcSurface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .06),
                blurRadius: 14,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: Row(
            children: [
              if (_currentIndex > 0) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: provider.isSubmitting ? null : _back,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: Text(isUrdu ? 'پیچھے' : 'Back'),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                flex: _currentIndex > 0 ? 1 : 2,
                child: FilledButton.icon(
                  onPressed: provider.isSubmitting ? null : _next,
                  icon: provider.isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(isLast
                          ? Icons.check_circle_outline_rounded
                          : Icons.arrow_forward_rounded),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(isLast
                        ? (isUrdu ? 'محفوظ کریں' : 'Submit safely')
                        : (isUrdu ? 'اگلا' : 'Next')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final ScreeningOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: Semantics(
          selected: isSelected,
          button: true,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color:
                    isSelected ? AppColors.primaryContainer : context.hcSurface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? AppColors.primary : context.hcOutline,
                  width: isSelected ? 2 : 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: isSelected
                        ? AppColors.primary
                        : context.hcTextSecondary,
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(option.textEn, style: AppTextStyles.bodyMedium),
                        const SizedBox(height: 5),
                        Text(
                          option.textUr,
                          textDirection: TextDirection.rtl,
                          style: AppTextStyles.urduLabel.copyWith(
                            color: context.hcTextSecondary,
                            height: 1.55,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _LoadError extends StatelessWidget {
  const _LoadError({
    required this.message,
    required this.onRetry,
    required this.isUrdu,
  });

  final String? message;
  final Future<void> Function() onRetry;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 58, color: AppColors.warning),
              const SizedBox(height: 16),
              Text(
                message ?? 'Screening could not be loaded.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyLarge,
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(isUrdu ? 'دوبارہ کوشش کریں' : 'Try again'),
              ),
            ],
          ),
        ),
      );
}
