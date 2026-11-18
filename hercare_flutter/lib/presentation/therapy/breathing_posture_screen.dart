import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum _Feedback { loading, framing, visible, tilted, unavailable }

class BreathingPostureScreen extends StatefulWidget {
  const BreathingPostureScreen({super.key, required this.isUrdu});

  final bool isUrdu;

  @override
  State<BreathingPostureScreen> createState() => _BreathingPostureScreenState();
}

class _BreathingPostureScreenState extends State<BreathingPostureScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  static const _posture = MethodChannel('com.hercare/posture');
  int? _session;
  late final Future<void> _opening;
  Future<void>? _analysis;
  bool _closed = false;
  final _sampling = Stopwatch()..start();
  int _nextSample = 0;
  _Feedback _feedback = _Feedback.loading;
  _Feedback? _candidate;
  int _candidateFrames = 0;

  String _text(String en, String ur) => widget.isUrdu ? ur : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _opening = _open();
  }

  Future<void> _open() async {
    try {
      final cameras = await availableCameras();
      if (_closed) return;
      final front = cameras
          .where((camera) => camera.lensDirection == CameraLensDirection.front)
          .firstOrNull;
      if (front == null) throw StateError('Front camera unavailable');
      final controller = CameraController(front, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      _camera = controller;
      await controller.initialize();
      if (_closed) return;
      _session = await _posture.invokeMethod<int>('open');
      if (_closed) return;
      if (_session == null) throw StateError('Posture check unavailable');
      await controller.startImageStream(_frame);
      if (mounted && !_closed) setState(() => _feedback = _Feedback.framing);
    } catch (_) {
      if (mounted && !_closed) {
        setState(() => _feedback = _Feedback.unavailable);
      }
      await _releaseCamera();
    }
  }

  void _frame(CameraImage frame) {
    final now = _sampling.elapsedMilliseconds;
    if (_closed ||
        _feedback == _Feedback.unavailable ||
        _analysis != null ||
        now < _nextSample) {
      return;
    }
    _nextSample = now + 350;
    _analysis = _inspect(frame).whenComplete(() => _analysis = null);
  }

  Future<void> _inspect(CameraImage frame) async {
    final camera = _camera;
    final session = _session;
    if (camera == null || session == null) return;
    final orientation = switch (camera.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    if (frame.planes.length != 1) {
      _show(_Feedback.unavailable);
      return;
    }
    try {
      final feedback = await _posture.invokeMethod<String>('inspect', {
        'session': session,
        'bytes': frame.planes.first.bytes,
        'width': frame.width,
        'height': frame.height,
        'rotation': (camera.description.sensorOrientation + orientation) % 360,
      });
      _show(switch (feedback) {
        'framing' => _Feedback.framing,
        'visible' => _Feedback.visible,
        'tilted' => _Feedback.tilted,
        _ => _Feedback.unavailable,
      });
    } catch (_) {
      _show(_Feedback.unavailable);
    }
  }

  void _show(_Feedback feedback) {
    if (!mounted || _closed) return;
    if (_candidate == feedback) {
      _candidateFrames++;
    } else {
      _candidate = feedback;
      _candidateFrames = 1;
    }
    if (_candidateFrames >= 2 && _feedback != feedback) {
      setState(() => _feedback = feedback);
    }
  }

  Future<void> _releaseCamera() async {
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      try {
        await camera.dispose();
      } on CameraException {
        // The camera may already have been released by Android.
      }
    }
  }

  Future<void> _close() async {
    await _opening;
    await _releaseCamera();
    await _analysis;
    if (_session != null) {
      try {
        await _posture.invokeMethod<void>('close', {'session': _session});
      } on PlatformException {
        // The native activity also releases its detector on teardown.
      } on MissingPluginException {
        // The native activity is already detached.
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final previewInterrupted = state == AppLifecycleState.inactive &&
        _camera?.value.isInitialized == true;
    if ((previewInterrupted ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    _closed = true;
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final feedback = switch (_feedback) {
      _Feedback.loading =>
        _text('Opening front camera…', 'سامنے کا کیمرا کھل رہا ہے…'),
      _Feedback.framing => _text(
          'Keep both shoulders in view. Try moving the phone back.',
          'دونوں کندھے سامنے رکھیں۔ فون تھوڑا پیچھے کر کے دیکھیں۔'),
      _Feedback.visible => _text('Both shoulders are visible. Sit comfortably.',
          'دونوں کندھے نظر آ رہے ہیں۔ آرام سے بیٹھیں۔'),
      _Feedback.tilted => _text(
          'Your shoulders appear tilted. Check that the phone is level and sit comfortably.',
          'کندھے جھکے ہوئے دکھائی دے رہے ہیں۔ فون سیدھا رکھیں اور آرام سے بیٹھیں۔'),
      _Feedback.unavailable => _text(
          'Posture check unavailable. You can still do the guided exercise.',
          'جسمانی حالت کی جانچ دستیاب نہیں۔ آپ رہنمائی کے ساتھ مشق کر سکتی ہیں۔'),
    };
    return Scaffold(
      appBar: AppBar(
          title: Text(_text('Check my posture', 'بیٹھنے کا انداز دیکھیں'))),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(_text(
              'Prop up your phone so both shoulders are visible. The camera closes when you leave this check.',
              'فون ٹکا دیں تاکہ دونوں کندھے نظر آئیں۔ اس صفحے سے نکلنے پر کیمرا بند ہو جائے گا۔')),
          if (camera != null &&
              camera.value.isInitialized &&
              _feedback != _Feedback.unavailable) ...[
            const SizedBox(height: 12),
            Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320, maxHeight: 340),
              child: CameraPreview(camera),
            )),
          ],
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(feedback)),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_text('Done', 'ہو گیا'))),
        ]),
      ),
    );
  }
}
