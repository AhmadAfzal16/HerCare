import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import 'breathing_band_panel.dart';
import 'pulse_analysis.dart';

/// Optional 30-second heart reading before or after a practice. Uses a
/// connected heart-rate band when available, otherwise a fingertip over the
/// back camera and flash. Frames are processed in memory and discarded; only
/// the summary (heart rate, HRV) is returned.
Future<PulseReading?> showPulseCheck(BuildContext context,
        {required bool isUrdu, required bool after}) =>
    Navigator.of(context).push<PulseReading>(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PulseCheckScreen(isUrdu: isUrdu, after: after)));

enum _Stage { choose, waitingForFinger, measuring, analysing, done, failed }

class PulseCheckScreen extends StatefulWidget {
  const PulseCheckScreen(
      {super.key,
      required this.isUrdu,
      required this.after,
      this.seconds = 30,
      this.findCameras = availableCameras});
  final bool isUrdu, after;
  final int seconds;

  /// Camera lookup; replaceable in tests.
  final Future<List<CameraDescription>> Function() findCameras;
  @override
  State<PulseCheckScreen> createState() => _PulseCheckScreenState();
}

class _PulseCheckScreenState extends State<PulseCheckScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  StreamSubscription<List<int>>? _band;
  final _clock = Stopwatch();
  final _samples = <PulseSample>[];
  final _intervals = <double>[];
  final _bandRates = <int>[];
  Timer? _ticker;
  _Stage _stage = _Stage.choose;
  bool _usingBand = false, _closed = false;
  int _lostFingerSince = -1;
  String? _problem;
  PulseReading? _reading;

  String _t(String en, String ur) => widget.isUrdu ? ur : en;
  // Camera: frame timestamps from a stopwatch. Band: counted in timer ticks,
  // so the reading length follows the same clock as the timer driving it.
  int _bandElapsedMs = 0;
  double get _progress =>
      (_usingBand ? _bandElapsedMs : _clock.elapsedMilliseconds) /
      (widget.seconds * 1000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // No band connected: go straight to the camera instructions.
    if (!HeartBandFeed.instance.live) _stage = _Stage.waitingForFinger;
    if (_stage == _Stage.waitingForFinger) unawaited(_startCamera());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed &&
        (_stage == _Stage.measuring || _stage == _Stage.waitingForFinger)) {
      _fail(_t('The reading was interrupted. Try again when ready.',
          'پیمائش رک گئی۔ تیار ہوں تو دوبارہ کوشش کریں۔'));
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_stop());
    super.dispose();
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _ticker = null;
    _clock.stop();
    await _band?.cancel();
    _band = null;
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      try {
        if (camera.value.isStreamingImages) await camera.stopImageStream();
        await camera.setFlashMode(FlashMode.off);
      } catch (_) {/* Already released. */}
      await camera.dispose();
    }
  }

  void _reset() {
    _samples.clear();
    _intervals.clear();
    _bandRates.clear();
    _clock
      ..stop()
      ..reset();
    _bandElapsedMs = 0;
    _lostFingerSince = -1;
    _problem = null;
    _reading = null;
  }

  Future<void> _startCamera() async {
    _reset();
    _usingBand = false;
    setState(() => _stage = _Stage.waitingForFinger);
    try {
      final back = (await widget.findCameras())
          .where((camera) => camera.lensDirection == CameraLensDirection.back)
          .firstOrNull;
      if (back == null) throw StateError('No back camera');
      final controller = CameraController(back, ResolutionPreset.low,
          enableAudio: false,
          imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
              ? ImageFormatGroup.bgra8888
              : ImageFormatGroup.yuv420);
      _camera = controller;
      await controller.initialize();
      if (_closed) return controller.dispose();
      await controller.setFlashMode(FlashMode.torch);
      await controller.startImageStream(_frame);
    } catch (_) {
      _fail(_t('The camera or flash is not available. You can skip this step.',
          'کیمرا یا فلیش دستیاب نہیں۔ آپ یہ مرحلہ چھوڑ سکتی ہیں۔'));
    }
  }

  void _startBand() {
    _reset();
    _usingBand = true;
    setState(() => _stage = _Stage.measuring);
    _band = HeartBandFeed.instance.intervals.listen((rr) {
      if (_stage == _Stage.measuring) {
        _intervals.addAll(rr.map((ms) => ms.toDouble()));
      }
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || _stage != _Stage.measuring) return;
      final feed = HeartBandFeed.instance;
      if (!feed.live) {
        _fail(_t('The band disconnected. Try the camera instead.',
            'بینڈ کا رابطہ ٹوٹ گیا۔ کیمرا آزمائیں۔'));
        return;
      }
      if (feed.bpm != null) _bandRates.add(feed.bpm!);
      _bandElapsedMs += 250;
      if (_progress >= 1) {
        _finish();
      } else {
        setState(() {});
      }
    });
  }

  /// Fingertip check and brightness from the centre of each frame.
  void _frame(CameraImage image) {
    if (_closed ||
        (_stage != _Stage.waitingForFinger && _stage != _Stage.measuring)) {
      return;
    }
    final sample = FrameSampler.sample(image);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (sample == null || !sample.fingerCovered) {
      if (_stage == _Stage.measuring) {
        if (_lostFingerSince < 0) _lostFingerSince = now;
        if (now - _lostFingerSince > 1500) {
          _reset();
          setState(() {
            _stage = _Stage.waitingForFinger;
            _problem = _t('Keep your fingertip gently on the camera and flash.',
                'انگلی کی پور کو کیمرا اور فلیش پر ہلکے سے رکھے رہیں۔');
          });
        }
      }
      return;
    }
    _lostFingerSince = -1;
    if (_stage == _Stage.waitingForFinger) {
      _clock.start();
      setState(() {
        _stage = _Stage.measuring;
        _problem = null;
      });
    }
    _samples
        .add(PulseSample(_clock.elapsedMicroseconds / 1000, sample.brightness));
    if (_progress >= 1) {
      _finish();
    } else if (_samples.length % 10 == 0) {
      setState(() {});
    }
  }

  Future<void> _finish() async {
    if (_stage != _Stage.measuring) return;
    setState(() => _stage = _Stage.analysing);
    // Release camera/band in the background; the result never waits on it
    // (a slow camera or Bluetooth shutdown must not leave her on a spinner).
    unawaited(_stop());
    final result = _usingBand
        ? (_intervals.length >= 15
            ? PulseAnalysis.fromIntervals(_intervals, source: 'band')
            : _bandRates.length >= 20
                // Band without beat intervals: heart rate only, no HRV.
                ? PulseResult.ok(PulseReading(
                    bpm:
                        (_bandRates.reduce((a, b) => a + b) / _bandRates.length)
                            .round(),
                    beats: _bandRates.length,
                    source: 'band'))
                : const PulseResult.failed(PulseFailure.tooShort))
        : PulseAnalysis.fromCamera(List.of(_samples));
    if (!mounted) return;
    if (result.ok) {
      setState(() {
        _reading = result.reading;
        _stage = _Stage.done;
      });
    } else {
      _fail(_t(
          'We could not get a clear reading. Rest your fingertip lightly (no pressing), keep still, and try again — or skip.',
          'واضح پیمائش نہیں ہو سکی۔ انگلی ہلکے سے رکھیں (دبائیں نہیں)، ساکن رہیں اور دوبارہ کوشش کریں، یا چھوڑ دیں۔'));
    }
  }

  void _fail(String message) {
    unawaited(_stop());
    if (!mounted) return;
    setState(() {
      _stage = _Stage.failed;
      _problem = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reading = _reading;
    return Directionality(
      textDirection: widget.isUrdu ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: context.hcBg,
        appBar: AppBar(
            backgroundColor: context.hcSurface,
            title: Text(widget.after
                ? _t('Heart check — after', 'دل کی پیمائش — بعد میں')
                : _t('Heart check — before', 'دل کی پیمائش — پہلے'))),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(
                _t('Optional. A 30-second reading shows how your body settles during practice. It is not a medical test.',
                    'اختیاری۔ 30 سیکنڈ کی پیمائش دکھاتی ہے کہ مشق کے دوران جسم کتنا پرسکون ہوا۔ یہ طبی ٹیسٹ نہیں۔'),
                style: AppTextStyles.bodyMedium),
            const SizedBox(height: 20),
            if (_stage == _Stage.choose) ...[
              FilledButton.icon(
                  key: const Key('pulse-use-band'),
                  onPressed: _startBand,
                  icon: const Icon(Icons.watch_outlined),
                  label: Text(
                      _t('Use my connected band', 'منسلک بینڈ استعمال کریں'))),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                  onPressed: () => unawaited(_startCamera()),
                  icon: const Icon(Icons.fingerprint),
                  label: Text(
                      _t('Use the phone camera', 'فون کا کیمرا استعمال کریں'))),
            ],
            if (_stage == _Stage.waitingForFinger ||
                (_stage == _Stage.measuring && !_usingBand)) ...[
              const Icon(Icons.fingerprint, size: 64, color: AppColors.primary),
              const SizedBox(height: 12),
              Text(
                  _t('Sit still. Rest the tip of your index finger lightly over the back camera and the flash. Don\'t press. The flash will feel slightly warm.',
                      'ساکن بیٹھیں۔ شہادت کی انگلی کی پور کو پچھلے کیمرے اور فلیش پر ہلکے سے رکھیں۔ دبائیں نہیں۔ فلیش ہلکا گرم محسوس ہو سکتا ہے۔'),
                  textAlign: TextAlign.center),
            ],
            if (_stage == _Stage.measuring) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                  value: _progress.clamp(0, 1), minHeight: 8),
              const SizedBox(height: 8),
              Text(
                  _t('Keep still… ${(widget.seconds * (1 - _progress)).ceil().clamp(0, widget.seconds)} s',
                      'ساکن رہیں… ${(widget.seconds * (1 - _progress)).ceil().clamp(0, widget.seconds)} سیکنڈ'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium),
            ],
            if (_stage == _Stage.analysing)
              const Center(child: CircularProgressIndicator()),
            if (_problem != null) ...[
              const SizedBox(height: 16),
              Text(_problem!,
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodyMedium
                      .copyWith(color: AppColors.error)),
            ],
            if (_stage == _Stage.done && reading != null) ...[
              const Icon(Icons.favorite, size: 48, color: AppColors.secondary),
              const SizedBox(height: 8),
              Text(
                  _t('${reading.bpm} beats per minute',
                      '${reading.bpm} دھڑکنیں فی منٹ'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall),
              if (reading.rmssdMs != null)
                Text(
                    _t('Heart-rate variability: ${reading.rmssdMs} ms',
                        'دل کی دھڑکن کا تغیر: ${reading.rmssdMs} ملی سیکنڈ'),
                    textAlign: TextAlign.center)
              else
                Text(
                    _t('Heart rate only — the signal was not steady enough for variability.',
                        'صرف دل کی رفتار — تغیر کے لیے سگنل کافی مستحکم نہیں تھا۔'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodySmall),
              const SizedBox(height: 6),
              Text(
                  reading.source == 'camera'
                      ? _t('Camera readings are approximate.',
                          'کیمرے کی پیمائش تخمینی ہوتی ہے۔')
                      : _t('Measured with your band.',
                          'آپ کے بینڈ سے ناپا گیا۔'),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.bodySmall
                      .copyWith(color: context.hcTextSecondary)),
              const SizedBox(height: 16),
              FilledButton(
                  key: const Key('pulse-use-reading'),
                  onPressed: () => Navigator.pop(context, reading),
                  child:
                      Text(_t('Use this reading', 'یہ پیمائش استعمال کریں'))),
            ],
            if (_stage == _Stage.failed || _stage == _Stage.done)
              TextButton(
                  onPressed: () => HeartBandFeed.instance.live
                      ? setState(() {
                          _reset();
                          _stage = _Stage.choose;
                        })
                      : unawaited(_startCamera()),
                  child: Text(_t('Try again', 'دوبارہ کوشش کریں'))),
            const SizedBox(height: 8),
            TextButton(
                key: const Key('pulse-skip'),
                onPressed: () => Navigator.pop(context),
                child: Text(_t('Skip', 'چھوڑ دیں'))),
          ]),
        ),
      ),
    );
  }
}

