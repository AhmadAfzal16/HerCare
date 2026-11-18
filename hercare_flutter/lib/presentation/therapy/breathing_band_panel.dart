import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// In-memory live feed from a connected heart-rate band, so a session can take
/// a 30-second before/after reading from the band instead of the camera.
/// Nothing here is persisted; only the final summary is saved with the session.
class HeartBandFeed extends ChangeNotifier {
  HeartBandFeed._();
  static final instance = HeartBandFeed._();
  bool live = false;
  int? bpm;
  final _intervals = StreamController<List<int>>.broadcast();

  /// Beat-to-beat intervals in ms, when the band sends them.
  Stream<List<int>> get intervals => _intervals.stream;

  void update({required bool live, int? bpm, List<int> intervals = const []}) {
    final changed = this.live != live || this.bpm != bpm;
    this.live = live;
    this.bpm = live ? bpm : null;
    if (live && intervals.isNotEmpty) _intervals.add(intervals);
    if (changed) notifyListeners();
  }
}

class BreathingBandPanel extends StatefulWidget {
  const BreathingBandPanel({
    super.key,
    required this.isUrdu,
    required this.enabled,
  });

  final bool isUrdu;
  final bool enabled;

  @override
  State<BreathingBandPanel> createState() => _BreathingBandPanelState();
}

class _BreathingBandPanelState extends State<BreathingBandPanel> {
  static const _control = MethodChannel('com.hercare/breathing_band');
  static const _events = EventChannel('com.hercare/breathing_band/events');
  final _devices = <String, String>{};
  StreamSubscription<dynamic>? _subscription;
  String _status = 'idle';
  int? _bpm;

  String _tr(String english, String urdu) => widget.isUrdu ? urdu : english;

  @override
  void didUpdateWidget(BreathingBandPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _disconnect();
  }

  void _receive(dynamic event) {
    if (!mounted || !widget.enabled || event is! Map) return;
    final device = event['device'];
    final status = event['status'];
    final bpm = event['bpm'];
    if (device is Map && device['id'] is String && device['name'] is String) {
      setState(
          () => _devices[device['id'] as String] = device['name'] as String);
    } else if (status is String) {
      setState(() {
        if (status == 'idle') _devices.clear();
        _status = status;
        _bpm = status == 'live' && bpm is int && bpm >= 1 && bpm <= 300
            ? bpm
            : null;
      });
      final rr = event['rr'];
      HeartBandFeed.instance.update(
          live: status == 'live' && _bpm != null,
          bpm: _bpm,
          intervals: rr is List
              ? rr
                  .whereType<int>()
                  .where((ms) => ms >= 250 && ms <= 2000)
                  .toList()
              : const []);
    }
  }

  void _onError(Object _) {
    HeartBandFeed.instance.update(live: false);
    if (mounted && widget.enabled) {
      setState(() {
        _status = 'connection_failed';
        _bpm = null;
      });
    }
  }

  Future<void> _send(String method, [Map<String, String>? args]) async {
    try {
      await _control.invokeMethod<void>(method, args);
    } on PlatformException catch (error) {
      if (method != 'stop') _onError(error);
    } on MissingPluginException catch (error) {
      if (method != 'stop') _onError(error);
    }
  }

  void _scan() {
    if (!widget.enabled) return;
    _subscription ??=
        _events.receiveBroadcastStream().listen(_receive, onError: _onError);
    setState(() {
      _devices.clear();
      _bpm = null;
      _status = 'scanning';
    });
    unawaited(_send('scan'));
  }

  void _disconnect() {
    _status = 'idle';
    _bpm = null;
    HeartBandFeed.instance.update(live: false);
    _devices.clear();
    if (_subscription != null) unawaited(_send('stop'));
  }

  @override
  void dispose() {
    _disconnect();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  String? get _message => switch (_status) {
        'permission' => _tr('Allow Nearby devices to find your band.',
            'بینڈ تلاش کرنے کے لیے قریبی آلات کی اجازت دیں۔'),
        'scanning' => _tr('Looking for heart-rate devices…',
            'دل کی دھڑکن کے آلات تلاش ہو رہے ہیں…'),
        'choose' => _tr('Select your band.', 'اپنا بینڈ منتخب کریں۔'),
        'connecting' => _tr('Waiting for a heart-rate reading…',
            'دل کی دھڑکن کی ریڈنگ کا انتظار ہے…'),
        'live' => _bpm == null
            ? null
            : _tr('Live heart rate: $_bpm bpm',
                'دل کی موجودہ رفتار: $_bpm فی منٹ'),
        'not_found' => _tr(
            'No band found. Turn on Share HR and keep the band nearby.',
            'بینڈ نہیں ملا۔ Share HR آن کریں اور بینڈ قریب رکھیں۔'),
        'no_service' => _tr(
            'The band did not share heart rate. Check that Share HR is on.',
            'بینڈ سے دل کی دھڑکن موصول نہیں ہوئی۔ Share HR چیک کریں۔'),
        'no_reading' => _tr(
            'No recent reading. Wear the band and check Share HR.',
            'حالیہ ریڈنگ دستیاب نہیں۔ بینڈ پہنیں اور Share HR چیک کریں۔'),
        'denied' => _tr(
            'Nearby devices permission is unavailable. You can allow it in app settings.',
            'قریبی آلات کی اجازت دستیاب نہیں۔ ایپ کی ترتیبات میں اجازت دیں۔'),
        'bluetooth_off' => _tr('Turn on Bluetooth, then try again.',
            'بلوٹوتھ آن کریں، پھر دوبارہ کوشش کریں۔'),
        'unsupported' => _tr(
            'Band connection requires Android 12 or later and Bluetooth LE.',
            'بینڈ کے لیے اینڈرائیڈ ۱۲ یا بعد کا ورژن اور بلوٹوتھ درکار ہیں۔'),
        'scan_failed' || 'connection_failed' => _tr(
            'Band connection unavailable. Turn on Share HR and try again.',
            'بینڈ کا رابطہ دستیاب نہیں۔ Share HR آن کرکے دوبارہ کوشش کریں۔'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !widget.enabled) {
      return const SizedBox.shrink();
    }
    final open = const {
      'permission',
      'scanning',
      'choose',
      'connecting',
      'live'
    }.contains(_status);
    final showDevices = _status == 'scanning' || _status == 'choose';
    final message = _message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (message != null)
          Semantics(
              liveRegion: _status != 'live',
              child: Text(message, textAlign: TextAlign.center)),
        if (showDevices)
          for (final device in _devices.entries)
            OutlinedButton(
              onPressed: () {
                setState(() => _status = 'connecting');
                unawaited(_send('connect', {'id': device.key}));
              },
              child: Text(device.value),
            ),
        TextButton.icon(
          onPressed: open ? () => setState(_disconnect) : _scan,
          icon: const Icon(Icons.watch_outlined),
          label: Text(open
              ? _tr('Disconnect band', 'بینڈ منقطع کریں')
              : _tr('Connect band', 'بینڈ جوڑیں')),
        ),
        if (_status != 'idle')
          Text(
              _tr('On the band, turn on Share HR in Settings. Readings are only shown during this visit.',
                  'بینڈ کی ترتیبات میں Share HR آن کریں۔ ریڈنگ صرف اس صفحے پر دکھائی جاتی ہے۔'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
