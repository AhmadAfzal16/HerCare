import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import 'activity_clock.dart';
import 'therapy_completion_sheet.dart';

class CbtExerciseScreen extends StatefulWidget {
  const CbtExerciseScreen({super.key, required this.activityId});
  final String activityId;
  @override
  State<CbtExerciseScreen> createState() => _CbtExerciseScreenState();
}

class _CbtExerciseScreenState extends State<CbtExerciseScreen>
    with WidgetsBindingObserver {
  final _controllers = List.generate(4, (_) => TextEditingController());
  final _clock = ActiveTherapyClock();
  int _groundingStep = 0;
  bool _saving = false;
  bool _foreground = true;
  bool _routeActive = true;

  bool get _isGrounding => widget.activityId == 'grounding_54321';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _clock.resume();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (_foreground && _routeActive && !_saving) {
      _clock.resume();
    } else {
      _clock.pause();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _clock.pause();
    } else if (!_saving && _routeActive) {
      _clock.resume();
    }
  }

  List<(String, String)> _prompts(bool isUrdu) {
    final values = switch (widget.activityId) {
      'behavior_plan' => const [
          (
            'What is one small thing that would support you today?',
            'آج کون سا ایک چھوٹا کام آپ کو سہارا دے گا؟'
          ),
          (
            'Make it smaller and achievable in ten minutes.',
            'اسے مزید چھوٹا اور دس منٹ میں قابلِ عمل بنائیں۔'
          ),
          ('When and where will you try it?', 'آپ اسے کب اور کہاں کریں گی؟'),
          (
            'Who or what could make it easier?',
            'کون یا کیا اسے آسان بنا سکتا ہے؟'
          ),
        ],
      'worry_time' => const [
          (
            'Write the worry in one clear sentence.',
            'فکر کو ایک واضح جملے میں لکھیں۔'
          ),
          (
            'Is any part of it within your control today?',
            'کیا اس کا کوئی حصہ آج آپ کے اختیار میں ہے؟'
          ),
          (
            'Choose one action, or choose to revisit it later.',
            'ایک قدم چنیں، یا اسے بعد میں دیکھنے کا فیصلہ کریں۔'
          ),
          (
            'Choose a short time to revisit this—then return to now.',
            'اسے دوبارہ دیکھنے کے لیے مختصر وقت چنیں، پھر حال میں واپس آئیں۔'
          ),
        ],
      _ => const [
          ('What happened?', 'کیا ہوا؟'),
          ('What thought came up?', 'کون سا خیال آیا؟'),
          (
            'What supports or challenges that thought?',
            'کیا چیز اس خیال کی حمایت یا مخالفت کرتی ہے؟'
          ),
          (
            'What is a kinder, more balanced thought?',
            'زیادہ مہربان اور متوازن خیال کیا ہو سکتا ہے؟'
          ),
        ],
    };
    return values;
  }

  Future<void> _finish({bool completed = true}) async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _clock.pause();
    setState(() => _saving = true);
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    final session = await showTherapyCompletionSheet(
      context,
      type: 'cbt',
      activityId: widget.activityId,
      durationSeconds: _clock.recordedSeconds,
      completed: completed,
      isUrdu: isUrdu,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (session == null) {
      if (_foreground && _routeActive) _clock.resume();
      return;
    }
    // Worksheet text is intentionally discarded when leaving this screen.
    Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.pause();
    for (final value in _controllers) {
      value.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final activity = TherapyCatalog.byId(widget.activityId);
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
          backgroundColor: context.hcSurface,
          surfaceTintColor: Colors.transparent,
          title: Text(isUrdu ? activity.titleUr : activity.title,
              style: AppTextStyles.titleMedium)),
      body: SafeArea(
          child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 30),
        children: [
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
                color: AppColors.successContainer
                    .withValues(alpha: context.isDark ? .12 : .65),
                borderRadius: BorderRadius.circular(14)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lock_outline_rounded,
                  color: AppColors.success, size: 20),
              const SizedBox(width: 9),
              Expanded(
                  child: Text(
                      isUrdu
                          ? 'آپ کے لکھے ہوئے جوابات محفوظ یا اپ لوڈ نہیں ہوتے۔'
                          : 'Your written answers are not saved or uploaded.',
                      style: AppTextStyles.bodySmall)),
            ]),
          ),
          const SizedBox(height: 18),
          if (!_isGrounding) ...[
            Text(
                isUrdu
                    ? 'لکھنا ضروری نہیں۔ آپ صرف دل میں جواب سوچ سکتی ہیں۔'
                    : 'Typing is optional. You can think through the answers instead.',
                style: AppTextStyles.bodySmall),
            const SizedBox(height: 14),
          ],
          if (_isGrounding)
            _GroundingExercise(
              isUrdu: isUrdu,
              step: _groundingStep,
              onNext: () {
                if (_groundingStep < 5) setState(() => _groundingStep += 1);
              },
            )
          else ...[
            ..._prompts(isUrdu).asMap().entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(isUrdu ? entry.value.$2 : entry.value.$1,
                          style: AppTextStyles.titleSmall),
                      const SizedBox(height: 8),
                      TextField(
                        key: ValueKey('cbt-answer-${entry.key}'),
                        controller: _controllers[entry.key],
                        enableIMEPersonalizedLearning: false,
                        autocorrect: false,
                        enableSuggestions: false,
                        minLines: 2,
                        maxLines: 5,
                        maxLength: 500,
                        decoration: InputDecoration(
                          hintText: isUrdu ? 'اختیاری جواب' : 'Optional answer',
                          filled: true,
                          fillColor: context.hcSurface,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _saving || (_isGrounding && _groundingStep < 5)
                ? null
                : () => _finish(),
            icon: const Icon(Icons.check_circle_outline_rounded),
            label: Text(isUrdu ? 'مشق مکمل کریں' : 'Complete exercise'),
          ),
          TextButton(
            onPressed: _saving ? null : () => _finish(completed: false),
            child: Text(isUrdu ? 'پہلے روکیں' : 'Stop early'),
          ),
          const SizedBox(height: 12),
          Text(
              isUrdu
                  ? 'یہ خود مدد کی مشق ہے، تھراپی یا طبی مشورہ نہیں۔'
                  : 'This is a self-help exercise, not therapy or medical advice.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.hcTextSecondary)),
        ],
      )),
    );
  }
}

