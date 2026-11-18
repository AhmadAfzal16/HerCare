import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import '../../providers/therapy_provider.dart';
import 'therapy_completion_sheet.dart';
import 'breathing_posture_screen.dart';
import 'meditation_audio.dart';
import 'meditation_guides.dart';

class MeditationScreen extends StatefulWidget {
  const MeditationScreen(
      {super.key, required this.activityId, this.audio, this.activeClock});
  final String activityId;
  final MeditationAudio? audio;
  final Stopwatch? activeClock;
  @override
  State<MeditationScreen> createState() => _MeditationScreenState();
}

class _MeditationScreenState extends State<MeditationScreen>
    with WidgetsBindingObserver {
  int _minutes = 5;
  int _elapsed = 0;
  int _setupStep = 0;
  bool _ready = false;
  bool _running = false;
  bool _saved = false;
  bool _completionOpen = false;
  late final Stopwatch _activeClock;
  late final MeditationAudio _audio;
  Map<String, List<MeditationCue>>? _guides;
  bool _guidesFailed = false;
  bool _audioEnabled = true;
  bool? _lastUrdu;
  int _lastCue = -1;
  String? _owner;
  String get _activityId => const {
        'body_scan',
        'muscle_relaxation',
        'mindfulness'
      }.contains(widget.activityId)
          ? widget.activityId
          : 'mindfulness';
  Timer? _timer;

  int get _total => _minutes * 60;
  int get _remaining => (_total - _elapsed).clamp(0, _total);

  @override
  void initState() {
    super.initState();
    _activeClock = widget.activeClock ?? Stopwatch();
    _owner = context.read<TherapyProvider?>()?.accountId;
    _audio = widget.audio ?? BundledTherapyAudio();
    _guides = MeditationGuides.loaded;
    _audio.addListener(_audioChanged);
    _audio.onInterruption = _pause;
    WidgetsBinding.instance.addObserver(this);
    MeditationGuides.load().then((guides) {
      if (mounted) setState(() => _guides = guides);
    }).catchError((Object _) {
      if (mounted) setState(() => _guidesFailed = true);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _pause();
  }

  bool get _ownerCurrent =>
      context.read<TherapyProvider?>()?.accountId == _owner;

  void _audioChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!TickerMode.valuesOf(context).enabled) _pause();
    final urdu = context.watch<LanguageProvider>().isUrdu;
    if (_lastUrdu != null && _lastUrdu != urdu) {
      _audio.stop();
      _lastCue = -1;
      if (_running) _speakCue(urdu);
    }
    _lastUrdu = urdu;
  }

  int get _cueIndex => ((_elapsed / _total) * 4).floor().clamp(0, 3);

  void _speakCue(bool isUrdu) {
    if (!_audioEnabled || _guides == null || !_running || _remaining == 0) {
      return;
    }
    if (_lastCue == _cueIndex) return;
    _lastCue = _cueIndex;
    _audio.cue(_guides![_activityId]![_cueIndex].audio(isUrdu));
  }

  void _setAudio(bool enabled) {
    setState(() => _audioEnabled = enabled);
    _audio.stop();
    _lastCue = -1;
    if (enabled && _running) _speakCue(_lastUrdu ?? false);
  }

  void _selectMinutes(int value) {
    if (_ready) return;
    setState(() {
      _minutes = value;
    });
  }

  void _toggle() {
    if (_running) {
      _pause();
      return;
    }
    if (!_ready || _saved || _remaining == 0 || !_ownerCurrent) return;
    _activeClock.start();
    setState(() => _running = true);
    if (_audioEnabled && _lastCue == _cueIndex) {
      _audio.resume();
    } else {
      _speakCue(_lastUrdu ?? false);
    }
    _timer ??=
        Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void _tick() {
    if (!mounted || !_running) return;
    if (!_ownerCurrent || ModalRoute.of(context)?.isCurrent == false) {
      _pause();
      return;
    }
    final seconds = _activeClock.elapsed.inSeconds.clamp(0, _total);
    if (seconds == _elapsed) return;
    setState(() => _elapsed = seconds);
    _speakCue(_lastUrdu ?? false);
    if (seconds >= _total) {
      _pause();
      HapticFeedback.mediumImpact();
      _finish();
    }
  }

  void _pause() {
    _activeClock.stop();
    _audio.pause();
    _timer?.cancel();
    _timer = null;
    if (mounted && _running) setState(() => _running = false);
  }

  String _guidance(bool urdu) {
    if (_guides == null) {
      return urdu
          ? 'آرام سے بیٹھیں اور سانس کو قدرتی رہنے دیں۔'
          : 'Sit comfortably and let your breathing stay natural.';
    }
    return _guides![_activityId]![_cueIndex].text(urdu);
  }

  Future<void> _finish() async {
    if (_completionOpen || _saved || _remaining != 0) return;
    _completionOpen = true;
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    final practiced = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        scrollable: true,
        title: Text(isUrdu ? 'کیا آپ نے مشق کی؟' : 'Did you practise?'),
        content: Text(isUrdu
            ? 'ٹائمر مکمل ہوا ہے، لیکن فون مراقبے یا نشست کی تصدیق نہیں کر سکتا۔ صرف اسی صورت میں مکمل محفوظ کریں جب آپ نے واقعی مشق کی ہو۔'
            : 'The timer finished, but your phone cannot verify meditation or posture. Save as complete only if you actually practised.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(isUrdu ? 'ابھی نہیں' : 'Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(isUrdu ? 'ہاں، میں نے مشق کی' : 'Yes, I practised'),
          ),
        ],
      ),
    );
    if (!mounted || !_ownerCurrent) return;
    if (practiced == true) {
      final session = await showTherapyCompletionSheet(
        context,
        type: 'meditation',
        activityId: _activityId,
        durationSeconds: _elapsed.clamp(1, 7200),
        isUrdu: isUrdu,
      );
      if (mounted && session != null) setState(() => _saved = true);
    }
    _completionOpen = false;
  }

  Future<void> _endEarly() async {
    if (_completionOpen || _saved || _elapsed < 1 || !_ownerCurrent) return;
    _pause();
    _completionOpen = true;
    final session = await showTherapyCompletionSheet(
      context,
      type: 'meditation',
      activityId: _activityId,
      durationSeconds: _elapsed.clamp(1, 7200),
      isUrdu: context.read<LanguageProvider>().isUrdu,
      completed: false,
    );
    if (!mounted || !_ownerCurrent) return;
    setState(() {
      if (session != null) _saved = true;
      _completionOpen = false;
    });
  }

  void _tryAgain() {
    _pause();
    _activeClock.reset();
    _audio.stop();
    _lastCue = -1;
    setState(() {
      _elapsed = 0;
      _setupStep = 0;
      _ready = false;
      _saved = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _activeClock.stop();
    _timer?.cancel();
    _audio.removeListener(_audioChanged);
    _audio.onInterruption = null;
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final activity = TherapyCatalog.byId(_activityId);
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
        child: _ready ? _buildPractice(isUrdu) : _buildPoseSetup(isUrdu),
      )),
    );
  }

  Widget _audioControls(bool urdu) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(urdu ? 'آواز میں رہنمائی' : 'Spoken guidance'),
            subtitle: Text(urdu
                ? 'اردو اور انگریزی آواز آف لائن بھی دستیاب ہے۔'
                : 'Urdu and English audio are included for offline use.'),
            value: _audioEnabled,
            onChanged: _setAudio,
          ),
          Text(
              urdu
                  ? 'مصنوعی آواز۔ ہر مرحلے کی رہنمائی کے بعد خاموش مشق کا وقت ہے۔'
                  : 'Synthetic voice. Each spoken step is followed by quiet practice time.',
              style: AppTextStyles.bodySmall),
          if (_audio.unavailable)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(urdu
                  ? 'آواز نہیں چل سکی۔ تحریری رہنمائی سے جاری رکھیں یا آواز بند کر کے دوبارہ چلائیں۔'
                  : 'Audio could not play. Continue with text, or switch audio off and on to retry.'),
            ),
          const SizedBox(height: 12),
        ],
      );

  Widget _buildPoseSetup(bool isUrdu) {
    final step = _poseSteps[_setupStep];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.asset(
            'assets/images/meditation_seated_posture.jpg',
            height: 300,
            fit: BoxFit.contain,
            semanticLabel: isUrdu
                ? 'کرسی پر آرام سے بیٹھی عورت، پاؤں فرش پر اور ہاتھ رانوں پر'
                : 'Woman seated comfortably on a chair with feet on the floor and hands on thighs',
          ),
        ),
        const SizedBox(height: 18),
        Text(
          isUrdu
              ? 'آرام دہ نشست ${_setupStep + 1} / ${_poseSteps.length}'
              : 'Comfortable posture ${_setupStep + 1} of ${_poseSteps.length}',
          style: AppTextStyles.labelLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(isUrdu ? step.$2 : step.$1,
            style: AppTextStyles.titleMedium, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(isUrdu ? step.$4 : step.$3,
            style: AppTextStyles.bodyMedium, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Text(
          isUrdu
              ? 'کیا یہ حالت آپ کے لیے آرام دہ ہے؟ اپنے آرام کے مطابق بیٹھیں۔'
              : 'Does this position feel comfortable? Adjust it to suit you.',
          style: AppTextStyles.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        if (_setupStep == 0 &&
            !kIsWeb &&
            defaultTargetPlatform == TargetPlatform.android)
          TextButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(
                  builder: (_) => BreathingPostureScreen(isUrdu: isUrdu)),
            ),
            icon: const Icon(Icons.camera_front_outlined),
            label: Text(isUrdu ? 'بیٹھنے کا انداز دیکھیں' : 'Check my posture'),
          ),
        if (_setupStep == 0)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [3, 5, 10, 15]
                .map((value) => ChoiceChip(
                      label: Text('$value ${isUrdu ? 'منٹ' : 'min'}'),
                      selected: _minutes == value,
                      onSelected: (_) => _selectMinutes(value),
                    ))
                .toList(),
          ),
        const SizedBox(height: 20),
        _audioControls(isUrdu),
        if (_guidesFailed)
          Text(isUrdu
              ? 'رہنمائی دستیاب نہیں۔ براہ کرم مشق دوبارہ کھولیں۔'
              : 'Guidance is unavailable. Please reopen this activity.'),
        FilledButton(
          onPressed: _guides == null
              ? null
              : () => setState(() {
                    if (_setupStep < _poseSteps.length - 1) {
                      _setupStep += 1;
                    } else {
                      _ready = true;
                    }
                  }),
          child: Text(_setupStep == _poseSteps.length - 1
              ? (isUrdu ? 'ہاں، شروع کریں' : 'Yes, begin')
              : (isUrdu ? 'ہاں، اگلا مرحلہ' : 'Yes, next step')),
        ),
        if (_setupStep > 0)
          TextButton(
            onPressed: () => setState(() => _setupStep -= 1),
            child: Text(isUrdu ? 'پچھلا مرحلہ' : 'Previous step'),
          ),
        const SizedBox(height: 10),
        Text(
          isUrdu
              ? 'کسی خاص یوگا پوز کی ضرورت نہیں۔ درد، چکر یا بے آرامی ہو تو رک جائیں یا نشست بدل لیں۔'
              : 'No special yoga pose is needed. Stop or adjust if you feel pain, dizzy, or uncomfortable.',
          style:
              AppTextStyles.bodySmall.copyWith(color: context.hcTextSecondary),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildPractice(bool isUrdu) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          isUrdu
              ? 'آرام سے بیٹھیں اور سانس کو قدرتی رہنے دیں'
              : 'Sit comfortably and let your breathing stay natural',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodyMedium,
        ),
        const SizedBox(height: 20),
        _audioControls(isUrdu),
        Center(
          child: SizedBox.square(
            dimension: 170,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: _total == 0 ? 0 : _elapsed / _total,
                  strokeWidth: 12,
                  backgroundColor: AppColors.primaryContainer,
                  color: AppColors.primary,
                ),
              ),
              Text(
                '${(_remaining ~/ 60).toString().padLeft(2, '0')}:${(_remaining % 60).toString().padLeft(2, '0')}',
                style: AppTextStyles.titleLarge,
              ),
            ]),
          ),
        ),
        const SizedBox(height: 24),
        AnimatedSwitcher(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 350),
          child: Container(
            key: ValueKey(_guidance(isUrdu)),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.hcSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.hcOutline),
            ),
            child: Text(_guidance(isUrdu),
                textAlign: TextAlign.center, style: AppTextStyles.bodyLarge),
          ),
        ),
        const SizedBox(height: 22),
        if (_saved)
          Text(isUrdu ? 'مشق محفوظ ہو گئی' : 'Session saved',
              textAlign: TextAlign.center, style: AppTextStyles.titleMedium)
        else if (_remaining == 0)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: _completionOpen ? null : _finish,
                child: Text(isUrdu
                    ? 'مشق کی تصدیق اور محفوظ کریں'
                    : 'Confirm practice and save'),
              ),
              TextButton(
                onPressed: _completionOpen ? null : _tryAgain,
                child: Text(isUrdu ? 'دوبارہ کوشش کریں' : 'Try again'),
              ),
            ],
          )
        else
          FilledButton.icon(
            onPressed: _toggle,
            icon:
                Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded),
            label: Text(_running
                ? (isUrdu ? 'وقفہ' : 'Pause')
                : (isUrdu ? 'شروع / جاری' : 'Start / Resume')),
          ),
        if (_elapsed > 0 && _remaining > 0 && !_saved)
          TextButton(
            onPressed: _endEarly,
            child: Text(isUrdu ? 'ابھی ختم کریں' : 'End early'),
          ),
        const SizedBox(height: 14),
        Text(
          isUrdu
              ? 'صرف ایپ کے سامنے فعال وقت گنا جاتا ہے؛ ایپ پس منظر میں جائے تو مشق رک جاتی ہے۔'
              : 'Only active foreground time counts; the session pauses when the app leaves the screen.',
          textAlign: TextAlign.center,
          style:
              AppTextStyles.bodySmall.copyWith(color: context.hcTextSecondary),
        ),
      ],
    );
  }
}

const _poseSteps = <(String, String, String, String)>[
  (
    'Find a steady seat',
    'مضبوط اور آرام دہ نشست چنیں',
    'Use a chair or another supported position. Let both feet rest on the floor if that is comfortable.',
    'کرسی یا کسی سہارے والی نشست پر بیٹھیں۔ اگر آرام دہ ہو تو دونوں پاؤں فرش پر رکھیں۔',
  ),
  (
    'Soften your shoulders',
    'کندھوں کو ڈھیلا چھوڑیں',
    'Sit upright without forcing your back straight. Rest your hands on your thighs or in your lap.',
    'کمر کو زبردستی سیدھا نہ کریں۔ ہاتھ رانوں یا گود میں آرام سے رکھیں۔',
  ),
  (
    'Choose a gentle gaze',
    'نگاہ نرم رکھیں',
    'Lower your gaze or close your eyes only if it feels safe. Breathe normally; do not hold or force your breath.',
    'اگر محفوظ اور آرام دہ لگے تو نگاہ نیچی کریں یا آنکھیں بند کریں۔ سانس نہ روکیں اور نہ زور دیں۔',
  ),
];
