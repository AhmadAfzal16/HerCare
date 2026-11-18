import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/voice_transcript.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../providers/mood_provider.dart';
import '../../services/mood_service.dart';
import 'journal_account_guard.dart';

class VoiceTranscriptScreen extends StatefulWidget {
  const VoiceTranscriptScreen(
      {super.key,
      required this.journalId,
      this.accountId,
      this.service,
      this.onPlay});
  final String journalId;
  final String? accountId;
  final MoodService? service;
  final VoidCallback? onPlay;
  @override
  State<VoiceTranscriptScreen> createState() => _VoiceTranscriptScreenState();
}

class _VoiceTranscriptScreenState extends State<VoiceTranscriptScreen>
    with WidgetsBindingObserver {
  late final MoodService _service;
  final _text = TextEditingController();
  VoiceTranscript? _value;
  Timer? _poll;
  String? _error;
  bool _busy = false, _denied = false;
  bool _confirmed = false;
  final _requestId = MoodService.requestId();
  late final DateTime _opened;
  bool get _same {
    if (!mounted) return false;
    final auth = context.read<AuthProvider?>();
    return widget.accountId == null ||
        auth == null ||
        (auth.user?.id == widget.accountId && auth.user?.isMother == true);
  }

  String tr(String en, String ur) =>
      context.read<LanguageProvider>().isUrdu ? ur : en;
  void _deny() {
    if (!_same) return;
    _poll?.cancel();
    setState(() {
      _denied = true;
      _value = null;
      _text.clear();
      _error = null;
    });
  }

  @override
  void initState() {
    super.initState();
    _opened = DateTime.now();
    _service = widget.service ?? (MoodService()..bindAccount(widget.accountId));
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _schedule() {
    _poll?.cancel();
    if (!_same ||
        _value?.pending != true ||
        DateTime.now().difference(_opened) > const Duration(minutes: 2)) {
      return;
    }
    _poll = Timer(const Duration(seconds: 5), _refresh);
  }

  Future<void> _refresh() async {
    if (_busy || !_same || _denied) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _service.getTranscript(widget.journalId);
      if (!_same) return;
      setState(() {
        final previous = _value;
        _value = value;
        if (value?.status == 'review' &&
            (previous?.status != 'review' ||
                previous?.revision != value?.revision)) {
          _text.text = value!.draft!;
        }
      });
    } on MoodAccessException {
      _deny();
    } on MoodAccountException {
      _deny();
    } catch (error) {
      if (_same) {
        setState(() => _error = tr(
            'Could not load the transcript. Reconnect and retry.',
            'نقل لوڈ نہیں ہوئی۔ کنکشن چیک کریں۔'));
      }
    } finally {
      if (_same) setState(() => _busy = false);
    }
    _schedule();
  }

  Future<void> _request() async {
    if (_busy || !_same || _denied) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final value = await _service.requestTranscript(widget.journalId);
      if (!_same) return;
      setState(() {
        _value = value;
        if (value.draft != null) _text.text = value.draft!;
      });
    } on MoodAccessException {
      _deny();
    } on MoodAccountException {
      _deny();
    } catch (_) {
      if (_same) {
        setState(() => _error = tr(
            'Transcription could not be requested. Your audio is still saved.',
            'نقل کی درخواست نہیں ہو سکی۔ آڈیو محفوظ ہے۔'));
      }
    } finally {
      if (_same) setState(() => _busy = false);
    }
    _schedule();
  }

  Future<void> _confirm() async {
    if (_busy ||
        !_same ||
        _value?.status != 'review' ||
        _text.text.trim().isEmpty) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final danger = await _service.confirmTranscript(
          widget.journalId, _text.text, _value!.revision, _requestId);
      if (!mounted || !_same) return;
      setState(() {
        _confirmed = true;
        _value = null;
        _text.clear();
      });
      final provider = context.read<MoodProvider?>();
      if (provider != null) unawaited(provider.searchJournals(''));
      if (danger) {
        context.push(AppRoutes.crisis);
      }
    } on MoodAccessException {
      _deny();
    } on MoodAccountException {
      _deny();
    } catch (_) {
      if (_same) {
        setState(() => _error = tr(
            'Not confirmed. Reconnect and retry; your corrections are still here. If it changed on another device, refresh first.',
            'تصدیق نہیں ہوئی۔ دوبارہ کوشش کریں؛ درستگی یہاں موجود ہے۔ دوسرے فون پر بدلا ہو تو پہلے تازہ کریں۔'));
      }
    } finally {
      if (_same) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy || !_same) return;
    setState(() => _busy = true);
    try {
      await _service.cancelTranscript(widget.journalId);
      if (_same) {
        setState(() {
          _value = null;
          _text.clear();
          _poll?.cancel();
        });
      }
    } on MoodAccessException {
      _deny();
    } on MoodAccountException {
      _deny();
    } catch (_) {
      if (_same) {
        setState(() => _error = tr(
            'Draft was not removed. Retry when connected.',
            'مسودہ نہیں ہٹا۔ کنکشن پر دوبارہ کوشش کریں۔'));
      }
    } finally {
      if (_same) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final value = _value;
    if (_denied) {
      return Scaffold(
          appBar: AppBar(title: Text(tr('Private journal', 'نجی جریدہ'))),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr(
                      'Private access is unavailable. Reopen your journal after checking your account and consent.',
                      'نجی رسائی دستیاب نہیں۔ اکاؤنٹ اور رضامندی چیک کرکے دوبارہ کھولیں۔')))));
    }
    return JournalAccountGuard(
        accountId: widget.accountId,
        child: Scaffold(
            appBar: AppBar(
                title: Text(tr('Review voice transcript', 'صوتی نقل دیکھیں'))),
            body: SafeArea(
                child: ListView(padding: const EdgeInsets.all(16), children: [
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(tr(
                          'Optional private transcript on your own server. Check the words before confirming; guardians never see them.',
                          'آپ کے سرور پر اختیاری نجی نقل۔ تصدیق سے پہلے الفاظ دیکھیں؛ سرپرست یہ نہیں دیکھتے۔')))),
              if (widget.onPlay != null)
                TextButton.icon(
                    onPressed: widget.onPlay,
                    icon: const Icon(Icons.play_circle_outline),
                    label: Text(tr(
                        'Listen / pause original', 'اصل آڈیو سنیں / روکیں'))),
              ExpansionTile(
                  title:
                      Text(tr('Privacy & safety details', 'رازداری اور حفاظت')),
                  children: [
                    Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(tr(
                            'Audio and text remain encrypted and private. Speech recognition can be wrong; correct any misheard words. Confirmed text uses sentiment and safety checks. This is not a diagnosis or emergency monitoring. You can cancel a draft without deleting the audio.',
                            'آڈیو اور متن خفیہ اور نجی رہتے ہیں۔ شناخت غلط ہو سکتی ہے؛ الفاظ درست کریں۔ تصدیق شدہ متن پر موڈ اور حفاظت کی جانچ ہوتی ہے۔ یہ تشخیص یا ہنگامی نگرانی نہیں۔ مسودہ منسوخ کرنے سے آڈیو نہیں مٹتی۔')))
                  ]),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error!)),
              if (!_confirmed &&
                  (value == null ||
                      ['failed', 'no_speech'].contains(value.status))) ...[
                if (value != null)
                  Text(tr(
                      value.status == 'no_speech'
                          ? 'No usable speech was found. Your original audio remains saved.'
                          : 'Transcription was unavailable or this clip could not be processed. The original audio remains saved.',
                      'قابلِ استعمال نقل نہیں ملی۔ اصل آڈیو محفوظ ہے۔')),
                const SizedBox(height: 12),
                FilledButton.icon(
                    key: const ValueKey('voice-request'),
                    onPressed: _busy ? null : _request,
                    icon: const Icon(Icons.record_voice_over),
                    label: Text(tr(
                        'Create private transcript', 'نجی صوتی نقل بنائیں'))),
                Text(tr(
                    'English/Urdu, up to 60 seconds. No automatic upload retry from the phone.',
                    'انگریزی/اردو، زیادہ سے زیادہ ۶۰ سیکنڈ۔ فون سے خودکار دوبارہ اپ لوڈ نہیں۔')),
              ],
              if (value?.pending == true) ...[
                Text(tr(
                    'Queued on your server. You can leave and check later; your audio is already saved.',
                    'سرور پر درخواست ہے۔ بعد میں دیکھ سکتے ہیں؛ آڈیو پہلے سے محفوظ ہے۔')),
                TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: Text(tr('Cancel transcription, keep audio',
                        'نقل منسوخ کریں، آڈیو رکھیں'))),
              ],
              if (value?.status == 'review') ...[
                if (value!.safetyHint)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(tr(
                              'Possible safety language appears in this unreviewed draft. Recognition may be wrong. If it reflects how you feel, open Immediate Help now; do not wait to confirm.',
                              'مسودے میں ممکنہ حفاظتی الفاظ ہیں؛ شناخت غلط بھی ہو سکتی ہے۔ اگر یہ آپ کی کیفیت ہے تو ابھی فوری مدد لیں، تصدیق کا انتظار نہ کریں۔')))),
                TextFormField(
                    key: const ValueKey('voice-draft'),
                    controller: _text,
                    minLines: 5,
                    maxLines: 12,
                    maxLength: 5000,
                    enabled: !_busy,
                    decoration: InputDecoration(
                        labelText: tr('Correct any misheard words',
                            'غلط سنے الفاظ درست کریں'),
                        border: const OutlineInputBorder())),
                const SizedBox(height: 12),
                FilledButton.icon(
                    key: const ValueKey('voice-confirm'),
                    onPressed: _busy ? null : _confirm,
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(tr('These are my words — confirm',
                        'یہ میرے الفاظ ہیں — تصدیق کریں'))),
                TextButton(
                    onPressed: _busy ? null : _cancel,
                    child: Text(tr('Discard draft, keep audio',
                        'مسودہ ہٹائیں، آڈیو رکھیں'))),
              ],
              if (_confirmed || value?.status == 'confirmed')
                Text(tr(
                    'Confirmed and analyzed. Read/search it in your private journal. Guardians never receive the transcript.',
                    'تصدیق اور تجزیہ ہو گیا۔ نجی جریدے میں پڑھیں یا تلاش کریں۔ سرپرست کو نقل نہیں ملتی۔')),
              OutlinedButton(
                  onPressed: _busy ? null : _refresh,
                  child: Text(tr('Refresh status', 'حالت تازہ کریں'))),
              TextButton.icon(
                  onPressed: () => context.push(AppRoutes.crisis),
                  icon: const Icon(Icons.health_and_safety_outlined),
                  label: Text(tr('Immediate help', 'فوری مدد'))),
            ]))));
  }
}