class _GroundingExercise extends StatelessWidget {
  const _GroundingExercise(
      {required this.isUrdu, required this.step, required this.onNext});
  final bool isUrdu;
  final int step;
  final VoidCallback onNext;
  static const values = <(String, String, IconData)>[
    (
      'Name 5 things you can see',
      '5 چیزیں بتائیں جو آپ دیکھ سکتی ہیں',
      Icons.visibility_outlined
    ),
    (
      'Notice 4 things you can feel',
      '4 چیزیں محسوس کریں جنہیں آپ چھو سکتی ہیں',
      Icons.touch_app_outlined
    ),
    ('Listen for 3 sounds', '3 آوازیں سنیں', Icons.hearing_outlined),
    ('Notice 2 scents', '2 خوشبوئیں محسوس کریں', Icons.air_outlined),
    (
      'Notice 1 taste or one slow breath',
      '1 ذائقہ یا ایک آہستہ سانس محسوس کریں',
      Icons.spa_outlined
    ),
  ];
  @override
  Widget build(BuildContext context) {
    if (step >= values.length) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
            isUrdu ? 'پانچوں حواس کی مشق مکمل۔' : 'All five senses explored.',
            textAlign: TextAlign.center,
            style: AppTextStyles.titleLarge),
      );
    }
    final current = values[step];
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
          color: context.hcSurface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: context.hcOutline)),
      child: Column(children: [
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                5,
                (index) => Container(
                      width: 28,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                          color: index <= step
                              ? AppColors.primary
                              : context.hcOutline,
                          borderRadius: BorderRadius.circular(6)),
                    ))),
        const SizedBox(height: 30),
        Icon(current.$3, color: AppColors.primary, size: 52),
        const SizedBox(height: 18),
        Text(isUrdu ? current.$2 : current.$1,
            textAlign: TextAlign.center, style: AppTextStyles.titleLarge),
        const SizedBox(height: 26),
        OutlinedButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(step == 4
                ? (isUrdu ? 'میں نے محسوس کیا' : 'I noticed it')
                : (isUrdu ? 'اگلا' : 'Next sense'))),
      ]),
    );
  }
}
