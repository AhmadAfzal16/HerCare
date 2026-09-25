import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import 'therapy_completion_sheet.dart';

class MeditationScreen extends StatefulWidget {
  const MeditationScreen({super.key, required this.activityId});
  final String activityId;
  @override
  State<MeditationScreen> createState() => _MeditationScreenState();
}

class _MeditationScreenState extends State<MeditationScreen> {
  int _minutes = 5;
  int _remaining = 300;
  int _elapsed = 0;
  bool _running = false;
  Timer? _timer;

  void _selectMinutes(int value) {
    if (_running) return;
    setState(() {
      _minutes = value;
      _remaining = value * 60;
      _elapsed = 0;
    });
  }

  void _toggle() {
    if (_running) {
      setState(() => _running = false);
      return;
    }
    setState(() => _running = true);
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_running) return;
      if (_remaining <= 1) {
        setState(() {
          _remaining = 0;
          _elapsed += 1;
          _running = false;
        });
        HapticFeedback.mediumImpact();
        _finish();
      } else {
        setState(() {
          _remaining -= 1;
          _elapsed += 1;
        });
      }
    });
  }

  String _guidance(bool urdu) {
    final progress = _elapsed / (_minutes * 60);
    final guides = _guides[widget.activityId] ?? _guides['mindfulness']!;
    final index =
        (progress * guides.length).floor().clamp(0, guides.length - 1);
    return urdu ? guides[index].$2 : guides[index].$1;
  }

  Future<void> _finish() async {
    setState(() => _running = false);
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    await showTherapyCompletionSheet(
      context,
      type: 'meditation',
      activityId: widget.activityId,
      durationSeconds: _elapsed.clamp(1, 7200),
      isUrdu: isUrdu,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final activity = TherapyCatalog.byId(widget.activityId);
    final total = _minutes * 60;
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
          backgroundColor: context.hcSurface,
          surfaceTintColor: Colors.transparent,
          title: Text(isUrdu ? activity.titleUr : activity.title,
              style: AppTextStyles.titleMedium)),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(children: [
          Wrap(
              spacing: 8,
              children: [3, 5, 10, 15]
                  .map((value) => ChoiceChip(
                        label: Text('$value ${isUrdu ? 'منٹ' : 'min'}'),
                        selected: _minutes == value,
                        onSelected: (_) => _selectMinutes(value),
                      ))
                  .toList()),
          const SizedBox(height: 34),
          SizedBox.square(
            dimension: 220,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                  child: CircularProgressIndicator(
                value: total == 0 ? 0 : 1 - (_remaining / total),
                strokeWidth: 12,
                backgroundColor: AppColors.primaryContainer,
                color: AppColors.primary,
              )),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.self_improvement_rounded,
                    color: AppColors.primary, size: 40),
                const SizedBox(height: 8),
                Text(
                    '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
                    style: AppTextStyles.headlineMedium),
              ]),
            ]),
          ),
          const SizedBox(height: 30),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            child: Container(
              key: ValueKey(_guidance(isUrdu)),
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                  color: context.hcSurface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: context.hcOutline)),
              child: Text(_guidance(isUrdu),
                  textAlign: TextAlign.center, style: AppTextStyles.bodyLarge),
            ),
          ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
                child: ElevatedButton.icon(
              onPressed: _remaining == 0 ? null : _toggle,
              icon: Icon(
                  _running ? Icons.pause_rounded : Icons.play_arrow_rounded),
              label: Text(_running
                  ? (isUrdu ? 'وقفہ' : 'Pause')
                  : (isUrdu ? 'شروع / جاری' : 'Start / Resume')),
            )),
            if (_elapsed > 0) ...[
              const SizedBox(width: 10),
              OutlinedButton(
                  onPressed: _finish, child: Text(isUrdu ? 'مکمل' : 'Finish'))
            ],
          ]),
          const SizedBox(height: 16),
          Text(
              isUrdu
                  ? 'آڈیو کے بغیر بھی مکمل طور پر آف لائن کام کرتا ہے۔'
                  : 'Works fully offline with gentle text and haptic guidance.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall
                  .copyWith(color: context.hcTextSecondary)),
        ]),
      )),
    );
  }
}

const _guides = <String, List<(String, String)>>{
  'body_scan': [
    (
      'Settle into a supported position and soften your gaze.',
      'آرام دہ حالت میں بیٹھیں اور نگاہ نرم کریں۔'
    ),
    (
      'Notice your forehead, jaw, and shoulders without judging.',
      'پیشانی، جبڑے اور کندھوں کو بغیر فیصلہ کیے محسوس کریں۔'
    ),
    (
      'Let attention move gently through your chest and belly.',
      'توجہ نرمی سے سینے اور پیٹ کی طرف لائیں۔'
    ),
    (
      'Feel your legs and feet supported beneath you.',
      'ٹانگوں اور پاؤں کے نیچے سہارا محسوس کریں۔'
    ),
  ],
  'muscle_relaxation': [
    (
      'Gently tense your hands, then let them soften.',
      'ہاتھ ہلکے سے سخت کریں، پھر ڈھیلا چھوڑ دیں۔'
    ),
    (
      'Lift the shoulders slightly, then release them.',
      'کندھوں کو تھوڑا اٹھائیں، پھر چھوڑ دیں۔'
    ),
    (
      'Press your feet gently, then notice the release.',
      'پاؤں ہلکے دبائیں، پھر آرام محسوس کریں۔'
    ),
    (
      'Let the whole body rest without forcing anything.',
      'بغیر زور کے پورے جسم کو آرام دیں۔'
    ),
  ],
  'mindfulness': [
    (
      'Notice one natural breath exactly as it is.',
      'ایک قدرتی سانس کو ویسا ہی محسوس کریں۔'
    ),
    (
      'When attention wanders, gently return to breathing.',
      'توجہ بھٹکے تو نرمی سے سانس کی طرف واپس آئیں۔'
    ),
    (
      'Notice sounds around you without needing to respond.',
      'آس پاس کی آوازیں سنیں، جواب دینے کی ضرورت نہیں۔'
    ),
    (
      'Bring kindness to this moment and to yourself.',
      'اس لمحے اور اپنے لیے مہربانی لائیں۔'
    ),
  ],
};