/// Frame summary: average brightness of the centre and whether a fingertip
/// (lit red by the flash) is covering the lens.
class FrameSample {
  const FrameSample(this.brightness, this.fingerCovered);
  final double brightness;
  final bool fingerCovered;
}

abstract final class FrameSampler {
  static FrameSample? sample(CameraImage image) {
    try {
      if (image.format.group == ImageFormatGroup.bgra8888) return _bgra(image);
      if (image.planes.length >= 3) return _yuv(image);
    } catch (_) {/* Unexpected frame layout. */}
    return null;
  }

  static ({int x0, int x1, int y0, int y1}) _centre(int width, int height) => (
        x0: width ~/ 4,
        x1: width * 3 ~/ 4,
        y0: height ~/ 4,
        y1: height * 3 ~/ 4
      );

  static FrameSample? _yuv(CameraImage image) {
    final box = _centre(image.width, image.height);
    final y = image.planes[0], v = image.planes[2];
    final vStride = v.bytesPerPixel ?? 1;
    var luma = 0.0, red = 0.0, count = 0;
    for (var row = box.y0; row < box.y1; row += 6) {
      for (var col = box.x0; col < box.x1; col += 6) {
        luma += y.bytes[row * y.bytesPerRow + col];
        red += v.bytes[(row ~/ 2) * v.bytesPerRow + (col ~/ 2) * vStride];
        count++;
      }
    }
    if (count == 0) return null;
    luma /= count;
    red /= count; // V (Cr) is high when the image is mostly red.
    return FrameSample(luma, red > 150 && luma > 15 && luma < 250);
  }

  static FrameSample? _bgra(CameraImage image) {
    final box = _centre(image.width, image.height);
    final plane = image.planes[0];
    var r = 0.0, g = 0.0, b = 0.0, count = 0;
    for (var row = box.y0; row < box.y1; row += 6) {
      for (var col = box.x0; col < box.x1; col += 6) {
        final i = row * plane.bytesPerRow + col * 4;
        b += plane.bytes[i];
        g += plane.bytes[i + 1];
        r += plane.bytes[i + 2];
        count++;
      }
    }
    if (count == 0) return null;
    r /= count;
    g /= count;
    b /= count;
    return FrameSample(r, r > 100 && r > g * 1.8 && r > b * 1.8);
  }
}
