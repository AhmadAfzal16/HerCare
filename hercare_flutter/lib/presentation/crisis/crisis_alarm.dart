import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../therapy/meditation_focus_gate.dart';

/// A public, local attention chime, not a request for help or proof of delivery.
abstract class CrisisAlarmAudio {
  Future<bool> start();
  Future<void> stop();
  void dispose();
}

class BundledCrisisAlarmAudio implements CrisisAlarmAudio {
  static const asset = 'assets/audio/crisis/support_chime.wav';
  AudioPlayer? _player;
  AudioSession? _session;
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  StreamSubscription<void>? _noisy;
  int _generation = 0;
  bool _disposed = false;
  VoidCallback? onInterruption;

  Future<void> _release() async {
    final session = _session;
    if (session == null) return;
    await MeditationFocusGate.shared.release(this, deactivate: () async {
      await session.setActive(false);
    });
  }

  @override
  Future<bool> start() async {
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    try {
      final session = _session ??= await AudioSession.instance;
      if (!current()) return false;
      await session.configure(const AudioSessionConfiguration.speech());
      if (!current()) return false;
      _interruptions ??= session.interruptionEventStream.listen((event) {
        if (event.begin) {
          unawaited(stop());
          onInterruption?.call();
        }
      });
      _noisy ??= session.becomingNoisyEventStream.listen((_) {
        unawaited(stop());
        onInterruption?.call();
      });
      final player = _player ??= AudioPlayer(
          handleInterruptions: false, handleAudioSessionActivation: false);
      await player.setAsset(asset);
      if (!current()) return false;
      await player.setLoopMode(LoopMode.one);
      if (!current()) return false;
      final granted = await MeditationFocusGate.shared.acquire(this,
          activate: () => session.setActive(true),
          deactivate: () async {
            await session.setActive(false);
          },
          isCurrent: current);
      if (!granted || !current()) return false;
      // This Future completes when playback ends, so never await it here.
      unawaited(player.play().catchError((Object _) {
        if (current()) {
          unawaited(stop());
          onInterruption?.call();
        }
      }));
      return true;
    } catch (_) {
      if (current()) await stop();
      return false;
    }
  }

  @override
  Future<void> stop() async {
    ++_generation; // A delayed asset/focus response can never start playback.
    try {
      await _player?.pause();
    } catch (_) {}
    try {
      await _release();
    } catch (_) {}
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stop());
    unawaited(_interruptions?.cancel());
    unawaited(_noisy?.cancel());
    unawaited(_player?.dispose().catchError((Object _) {}));
  }
}

class CrisisAlarmController extends ChangeNotifier {
  CrisisAlarmController({CrisisAlarmAudio? audio})
      : _audio = audio ?? BundledCrisisAlarmAudio() {
    final bundled = _audio;
    if (bundled is BundledCrisisAlarmAudio) bundled.onInterruption = stop;
  }
  static const maximumDuration = Duration(seconds: 15);
  final CrisisAlarmAudio _audio;
  Timer? _deadline;
  int _generation = 0;
  bool _disposed = false;
  bool _active = false;
  bool _unavailable = false;
  bool get active => _active;
  bool get unavailable => _unavailable;

  Future<void> start() async {
    if (_disposed || _active) return;
    final generation = ++_generation;
    _active = true;
    _unavailable = false;
    // Includes initialization time; a stalled plugin cannot extend the alarm.
    _deadline = Timer(maximumDuration, stop);
    notifyListeners();
    var started = false;
    try {
      started = await _audio.start();
    } catch (_) {}
    if (_disposed || generation != _generation) return;
    if (!started) {
      _unavailable = true;
      stop();
    }
  }

  void stop() {
    if (_disposed) return;
    ++_generation;
    _deadline?.cancel();
    _deadline = null;
    unawaited(_audio.stop().catchError((Object _) {}));
    if (!_active) return;
    _active = false;
    notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    stop();
    _disposed = true;
    _audio.dispose();
    super.dispose();
  }
}

/// Stop on page hiding, app background, account change, calls or headphone loss.
/// Starting is only possible by a visible explicit tap; it never sends a push.
class CrisisAlarmCard extends StatefulWidget {
  const CrisisAlarmCard(
      {super.key,
      required this.isUrdu,
      this.accountId,
      this.active = true,
      this.controller});
  final bool isUrdu;
  final String? accountId;
  final bool active;
  final CrisisAlarmController? controller;
  @override
  State<CrisisAlarmCard> createState() => _CrisisAlarmCardState();
}

class _CrisisAlarmCardState extends State<CrisisAlarmCard>
    with WidgetsBindingObserver {
  late CrisisAlarmController _alarm;
  String? _observedAccount;
  bool _hasObservedAccount = false;
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _alarm = widget.controller ?? CrisisAlarmController();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider?>();
    final account = auth?.user?.id;
    _enabled = widget.active &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        (auth == null ||
            widget.accountId == null ||
            account == widget.accountId);
    if (!_enabled || (_hasObservedAccount && account != _observedAccount)) {
      _alarm.stop();
    }
    _observedAccount = account;
    _hasObservedAccount = true;
  }

  @override
  void didUpdateWidget(CrisisAlarmCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _alarm.stop();
      if (oldWidget.controller == null) _alarm.dispose();
      _alarm = widget.controller ?? CrisisAlarmController();
    }
    if (oldWidget.accountId != widget.accountId || !widget.active) {
      _alarm.stop();
    }
    final auth = context.read<AuthProvider?>();
    _enabled = widget.active &&
        (ModalRoute.of(context)?.isCurrent ?? true) &&
        (auth == null ||
            widget.accountId == null ||
            auth.user?.id == widget.accountId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _alarm.stop();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarm.stop();
    if (widget.controller == null) _alarm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ur = widget.isUrdu;
    return AnimatedBuilder(
        animation: _alarm,
        builder: (context, _) => Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          ur
                              ? 'اختیاری مدد کی آواز'
                              : 'Optional attention sound',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(ur
                          ? 'صرف اس وقت بجائیں جب آس پاس کے کسی محفوظ شخص کی توجہ لینا مناسب ہو۔ آواز ۱۵ سیکنڈ میں بند ہو جاتی ہے؛ یہ کال یا گارڈین کو اطلاع نہیں بھیجتی۔ اپنے فون کی آواز چیک کریں۔'
                          : 'Use only when it is safe to get a nearby person’s attention. Stops within 15 seconds; this does not call or notify your guardian. Check your phone volume.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                          key: const ValueKey('crisis-alarm-toggle'),
                          onPressed: _alarm.active
                              ? _alarm.stop
                              : (_enabled ? _alarm.start : null),
                          icon: Icon(_alarm.active
                              ? Icons.stop_circle_outlined
                              : Icons.volume_up_outlined),
                          label: Text(_alarm.active
                              ? (ur ? 'آواز بند کریں' : 'Stop sound')
                              : (ur
                                  ? 'مدد کی آواز بجائیں'
                                  : 'Play attention sound'))),
                      if (_alarm.unavailable) ...[
                        const SizedBox(height: 8),
                        Text(ur
                            ? 'آواز دستیاب نہیں ہے۔ براہ راست مدد کے اختیارات استعمال کریں۔'
                            : 'Sound is unavailable. Use the direct help options.'),
                      ],
                    ]),
              ),
            ));
  }
}
