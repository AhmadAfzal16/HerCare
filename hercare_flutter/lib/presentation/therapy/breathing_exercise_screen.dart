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

class BreathingExerciseScreen extends StatefulWidget {
  const BreathingExerciseScreen({super.key, required this.patternId});
  final String patternId;
  @override
  State<BreathingExerciseScreen> createState() =>
      _BreathingExerciseScreenState();
}

class _BreathingExerciseScreenState extends State<BreathingExerciseScreen>
    with SingleTickerProviderStateMixin {
  late final _pattern = _BreathingPattern.fromId(widget.patternId);
  late final AnimationController _animation;
  Timer? _timer;
  int _phaseIndex = 0;
  int _phaseRemaining = 0;
  int _elapsed = 0;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _animation = AnimationController(vsync: this);
    _phaseRemaining = _pattern.phases.first.seconds;
  }

  void _toggle() => _running ? _pause() : _start();

  void _start() {
    setState(() => _running = true);
    _animatePhase();
    _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_running) return;
      setState(() {
        _elapsed += 1;
        _phaseRemaining -= 1;
        if (_phaseRemaining <= 0) {
          _phaseIndex = (_phaseIndex + 1) % _pattern.phases.length;
          _phaseRemaining = _pattern.phases[_phaseIndex].seconds;
          HapticFeedback.selectionClick();
          _animatePhase();
        }
      });
    });
  }

  void _animatePhase() {
    final phase = _pattern.phases[_phaseIndex];
    _animation.duration = Duration(seconds: phase.seconds);
    if (phase.kind == _PhaseKind.inhale) {
      _animation.forward(from: 0);
    } else if (phase.kind == _PhaseKind.exhale) {
      _animation.reverse(from: 1);
    } else if (_animation.value < .5) {
      _animation.value = 0;
    } else {
      _animation.value = 1;
    }
  }

  void _pause() {
    _animation.stop();
    setState(() => _running = false);
  }

  Future<void> _finish() async {
    _pause();
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    final session = await showTherapyCompletionSheet(
      context,
      type: 'breathing',
      activityId: _pattern.id,
      durationSeconds: _elapsed.clamp(1, 7200),
      isUrdu: isUrdu,
    );
    if (!mounted || session == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(session.isSynced
          ? (isUrdu ? 'سیشن محفوظ ہو گیا' : 'Session saved')
          : (isUrdu
              ? 'آف لائن محفوظ، بعد میں ہم آہنگ ہوگا'
              : 'Saved offline and will sync later')),
    ));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final phase = _pattern.phases[_phaseIndex];
    final activity = TherapyCatalog.byId(_pattern.id);
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        surfaceTintColor: Colors.transparent,
        title: Text(isUrdu ? activity.titleUr : activity.title,
            style: AppTextStyles.titleMedium),
      ),
      body: SafeArea(
        child: LayoutBuilder(builder: (context, constraints) {
          final orbSize = (constraints.maxWidth * .56).clamp(150.0, 250.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            child: ConstrainedBox(
              constraints:
                  BoxConstraints(minHeight: constraints.maxHeight - 48),
              child: Column(children: [
                Text(
                  isUrdu
                      ? 'اگر چکر آئے یا تکلیف ہو تو رک جائیں اور معمول کی سانس لیں۔'
                      : 'Stop and return to normal breathing if you feel dizzy or uncomfortable.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: context.hcTextSecondary),
                ),
                const SizedBox(height: 26),
                AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    final scale = .66 + (_animation.value * .34);
                    return SizedBox.square(
                      dimension: orbSize,
                      child: Center(
                        child: Transform.scale(
                          scale: scale,
                          child: Container(
                            width: orbSize,
                            height: orbSize,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [
                                AppColors.primaryLight.withValues(alpha: .72),
                                AppColors.primary.withValues(alpha: .94),
                              ]),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      AppColors.primary.withValues(alpha: .2),
                                  blurRadius: 30,
                                  spreadRadius: 8,
                                )
                              ],
                            ),
                            child: Center(
                                child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(phase.label(isUrdu),
                                    style: AppTextStyles.headlineSmall
                                        .copyWith(color: Colors.white)),
                                Text('$_phaseRemaining',
                                    style: AppTextStyles.headlineLarge
                                        .copyWith(color: Colors.white)),
                              ],
                            )),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 28),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: _pattern.phases.asMap().entries.map((entry) {
                    final selected = entry.key == _phaseIndex;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.primaryContainer
                            : context.hcSurface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                            color: selected
                                ? AppColors.primary
                                : context.hcOutline),
                      ),
                      child: Text(
                          '${entry.value.label(isUrdu)} ${entry.value.seconds}s',
                          style: AppTextStyles.labelSmall),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 28),
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _toggle,
                      icon: Icon(_running
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                      label: Text(_running
                          ? (isUrdu ? 'وقفہ' : 'Pause')
                          : (_elapsed == 0
                              ? (isUrdu ? 'شروع کریں' : 'Start')
                              : (isUrdu ? 'جاری رکھیں' : 'Resume'))),
                    ),
                  ),
                  if (_elapsed > 0) ...[
                    const SizedBox(width: 10),
                    OutlinedButton(
                        onPressed: _finish,
                        child: Text(isUrdu ? 'مکمل' : 'Finish')),
                  ],
                ]),
                const SizedBox(height: 12),
                Text(
                    '${(_elapsed ~/ 60).toString().padLeft(2, '0')}:${(_elapsed % 60).toString().padLeft(2, '0')}',
                    style: AppTextStyles.labelLarge
                        .copyWith(color: context.hcTextSecondary)),
              ]),
            ),
          );
        }),
      ),
    );
  }
}

enum _PhaseKind { inhale, hold, exhale, rest }

class _BreathingPhase {
  const _BreathingPhase(this.kind, this.seconds);
  final _PhaseKind kind;
  final int seconds;
  String label(bool urdu) => switch (kind) {
        _PhaseKind.inhale => urdu ? 'سانس لیں' : 'Inhale',
        _PhaseKind.hold => urdu ? 'روکیں' : 'Hold',
        _PhaseKind.exhale => urdu ? 'سانس چھوڑیں' : 'Exhale',
        _PhaseKind.rest => urdu ? 'آرام' : 'Rest',
      };
}

class _BreathingPattern {
  const _BreathingPattern(this.id, this.phases);
  final String id;
  final List<_BreathingPhase> phases;
  static _BreathingPattern fromId(String id) => switch (id) {
        'breathing_478' => const _BreathingPattern('breathing_478', [
            _BreathingPhase(_PhaseKind.inhale, 4),
            _BreathingPhase(_PhaseKind.hold, 7),
            _BreathingPhase(_PhaseKind.exhale, 8),
          ]),
        'diaphragmatic' => const _BreathingPattern('diaphragmatic', [
            _BreathingPhase(_PhaseKind.inhale, 4),
            _BreathingPhase(_PhaseKind.exhale, 6),
          ]),
        _ => const _BreathingPattern('box_breathing', [
            _BreathingPhase(_PhaseKind.inhale, 4),
            _BreathingPhase(_PhaseKind.hold, 4),
            _BreathingPhase(_PhaseKind.exhale, 4),
            _BreathingPhase(_PhaseKind.rest, 4),
          ]),
      };
}
