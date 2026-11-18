import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Optional, non-blocking grounding. No microphone, timers or inferred recovery.
class CrisisGrounding extends StatefulWidget {
  const CrisisGrounding({super.key, required this.isUrdu});
  final bool isUrdu;
  @override
  State<CrisisGrounding> createState() => _CrisisGroundingState();
}

class _CrisisGroundingState extends State<CrisisGrounding>
    with SingleTickerProviderStateMixin {
  late final _animation =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  bool _started = false;

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_reducedMotion && _animation.isAnimating) _animation.stop();
  }

  bool get _reducedMotion =>
      MediaQuery.of(context).disableAnimations ||
      MediaQuery.of(context).accessibleNavigation;

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(ur
          ? 'صرف اس وقت جب آپ محفوظ ہوں یا مدد کا انتظار کر رہی ہوں۔ سانس معمول کے مطابق لیں؛ اسے روکنا ضروری نہیں۔'
          : 'Only if you are somewhere safe or waiting for help. Breathe normally; do not hold your breath.'),
      const SizedBox(height: 12),
      if (_started) ...[
        Center(
          child: AnimatedBuilder(
            animation: _animation,
            builder: (_, __) => Transform.scale(
              scale: _reducedMotion ? 1 : .85 + .15 * _animation.value,
              child: const Icon(Icons.spa_outlined,
                  size: 56, color: AppColors.primary),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(ur
            ? 'آس پاس کی ۳ چیزیں دیکھیں۔ ۲ چیزوں کا لمس محسوس کریں۔ ۱ آواز سنیں۔ کسی مددگار شخص کے ساتھ رہیں۔'
            : 'Notice 3 things you can see, 2 things you can feel and 1 sound. Stay with a supportive person.'),
        const SizedBox(height: 12),
      ],
      OutlinedButton(
        onPressed: () {
          setState(() => _started = !_started);
          if (_started && !_reducedMotion) {
            _animation.repeat(reverse: true);
          } else {
            _animation.stop();
          }
        },
        child: Text(_started
            ? (ur ? 'مشق روکیں' : 'Stop grounding')
            : (ur ? 'اختیاری سکون کی مشق' : 'Optional grounding')),
      ),
    ]);
  }
}
