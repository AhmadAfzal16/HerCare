import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import 'activity_clock.dart';
import 'therapy_completion_sheet.dart';

class TherapyGameScreen extends StatefulWidget {
  const TherapyGameScreen({super.key, required this.gameId});
  final String gameId;
  @override
  State<TherapyGameScreen> createState() => _TherapyGameScreenState();
}

class _TherapyGameScreenState extends State<TherapyGameScreen>
    with WidgetsBindingObserver {
  final _clock = ActiveTherapyClock();
  final _random = Random();
  late final List<String> _cards;
  final Set<int> _matched = {};
  final List<int> _open = [];
  Timer? _matchTimer;
  Timer? _paceTimer;
  bool _checking = false;
  int _score = 0;
  int _targetColor = 0;
  int _nextBubbleAt = 0;
  bool _completed = false;
  bool _saving = false;
  bool _saved = false;
  bool _foreground = true;
  bool _routeActive = true;
  bool _puzzleWrong = false;

  static const _symbols = ['🌸', '🌙', '🍃', '💜'];
  static const _symbolNames = [
    ('Flower', 'پھول'),
    ('Moon', 'چاند'),
    ('Leaf', 'پتا'),
    ('Heart', 'دل')
  ];
  static const _colors = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.accent,
    AppColors.success
  ];
  static const _colorNames = [
    ('Purple', 'جامنی'),
    ('Pink', 'گلابی'),
    ('Blue', 'نیلا'),
    ('Green', 'سبز')
  ];
  static const _household = [
    (
      'A book',
      'کتاب',
      'Bookshelf',
      'کتابوں کی الماری',
      Icons.menu_book_rounded
    ),
    (
      'A clean cup',
      'صاف کپ',
      'Kitchen shelf',
      'باورچی خانے کا شیلف',
      Icons.local_cafe_outlined
    ),
    (
      'A folded towel',
      'تہہ کیا تولیہ',
      'Linen basket',
      'کپڑوں کی ٹوکری',
      Icons.dry_cleaning_outlined
    ),
  ];

  bool get _canPlay => !_completed && !_saving && _foreground && _routeActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cards = [..._symbols, ..._symbols]..shuffle(_random);
    _targetColor = _random.nextInt(_colors.length);
    _clock.resume();
    if (widget.gameId == 'breathing_bubbles') {
      _paceTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted && _canPlay) setState(() {});
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeActive = TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (_foreground && _routeActive && !_saving && !_completed) {
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
      _matchTimer?.cancel();
      _open.clear();
      _checking = false;
    } else if (!_saving && !_completed && _routeActive) {
      _clock.resume();
    }
    if (mounted) setState(() {});
  }

  void _flip(int index) {
    if (!_canPlay ||
        _checking ||
        _matched.contains(index) ||
        _open.contains(index)) {
      return;
    }
    setState(() => _open.add(index));
    if (_open.length < 2) return;
    final first = _open[0];
    final second = _open[1];
    if (_cards[first] == _cards[second]) {
      setState(() {
        _matched.addAll([first, second]);
        _open.clear();
      });
      if (_matched.length == _cards.length) unawaited(_finishGame());
    } else {
      _checking = true;
      _matchTimer = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        setState(() {
          _open.clear();
          _checking = false;
        });
      });
    }
  }

  void _tapBubble() {
    if (!_canPlay || _clock.elapsed.inMilliseconds < _nextBubbleAt) return;
    setState(() {
      _score += 1;
      _nextBubbleAt = _clock.elapsed.inMilliseconds + 4000;
    });
    if (_score >= 10) unawaited(_finishGame());
  }

  void _tapColor(int index) {
    if (!_canPlay) return;
    if (index == _targetColor) {
      setState(() {
        _score += 1;
        _targetColor =
            (_targetColor + 1 + _random.nextInt(_colors.length - 1)) %
                _colors.length;
      });
      if (_score >= 8) unawaited(_finishGame());
    }
  }

  void _placeItem(int place) {
    if (!_canPlay) return;
    if (place != _score) {
      setState(() => _puzzleWrong = true);
      return;
    }
    setState(() {
      _score += 1;
      _puzzleWrong = false;
    });
    if (_score == _household.length) unawaited(_finishGame());
  }

  Future<void> _finishGame({bool completed = true}) async {
    if (_saving || _saved) return;
    _clock.pause();
    _matchTimer?.cancel();
    setState(() {
      _saving = true;
      if (completed) _completed = true;
    });
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    final session = await showTherapyCompletionSheet(
      context,
      type: 'game',
      activityId: widget.gameId,
      durationSeconds: _clock.recordedSeconds,
      completed: completed,
      isUrdu: isUrdu,
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _saved = session != null;
      _open.clear();
      _checking = false;
    });
    if (session != null && !completed) {
      Navigator.pop(context);
    } else if (!_completed && _foreground && _routeActive) {
      _clock.resume();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock.pause();
    _matchTimer?.cancel();
    _paceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final activity = TherapyCatalog.byId(widget.gameId);
    final instruction = switch (widget.gameId) {
      'memory_match' =>
        isUrdu ? 'ایک جیسے چار جوڑے تلاش کریں' : 'Find the four matching pairs',
      'breathing_bubbles' => isUrdu
          ? 'آرام سے سانس لیں، پھر سانس چھوڑتے ہوئے ایک بلبلہ چھوئیں۔ سانس نہ روکیں۔'
          : 'Breathe comfortably, then tap a bubble with your exhale. Do not hold your breath.',
      'domestic_puzzle' => isUrdu
          ? 'ہر چیز کے لیے مناسب جگہ چنیں۔ کوئی وقت کی پابندی نہیں۔'
          : 'Choose a home for each item. There is no time limit.',
      _ => isUrdu
          ? 'دکھایا گیا رنگ یا اس کا نام منتخب کریں'
          : 'Choose the color shown above, or match its name',
    };
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
          backgroundColor: context.hcSurface,
          surfaceTintColor: Colors.transparent,
          title: Text(isUrdu ? activity.titleUr : activity.title,
              style: AppTextStyles.titleMedium)),
      body: SafeArea(
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(children: [
          Text(instruction,
              textAlign: TextAlign.center, style: AppTextStyles.bodyMedium),
          const SizedBox(height: 22),
          if (widget.gameId == 'memory_match')
            _memoryGrid(isUrdu)
          else if (widget.gameId == 'breathing_bubbles')
            _bubbleGame(isUrdu)
          else if (widget.gameId == 'domestic_puzzle')
            _domesticPuzzle(isUrdu)
          else
            _colorGame(isUrdu),
          const SizedBox(height: 24),
          if (_completed) ...[
            Text(isUrdu ? 'آپ نے کھیل مکمل کر لیا۔' : 'You completed the game.',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.success)),
            const SizedBox(height: 10),
            if (!_saved)
              ElevatedButton(
                onPressed: _saving ? null : () => _finishGame(),
                child: Text(
                    isUrdu ? 'مکمل کھیل محفوظ کریں' : 'Save completed game'),
              )
            else
              Text(isUrdu ? 'سیشن محفوظ ہو گیا' : 'Session saved'),
          ] else
            TextButton(
              onPressed: _saving ? null : () => _finishGame(completed: false),
              child: Text(isUrdu ? 'پہلے روکیں' : 'Stop early'),
            ),
          const SizedBox(height: 12),
          Text(
            isUrdu
                ? 'یہ ہلکا کھیل خود مدد کے لیے ہے؛ موڈ بہتر ہونے کی ضمانت نہیں۔'
                : 'This light self-care game does not guarantee a mood improvement.',
            textAlign: TextAlign.center,
            style: AppTextStyles.bodySmall
                .copyWith(color: context.hcTextSecondary),
          ),
        ]),
      )),
    );
  }

  Widget _memoryGrid(bool isUrdu) =>
      LayoutBuilder(builder: (context, constraints) {
        final width = min(constraints.maxWidth, 360.0);
        final reduced = MediaQuery.disableAnimationsOf(context);
        return Center(
            child: SizedBox(
          width: width,
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _cards.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, crossAxisSpacing: 8, mainAxisSpacing: 8),
            itemBuilder: (context, index) {
              final visible = _open.contains(index) || _matched.contains(index);
              final symbolIndex = _symbols.indexOf(_cards[index]);
              final name = isUrdu
                  ? _symbolNames[symbolIndex].$2
                  : _symbolNames[symbolIndex].$1;
              final cardNumber = index + 1;
              final label = visible
                  ? name
                  : (isUrdu
                      ? 'چھپا کارڈ $cardNumber'
                      : 'Hidden card $cardNumber');
              return Semantics(
                button: true,
                enabled: _canPlay && !_matched.contains(index),
                label: label,
                child: ExcludeSemantics(
                  child: InkWell(
                    key: ValueKey('memory-$index'),
                    onTap: _canPlay ? () => _flip(index) : null,
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: reduced
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                          color: visible
                              ? AppColors.primaryContainer
                              : AppColors.primary,
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: Text(visible ? _cards[index] : '•',
                              textScaler: TextScaler.noScaling,
                              style: const TextStyle(
                                  fontSize: 28, color: Colors.white))),
                    ),
                  ),
                ),
              );
            },
          ),
        ));
      });

  Widget _bubbleGame(bool isUrdu) {
    final remaining = ((_nextBubbleAt - _clock.elapsed.inMilliseconds) / 1000)
        .ceil()
        .clamp(0, 4);
    final ready = remaining == 0 && _canPlay;
    return Column(children: [
      Text('$_score / 10',
          style: AppTextStyles.headlineSmall.copyWith(color: AppColors.accent)),
      const SizedBox(height: 16),
      SizedBox(
        width: 110,
        height: 110,
        child: Semantics(
          button: true,
          label: isUrdu ? 'سانس کا بلبلہ' : 'Breathing bubble',
          child: IconButton.filledTonal(
            key: const Key('breathing-bubble'),
            onPressed: ready ? _tapBubble : null,
            iconSize: 50,
            icon: const Icon(Icons.air_rounded),
          ),
        ),
      ),
      const SizedBox(height: 14),
      Text(
        remaining > 0
            ? (isUrdu
                ? 'آرام سے سانس لیں: $remaining'
                : 'Breathe comfortably: $remaining')
            : (isUrdu ? 'سانس چھوڑتے ہوئے چھوئیں' : 'Tap with your exhale'),
        textAlign: TextAlign.center,
        style: AppTextStyles.bodyMedium,
      ),
      const SizedBox(height: 8),
      Text(
        isUrdu
            ? 'ایپ آپ کی سانس کی تصدیق نہیں کر سکتی۔ اپنی آرام دہ رفتار رکھیں۔'
            : 'The app cannot verify your breathing. Keep a comfortable pace.',
        textAlign: TextAlign.center,
        style: AppTextStyles.bodySmall,
      ),
    ]);
  }

  Widget _colorGame(bool isUrdu) {
    final target =
        isUrdu ? _colorNames[_targetColor].$2 : _colorNames[_targetColor].$1;
    return Column(children: [
      Text('$_score / 8', style: AppTextStyles.titleMedium),
      const SizedBox(height: 18),
      Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          color: _colors[_targetColor],
          borderRadius: BorderRadius.circular(26),
        ),
      ),
      const SizedBox(height: 8),
      Text(target,
          key: const Key('color-target'),
          textAlign: TextAlign.center,
          style: AppTextStyles.titleMedium),
      const SizedBox(height: 20),
      ...List.generate(_colors.length, (index) {
        final name = isUrdu ? _colorNames[index].$2 : _colorNames[index].$1;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              key: ValueKey('color-$index'),
              onPressed: _canPlay ? () => _tapColor(index) : null,
              icon: Icon(Icons.circle, color: _colors[index]),
              label: Text(name),
            ),
          ),
        );
      }),
    ]);
  }

  Widget _domesticPuzzle(bool isUrdu) {
    if (_completed) {
      return const Icon(Icons.home_outlined,
          size: 72, color: AppColors.success);
    }
    final item = _household[_score];
    final itemName = isUrdu ? item.$2 : item.$1;
    final progress = _score + 1;
    return Column(children: [
      Text('$progress / 3', style: AppTextStyles.labelLarge),
      const SizedBox(height: 14),
      Icon(item.$5, size: 58, color: AppColors.primary),
      const SizedBox(height: 10),
      Text(itemName,
          textAlign: TextAlign.center, style: AppTextStyles.titleLarge),
      const SizedBox(height: 18),
      ...List.generate(_household.length, (index) {
        final place = isUrdu ? _household[index].$4 : _household[index].$3;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: ValueKey('household-$index'),
              onPressed: _canPlay ? () => _placeItem(index) : null,
              child: Text(place),
            ),
          ),
        );
      }),
      if (_puzzleWrong)
        Text(
          isUrdu
              ? 'کوئی بات نہیں، دوسری جگہ آزمائیں۔'
              : 'No problem—try another place.',
          textAlign: TextAlign.center,
          style: AppTextStyles.bodySmall,
        ),
    ]);
  }
}
