import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import 'activity_clock.dart';
import 'breathing_band_panel.dart';
import 'breathing_posture_screen.dart';
import 'meditation_audio.dart';
import 'session_check_card.dart';
import 'therapy_completion_sheet.dart';

class BreathingExerciseScreen extends StatefulWidget {
  const BreathingExerciseScreen(
      {super.key, required this.patternId, this.audio});
  final String patternId;
  final MeditationAudio? audio;
  @override
  State<BreathingExerciseScreen> createState() =>
      _BreathingExerciseScreenState();
}

class _BreathingExerciseScreenState extends State<BreathingExerciseScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _pattern = _BreathingPattern.fromId(widget.patternId);
  late final AnimationController _animation;
  final _clock = ActiveTherapyClock();
  late final MeditationAudio _audio;
  bool _spokenCues = true;
  bool _isUrdu = false;
  Timer? _timer;
  int _phaseIndex = 0;
  int _phaseRemaining = 0;
  bool _running = false;
  bool _saving = false;
  bool _foreground = true;
  bool _routeActive = true;
  bool _reducedMotion = false;
  TherapyMeasures _measures = const TherapyMeasures();

  int get _targetSeconds => TherapyCatalog.byId(_pattern.id).minutes * 60;

  @override
  void initState() {
    super.initState();
    _audio = widget.audio ?? BundledTherapyAudio();
    _audio.addListener(_audioChanged);
    _audio.onInterruption = () {
      if (mounted && _running) _pause();
    };
    WidgetsBinding.instance.addObserver(this);
    _animation = AnimationController(vsync: this);
    _phaseRemaining = _pattern.phases.first.seconds;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _isUrdu = context.watch<LanguageProvider>().isUrdu;
    _routeActive = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (!_routeActive && _running) _pause();
    final media = MediaQuery.of(context);
    final reduced = media.disableAnimations || media.accessibleNavigation;
    if (_reducedMotion != reduced) {
      _reducedMotion = reduced;
      _animation.stop();
      if (_running) _syncPhase(animate: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground && _running) {
      _pause();
    }
  }

  void _start() {
    if (_saving ||
        !_foreground ||
        !_routeActive ||
        _clock.seconds >= _targetSeconds) {
      return;
    }
    _clock.resume();
    setState(() => _running = true);
    _syncPhase(animate: true, speak: true);
    _timer ??= Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_running) return;
      if (_clock.seconds >= _targetSeconds) {
        _pause();
        unawaited(_finish());
        return;
      }
      final remaining = _phaseRemaining;
      final phase = _phaseIndex;
      _syncPhase();
      if (phase != _phaseIndex || remaining != _phaseRemaining) setState(() {});
    });
  }

  void _syncPhase({bool animate = false, bool speak = false}) {
    final totalMs = _pattern.phases
        .fold<int>(0, (sum, phase) => sum + phase.seconds * 1000);
    var position = _clock.elapsed.inMilliseconds % totalMs;
    var index = 0;
    while (position >= _pattern.phases[index].seconds * 1000) {
      position -= _pattern.phases[index].seconds * 1000;
      index += 1;
    }
    final changed = index != _phaseIndex;
    _phaseIndex = index;
    final phase = _pattern.phases[index];
    final remainingMs = phase.seconds * 1000 - position;
    _phaseRemaining = (remainingMs / 1000).ceil();
    if (changed || speak) _speak(phase.kind);
    if ((!changed && !animate) || _reducedMotion) return;
    _animation.duration = Duration(seconds: phase.seconds);
    final progress = position / (phase.seconds * 1000);
    switch (phase.kind) {
      case _PhaseKind.inhale:
      case _PhaseKind.topUp:
        _animation.forward(from: progress);
      case _PhaseKind.exhale:
        _animation.reverse(from: 1 - progress);
      case _PhaseKind.hold:
        _animation.value = 1;
      case _PhaseKind.rest:
        _animation.value = 0;
    }
  }

  void _audioChanged() {
    if (mounted) setState(() {});
  }

  void _speak(_PhaseKind kind) {
    if (!_spokenCues || _audio.unavailable) return;
    _audio.cue(
        // The top-up breath reuses the recorded "inhale" cue.
        'assets/audio/breathing/${_isUrdu ? 'ur' : 'en'}_${kind == _PhaseKind.topUp ? 'inhale' : kind.name}.wav');
  }

  void _pause() {
    _clock.pause();
    _timer?.cancel();
    _timer = null;
    _audio.pause();
    _animation.stop();
    if (mounted) setState(() => _running = false);
  }

  Future<void> _finish() async {
    if (_saving || _clock.elapsed == Duration.zero) return;
    _pause();
    setState(() => _saving = true);
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    _measures = await maybeAfterReading(context, _measures, isUrdu);
    if (!mounted) return;
    final session = await showTherapyCompletionSheet(
      context,
      type: 'breathing',
      activityId: _pattern.id,
      durationSeconds: _clock.recordedSeconds,
      completed: _clock.seconds >= _targetSeconds,
      isUrdu: isUrdu,
      measures: _measures,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (session != null) Navigator.pop(context);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.pause();
    _audio.removeListener(_audioChanged);
    _audio.onInterruption = null;
    if (widget.audio == null) {
      _audio.dispose();
    } else {
      _audio.stop();
    }
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final phase = _pattern.phases[_phaseIndex];
    final activity = TherapyCatalog.byId(_pattern.id);
    final elapsed = _clock.seconds;
    final minutes = _targetSeconds ~/ 60;
    final done = elapsed >= _targetSeconds;
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
          final orbSize = (constraints.maxWidth * .5).clamp(140.0, 230.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 30),
            child: Column(children: [
              Text(
                isUrdu
                    ? 'آرام دہ انداز میں بیٹھیں۔ سانس کو زور سے نہ روکیں۔ چکر یا تکلیف ہو تو رک جائیں اور معمول کی سانس لیں۔'
                    : 'Sit comfortably. Never force a breath hold. Stop and breathe normally if you feel dizzy or uncomfortable.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall
                    .copyWith(color: context.hcTextSecondary),
              ),
              if (elapsed == 0 && !_running) ...[
                const SizedBox(height: 14),
                PreSessionCheck(
                    isUrdu: isUrdu,
                    measures: _measures,
                    enabled: !_saving,
                    onChanged: (value) => setState(() => _measures = value)),
              ],
              const SizedBox(height: 20),
              Text(
                done
                    ? (isUrdu ? 'مشق مکمل' : 'Practice complete')
                    : phase.label(isUrdu),
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineSmall,
              ),
              Text('$_phaseRemaining',
                  style: AppTextStyles.headlineLarge
                      .copyWith(color: AppColors.primary)),
              const SizedBox(height: 10),
              ExcludeSemantics(
                child: AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) => SizedBox.square(
                    dimension: orbSize,
                    child: Center(
                      child: Transform.scale(
                        scale:
                            _reducedMotion ? 1 : .66 + (_animation.value * .34),
                        child: Container(
                          width: orbSize,
                          height: orbSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              AppColors.primaryLight.withValues(alpha: .72),
                              AppColors.primary.withValues(alpha: .94),
                            ]),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: _pattern.phases.asMap().entries.map((entry) {
                  final selected = entry.key == _phaseIndex;
                  return Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primaryContainer
                          : context.hcSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color:
                              selected ? AppColors.primary : context.hcOutline),
                    ),
                    child: Text(
                        '${entry.value.label(isUrdu)} ${entry.value.seconds}s',
                        style: AppTextStyles.labelSmall),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text(
                isUrdu
                    ? '$minutes منٹ کی نرم مشق؛ آپ پہلے بھی رک سکتی ہیں۔'
                    : '$minutes gentle minutes; you can stop earlier.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall,
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(isUrdu ? 'آواز میں رہنمائی' : 'Spoken cues'),
                subtitle: _audio.unavailable
                    ? Text(isUrdu
                        ? 'آواز دستیاب نہیں۔ اسکرین کی ہدایات استعمال کریں۔'
                        : 'Voice unavailable. Follow the cues on screen.')
                    : null,
                value: _spokenCues && !_audio.unavailable,
                onChanged: _audio.unavailable
                    ? null
                    : (enabled) {
                        setState(() => _spokenCues = enabled);
                        if (!enabled) _audio.pause();
                        if (enabled && _running) _speak(phase.kind);
                      },
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  key: const Key('breathing-toggle'),
                  onPressed:
                      _saving || done ? null : (_running ? _pause : _start),
                  icon: Icon(_running
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded),
                  label: Text(_running
                      ? (isUrdu ? 'وقفہ' : 'Pause')
                      : (elapsed == 0
                          ? (isUrdu
                              ? 'سانس کی مشق شروع کریں'
                              : 'Start breathing')
                          : (isUrdu ? 'جاری رکھیں' : 'Resume'))),
                ),
              ),
              if (!_running &&
                  !done &&
                  !_saving &&
                  !kIsWeb &&
                  defaultTargetPlatform == TargetPlatform.android)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                        builder: (_) => BreathingPostureScreen(isUrdu: isUrdu)),
                  ),
                  icon: const Icon(Icons.camera_front_outlined),
                  label: Text(
                      isUrdu ? 'بیٹھنے کا انداز دیکھیں' : 'Check my posture'),
                ),
              BreathingBandPanel(
                isUrdu: isUrdu,
                enabled: _foreground && _routeActive && !done && !_saving,
              ),
              if (elapsed > 0 || done) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _saving ? null : _finish,
                    child: Text(done
                        ? (isUrdu ? 'مکمل مشق محفوظ کریں' : 'Save practice')
                        : (isUrdu ? 'ابھی روکیں' : 'Stop early')),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                  '${(elapsed ~/ 60).toString().padLeft(2, '0')}:${(elapsed % 60).toString().padLeft(2, '0')}',
                  style: AppTextStyles.labelLarge
                      .copyWith(color: context.hcTextSecondary)),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                  value: (elapsed / _targetSeconds).clamp(0, 1)),
            ]),
          );
        }),
      ),
    );
  }
}

/// topUp: the short second inhale of a cyclic sigh (Balban et al. 2023).
enum _PhaseKind { inhale, topUp, hold, exhale, rest }

class _BreathingPhase {
  const _BreathingPhase(this.kind, this.seconds);
  final _PhaseKind kind;
  final int seconds;
  String label(bool urdu) => switch (kind) {
        _PhaseKind.inhale => urdu ? 'سانس لیں' : 'Inhale',
        _PhaseKind.topUp => urdu ? 'تھوڑا اور سانس' : 'Top-up breath',
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
        // Two inhales through the nose, then a long slow exhale (~6.7/min).
        'cyclic_sighing' => const _BreathingPattern('cyclic_sighing', [
            _BreathingPhase(_PhaseKind.inhale, 2),
            _BreathingPhase(_PhaseKind.topUp, 1),
            _BreathingPhase(_PhaseKind.exhale, 6),
          ]),
        // 5 s in, 5 s out = 6 breaths a minute, the usual resonance rate.
        'resonance_breathing' =>
          const _BreathingPattern('resonance_breathing', [
            _BreathingPhase(_PhaseKind.inhale, 5),
            _BreathingPhase(_PhaseKind.exhale, 5),
          ]),
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
