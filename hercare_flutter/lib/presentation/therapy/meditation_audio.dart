import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'meditation_focus_gate.dart';

/// Injected in tests; production only plays the bundled public allow-listed cues.
abstract class MeditationAudio extends ChangeNotifier {
  bool get unavailable;
  VoidCallback? onInterruption;
  void cue(String asset);
  void pause();
  void resume();
  void stop();
}

class BundledTherapyAudio extends MeditationAudio {
  AudioPlayer? _player;
  AudioSession? _session;
  Future<void>? _initializing;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _noisy;
  Future<void> _tail = Future.value();
  int _generation = 0;
  bool _disposed = false;
  bool _wanted = false;
  bool _unavailable = false;
  String? _asset;
  String? _loadedAsset;

  @override
  bool get unavailable => _unavailable;

  Future<void> _initialize() => _initializing ??= (() async {
        final session = await AudioSession.instance;
        if (_disposed) return;
        await session.configure(const AudioSessionConfiguration.speech());
        if (_disposed) return;
        _session = session;
        _player ??= AudioPlayer(
            handleInterruptions: false, handleAudioSessionActivation: false);
        _interruptions = session.interruptionEventStream.listen((event) {
          if (event.begin && _wanted) {
            pause();
            onInterruption?.call();
          }
          // Never auto-resume after a call or another app takes audio focus.
        });
        _noisy = session.becomingNoisyEventStream.listen((_) {
          if (_wanted) {
            pause();
            onInterruption?.call();
          }
        });
      })();

  void _fail(int generation) {
    if (_disposed || generation != _generation) return;
    _unavailable = true;
    _wanted = false;
    unawaited(_player?.pause().catchError((Object _) {}));
    unawaited(_releaseFocus().catchError((Object _) {}));
    if (_session == null) _initializing = null;
    notifyListeners();
  }

  void _schedule(Future<void> Function(int generation) action) {
    final generation = ++_generation;
    _tail = _tail.then((_) async {
      if (_disposed || generation != _generation) return;
      try {
        await action(generation);
      } catch (_) {
        _fail(
            generation); // captions/timing still work; no false playback claim
      }
    });
  }

  bool _current(int generation) =>
      !_disposed && generation == _generation && _wanted;

  Future<void> _releaseFocus() async {
    final session = _session;
    if (session == null) return;
    await MeditationFocusGate.shared.release(this, deactivate: () async {
      await session.setActive(false);
    });
  }

  Future<void> _play(int generation) async {
    if (!_current(generation)) return;
    final session = _session;
    if (session == null) return;
    final acquired = await MeditationFocusGate.shared.acquire(this,
        activate: () => session.setActive(true),
        deactivate: () async {
          await session.setActive(false);
        },
        isCurrent: () => _current(generation));
    if (!acquired) {
      if (_current(generation)) {
        pause();
        onInterruption?.call();
      }
      return;
    }
    if (!_current(generation)) {
      await _releaseFocus();
      return;
    }
    // play's Future ends with playback, not its start. Don't block pause/next cue.
    unawaited(_player!.play().catchError((Object _) => _fail(generation)));
  }

  @override
  void cue(String asset) {
    if (_disposed) return;
    if (!_allowedCue.hasMatch(asset)) {
      throw ArgumentError('Only bundled activity audio is supported');
    }
    _asset = asset;
    _wanted = true;
    _unavailable = false;
    _schedule((generation) async {
      await _initialize();
      if (!_current(generation)) return;
      await _player!.setAsset(asset);
      if (!_current(generation)) return;
      _loadedAsset = asset;
      await _play(generation);
    });
  }

  static final _allowedCue = RegExp(
    r'^assets/audio/(meditation/(en|ur)_(body_scan|muscle_relaxation|mindfulness)_[0-3]\.m4a|breathing/(en|ur)_(inhale|hold|exhale|rest)\.wav)$',
  );

  @override
  void pause() {
    if (_disposed) return;
    ++_generation;
    _wanted = false;
    unawaited(_player?.pause().catchError((Object _) {}));
    unawaited(_releaseFocus().catchError((Object _) {}));
  }

  @override
  void resume() {
    if (_disposed || _asset == null) return;
    if (_loadedAsset != _asset) {
      cue(_asset!);
      return;
    }
    _wanted = true;
    _schedule((generation) async {
      // Completed cues remain quiet until the next caption; no repeated loop.
      if (_player?.processingState != ProcessingState.completed) {
        await _play(generation);
      }
    });
  }

  @override
  void stop() {
    pause();
    _asset = null;
    _loadedAsset = null;
    unawaited(_player?.stop().catchError((Object _) {}));
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    ++_generation;
    unawaited(_interruptions?.cancel());
    unawaited(_noisy?.cancel());
    unawaited(_player?.dispose().catchError((Object _) {}));
    super.dispose();
  }
}
