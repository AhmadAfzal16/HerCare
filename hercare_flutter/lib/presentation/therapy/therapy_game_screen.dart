import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import 'therapy_completion_sheet.dart';

class TherapyGameScreen extends StatefulWidget {
  const TherapyGameScreen({super.key, required this.gameId});
  final String gameId;
  @override
  State<TherapyGameScreen> createState() => _TherapyGameScreenState();
}

class _TherapyGameScreenState extends State<TherapyGameScreen> {
  final _startedAt = DateTime.now();
  late List<String> _cards;
  final Set<int> _matched = {};
  final List<int> _open = [];
  bool _checking = false;
  int _score = 0;
  int _targetColor = 0;
  bool _completed = false;

  static const _symbols = ['🌸', '🌙', '🍃', '💜'];
  static const _colors = [
    AppColors.primary,
    AppColors.secondary,
    AppColors.accent,
    AppColors.success
  ];

  @override
  void initState() {
    super.initState();
    _cards = [..._symbols, ..._symbols]..shuffle(Random.secure());
    _targetColor = Random.secure().nextInt(_colors.length);
  }

  Future<void> _flip(int index) async {
    if (_checking || _matched.contains(index) || _open.contains(index)) return;
    setState(() => _open.add(index));
    if (_open.length < 2) return;
    _checking = true;
    final first = _open[0];
    final second = _open[1];
    if (_cards[first] == _cards[second]) {
      setState(() {
        _matched.addAll([first, second]);
        _open.clear();
        _checking = false;
      });
      if (_matched.length == _cards.length) await _finishGame();
    } else {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (mounted) {
        setState(() {
          _open.clear();
          _checking = false;
        });
      }
    }
  }

  void _tapBubble() {
    if (_completed) return;
    setState(() => _score += 1);
    if (_score >= 10) _finishGame();
  }

  void _tapColor(int index) {
    if (_completed) return;
    if (index == _targetColor) {
      setState(() {
        _score += 1;
        _targetColor = Random.secure().nextInt(_colors.length);
      });
      if (_score >= 8) _finishGame();
    } else {
      setState(() => _score = max(0, _score - 1));
    }
  }

  Future<void> _finishGame() async {
    if (_completed) return;
    setState(() => _completed = true);
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    await showTherapyCompletionSheet(
      context,
      type: 'game',
      activityId: widget.gameId,
      durationSeconds:
          DateTime.now().difference(_startedAt).inSeconds.clamp(1, 7200),
      isUrdu: isUrdu,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final activity = TherapyCatalog.byId(widget.gameId);
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
          Text(
            widget.gameId == 'memory_match'
                ? (isUrdu
                    ? 'ایک جیسے چار جوڑے تلاش کریں'
                    : 'Find the four matching pairs')
                : widget.gameId == 'breathing_bubbles'
                    ? (isUrdu
                        ? 'آہستہ سانس چھوڑیں اور ایک بلبلہ چھوئیں'
                        : 'Exhale slowly, then tap one bubble')
                    : (isUrdu
                        ? 'اوپر دکھایا گیا رنگ منتخب کریں'
                        : 'Choose the color shown above'),
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium,
          ),
          const SizedBox(height: 22),
          if (widget.gameId == 'memory_match')
            _memoryGrid()
          else if (widget.gameId == 'breathing_bubbles')
            _bubbleGame(isUrdu)
          else
            _colorGame(isUrdu),
          const SizedBox(height: 24),
          if (_completed)
            Text(
                isUrdu
                    ? 'بہت خوب! آپ نے مکمل کر لیا۔'
                    : 'Well done—you completed it.',
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium
                    .copyWith(color: AppColors.success)),
          const SizedBox(height: 12),
          TextButton(
              onPressed: _completed ? null : _finishGame,
              child: Text(isUrdu ? 'ابھی ختم کریں' : 'Finish now')),
        ]),
      )),
    );
  }

  Widget _memoryGrid() => LayoutBuilder(builder: (context, constraints) {
        final width = min(constraints.maxWidth, 360.0);
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
              return Semantics(
                  button: true,
                  label: visible ? _cards[index] : 'Hidden card',
                  child: InkWell(
                    onTap: () => _flip(index),
                    borderRadius: BorderRadius.circular(14),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      decoration: BoxDecoration(
                          color: visible
                              ? AppColors.primaryContainer
                              : AppColors.primary,
                          borderRadius: BorderRadius.circular(14)),
                      child: Center(
                          child: Text(visible ? _cards[index] : '•',
                              style: TextStyle(
                                  fontSize: visible ? 28 : 30,
                                  color: Colors.white))),
                    ),
                  ));
            },
          ),
        ));
      });

  Widget _bubbleGame(bool isUrdu) => Column(children: [
        Text('$_score / 10',
            style:
                AppTextStyles.headlineSmall.copyWith(color: AppColors.accent)),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 14,
          runSpacing: 14,
          children: List.generate(
              6,
              (index) => InkWell(
                    onTap: _tapBubble,
                    customBorder: const CircleBorder(),
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: [
                          AppColors.primaryLight,
                          AppColors.secondaryLight,
                          AppColors.accent
                        ][index % 3]
                            .withValues(alpha: .55),
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.air_rounded, color: Colors.white),
                    ),
                  )),
        ),
      ]);

  Widget _colorGame(bool isUrdu) => Column(children: [
        Text('${isUrdu ? 'اسکور' : 'Score'}: $_score / 8',
            style: AppTextStyles.titleMedium),
        const SizedBox(height: 18),
        AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            width: 120,
            height: 120,
            decoration: BoxDecoration(
                color: _colors[_targetColor],
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                      color: _colors[_targetColor].withValues(alpha: .25),
                      blurRadius: 22)
                ])),
        const SizedBox(height: 24),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 12,
          children: List.generate(
              _colors.length,
              (index) => Semantics(
                    button: true,
                    label: 'Color ${index + 1}',
                    child: InkWell(
                        onTap: () => _tapColor(index),
                        customBorder: const CircleBorder(),
                        child: Container(
                            width: 58,
                            height: 58,
                            decoration: BoxDecoration(
                                color: _colors[index],
                                shape: BoxShape.circle))),
                  )),
        ),
      ]);
}
