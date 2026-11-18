import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/chatbot_models.dart';
import '../../providers/language_provider.dart';
import '../../services/chatbot_service.dart';
import 'offline_support.dart';

/// Separate from guardian messaging; routes key private state by account.
/// Offline text is memory-only and is never queued for automatic upload.
class HumRaazScreen extends StatefulWidget {
  const HumRaazScreen({super.key, this.service});
  final ChatbotService? service;
  @override
  State<HumRaazScreen> createState() => _HumRaazScreenState();
}

class _HumRaazScreenState extends State<HumRaazScreen> {
  late final ChatbotService _service;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  ChatbotStatus? _status;
  ChatbotSession? _session;
  List<ChatbotSession> _sessions = [];
  List<ChatbotMessage> _messages = [];
  final Map<String, List<ChatbotMessage>> _cache = {};
  _PendingSend? _pending;
  String? _languageOverride, _error, _messageCursor, _sessionCursor;
  bool _loading = true,
      _sending = false,
      _offline = false,
      _offlineUrgent = false;
  int _epoch = 0;
  String get _language =>
      _languageOverride ??
      (context.read<LanguageProvider>().isUrdu ? 'ur' : 'en');
  String _t(String en, String ur, String roman) =>
      OfflineSupport.text(_language, en, ur, roman);

  void _remember(String sessionId) {
    _cache.remove(sessionId);
    _cache[sessionId] = List.of(_messages.length > 300
        ? _messages.sublist(_messages.length - 300)
        : _messages);
    while (_cache.length > 12) {
      _cache.remove(_cache.keys.first);
    }
  }

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? ChatbotService();
    WidgetsBinding.instance.addPostFrameCallback((_) => _connect());
  }

  Future<void> _connect() async {
    if (!mounted || _sending) return;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.status();
      final history = await _service.sessions();
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _status = status;
        _sessions = List.of(history.sessions);
        _sessionCursor = history.hasMore ? history.nextCursor : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _status = null;
        _error = _t(
            'Server unavailable. Retry or choose limited offline support.',
            'سرور دستیاب نہیں۔ دوبارہ کوشش یا محدود آف لائن مدد منتخب کریں۔',
            'Server available nahi. Retry ya limited offline support chunein.');
      });
    }
  }

  void _scrollEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut);
        }
      });

  Future<void> _send() async {
    if (_sending || _loading) return;
    final text = _pending?.text ?? _controller.text.trim();
    if (text.isEmpty) return;
    if (_offline) {
      final urgent = _offlineUrgent || OfflineSupport.needsImmediateHelp(text);
      setState(() {
        _offlineUrgent = urgent;
        _messages.addAll([
          ChatbotMessage(
              id: ChatbotService.requestId(),
              role: 'user',
              content: text,
              language: _language,
              createdAt: DateTime.now()),
          ChatbotMessage(
              id: ChatbotService.requestId(),
              role: 'assistant',
              content: OfflineSupport.reply(_language, urgent: urgent),
              language: _language,
              createdAt: DateTime.now(),
              metadata: {'mode': 'offline_support', 'requires_help': urgent}),
        ]);
        if (_messages.length > 100) {
          _messages.removeRange(0, _messages.length - 100);
        }
        _controller.clear();
      });
      _scrollEnd();
      return;
    }
    if (_status?.available != true) return;
    final pending =
        _pending ?? _PendingSend(text, _language, ChatbotService.requestId());
    final epoch = _epoch;
    setState(() {
      _sending = true;
      _pending = pending;
      _error = null;
    });
    try {
      final session =
          _session ?? await _service.createSession(pending.language);
      if (!mounted || epoch != _epoch) return;
      _session = session;
      final result = await _service.send(session.id,
          message: pending.text,
          language: pending.language,
          requestId: pending.id);
      if (!mounted || epoch != _epoch) return;
      if (result.status != 'complete') {
        throw const FormatException('Reply not completed');
      }
      setState(() {
        for (final message in result.messages) {
          if (!_messages.any((item) => item.id == message.id)) {
            _messages.add(
                message.role == 'assistant' && message.metadata.isEmpty
                    ? ChatbotMessage(
                        id: message.id,
                        role: message.role,
                        content: message.content,
                        language: message.language,
                        createdAt: message.createdAt,
                        metadata: result.reply)
                    : message);
          }
        }
        _remember(session.id);
        if (!_sessions.any((item) => item.id == session.id)) {
          _sessions.insert(0, session);
        }
        _pending = null;
        _controller.clear();
        _sending = false;
      });
      _scrollEnd();
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _sending = false;
        _error = _t(
            'Reply not confirmed. The message may have reached the server. Retry uses the same request; nothing is automatically resent.',
            'جواب کی تصدیق نہیں ہوئی۔ پیغام سرور تک پہنچا ہو سکتا ہے۔ دوبارہ کوشش اسی درخواست سے ہوگی؛ خودکار ارسال نہیں ہوگا۔',
            'Reply confirm nahi hua. Message server tak pohancha ho sakta hai. Retry usi request se hogi; automatic resend nahi hota.');
      });
    }
  }

  void _newConversation({bool offline = false}) {
    if (_sending) return;
    ++_epoch;
    setState(() {
      _session = null;
      _messages = [];
      _pending = null;
      _error = null;
      _offline = offline;
      _offlineUrgent = false;
      _messageCursor = null;
      _loading = false;
      _controller.clear();
    });
  }

  Future<void> _openSession(ChatbotSession session) async {
    if (_sending) return;
    final epoch = ++_epoch;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final history = await _service.messages(session.id);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _session = session;
        _messages = List.of(history.messages);
        _remember(session.id);
        _messageCursor = history.hasMore ? history.nextCursor : null;
        _offline = false;
        _pending = null;
        _controller.clear();
        _loading = false;
      });
      _scrollEnd();
    } catch (_) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _loading = false;
        _status = null;
        _error = _t(
            'History could not refresh. Any cached copy is read-only until the server reconnects.',
            'گفتگو تازہ نہیں ہو سکی۔ سرور سے رابطے تک عارضی نقل صرف پڑھی جا سکتی ہے۔',
            'History refresh nahi hui. Cached copy server reconnect honay tak sirf parhi ja sakti hai.');
        if (_cache[session.id] != null) {
          _session = session;
          _messages = List.of(_cache[session.id]!);
          _offline = false;
          _pending = null;
          _controller.clear();
          _messageCursor = null;
        }
      });
    }
  }

  Future<void> _older() async {
    if (_session == null || _messageCursor == null || _loading || _sending) {
      return;
    }
    final epoch = _epoch;
    setState(() {
      _loading = true;
    });
    try {
      final history =
          await _service.messages(_session!.id, before: _messageCursor);
      if (!mounted || epoch != _epoch) return;
      setState(() {
        final ids = _messages.map((item) => item.id).toSet();
        _messages.insertAll(
            0, history.messages.where((item) => !ids.contains(item.id)));
        _messageCursor = history.hasMore ? history.nextCursor : null;
        _loading = false;
        _remember(_session!.id);
      });
    } catch (_) {
      if (mounted && epoch == _epoch) {
        setState(() {
          _loading = false;
          _error = _t('Earlier messages unavailable.',
              'پرانے پیغامات دستیاب نہیں۔', 'Purane messages available nahi.');
        });
      }
    }
  }

  Future<void> _showHistory() async {
    if (_sending) return;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
            child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * .65,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  Text(
                      _t('Private conversation history', 'نجی گفتگو کی تاریخ',
                          'Private conversation history'),
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_sessions.isEmpty)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_t(
                            'No saved conversations yet.',
                            'ابھی کوئی محفوظ گفتگو نہیں۔',
                            'Abhi koi saved conversation nahi.'))),
                  for (final session in _sessions)
                    ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(
                            '${session.createdAt.toLocal().year}-${session.createdAt.toLocal().month.toString().padLeft(2, '0')}-${session.createdAt.toLocal().day.toString().padLeft(2, '0')}'),
                        subtitle: Text(session.language),
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _openSession(session);
                        }),
                  if (_sessionCursor != null)
                    TextButton(
                        onPressed: () async {
                          Navigator.pop(sheetContext);
                          try {
                            final more =
                                await _service.sessions(before: _sessionCursor);
                            if (!mounted) return;
                            setState(() {
                              _sessions.addAll(more.sessions.where((item) =>
                                  !_sessions.any((old) => old.id == item.id)));
                              _sessionCursor =
                                  more.hasMore ? more.nextCursor : null;
                            });
                            if (mounted) _showHistory();
                          } catch (_) {
                            if (mounted) {
                              setState(() {
                                _error = _t(
                                    'History unavailable.',
                                    'گفتگو کی تاریخ دستیاب نہیں۔',
                                    'History available nahi.');
                              });
                            }
                          }
                        },
                        child: Text(_t('Load more conversations', 'مزید گفتگو',
                            'Mazeed conversations'))),
                ]))));
  }

  Future<void> _delete() async {
    final session = _session;
    if (session == null || _sending) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(_t('Delete this conversation?',
                    'یہ گفتگو حذف کریں؟', 'Yeh conversation delete karein?')),
                content: Text(_t(
                    'This removes this conversation from your server history, not your health records.',
                    'یہ گفتگو سرور سے حذف ہوگی، صحت کے ریکارڈ نہیں۔',
                    'Yeh conversation server history se delete hogi, health records nahi.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(_t('Cancel', 'منسوخ', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(_t('Delete', 'حذف', 'Delete')))
                ]));
    if (!mounted || confirmed != true) return;
    setState(() {
      _loading = true;
    });
    try {
      await _service.deleteSession(session.id);
      if (!mounted) return;
      _cache.remove(session.id);
      _sessions.removeWhere((item) => item.id == session.id);
      _newConversation();
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _t('Deletion was not confirmed.',
              'حذف ہونے کی تصدیق نہیں ہوئی۔', 'Delete confirm nahi hua.');
        });
      }
    }
  }

  Future<void> _consent(bool enabled) async {
    if (_sending || _loading || _offline) return;
    if (enabled) {
      final agreed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  scrollable: true,
                  title: Text(_t(
                      'Use aggregate health context?',
                      'مجموعی صحت کے اسکور استعمال کریں؟',
                      'Aggregate health context use karein?')),
                  content: Text(_t(
                      'Optional: Hum-Raaz may read recorded mood, screening scores, research-only risk estimates and aggregate journal sentiment scores to adapt support. These are not diagnoses. Raw journal text, audio, guardian messages and phone notifications are excluded. Chat history is saved for continuity, not model training. Switching this off stops future use of aggregate-personalized history, but old replies remain viewable until you delete the conversation. This does not enable guardian alerts.',
                      'اختیاری: مدد کے لیے موڈ، جانچ، تحقیقی خطرے کے اندازے اور جریدے کے مجموعی جذباتی اسکور پڑھے جا سکتے ہیں۔ یہ تشخیص نہیں۔ جریدے کا اصل متن، آڈیو، سرپرست کے پیغامات یا فون اطلاعات شامل نہیں۔ گفتگو تسلسل کے لیے ہے، تربیت کے لیے نہیں۔ اجازت بند کرنے پر ذاتی اسکور والی سابقہ گفتگو آئندہ جواب میں استعمال نہیں ہوگی، مگر حذف کرنے تک پڑھی جا سکے گی۔ اس سے سرپرست کی اطلاعات فعال نہیں ہوتیں۔',
                      'Optional: Hum-Raaz mood, screening scores, research-only risk estimates aur aggregate journal sentiment scores use kar sakta hai. Yeh diagnosis nahi. Raw journal text, audio, guardian messages aur phone notifications shamil nahi. History continuity ke liye hai, training ke liye nahi. Band karnay par personalized history future replies mein use nahi hogi; puranay replies delete karnay tak parhay ja sakte hain. Is se guardian alerts enable nahi hotay.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(_t('Not now', 'ابھی نہیں', 'Abhi nahi'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(
                            _t('I agree', 'میں متفق ہوں', 'Main razi hoon')))
                  ]));
      if (!mounted || agreed != true) return;
    }
    setState(() {
      _loading = true;
    });
    try {
      final consent = await _service.consent(enabled);
      if (!mounted) return;
      setState(() {
        _status = ChatbotStatus(
            available: _status?.available == true,
            historyEncrypted: _status?.historyEncrypted == true,
            consent: consent);
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _t(
              'Consent was not updated. Retry.',
              'اجازت تبدیل نہیں ہوئی۔ دوبارہ کوشش کریں۔',
              'Consent update nahi hui. Retry karein.');
        });
      }
    }
  }

  @override
  void dispose() {
    ++_epoch;
    _cache.clear();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final language = _language;
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
          backgroundColor: context.hcSurface,
          toolbarHeight:
              72 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.8),
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_t('Hum-Raaz', 'ہم راز', 'Hum-Raaz'),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
                _t(
                    'Wellbeing support · not a therapist',
                    'صحت کی مدد · معالج نہیں',
                    'Wellbeing support · therapist nahi'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall),
          ]),
          actions: [
            PopupMenuButton<String>(
                tooltip: _t('Reply language', 'جواب کی زبان', 'Reply language'),
                icon: const Icon(Icons.translate),
                onSelected: (value) => setState(() {
                      _languageOverride = value == 'app' ? null : value;
                    }),
                itemBuilder: (_) => [
                      PopupMenuItem(
                          value: 'app',
                          child: Text(_t('Follow app language', 'ایپ کی زبان',
                              'App ki language'))),
                      const PopupMenuItem(value: 'en', child: Text('English')),
                      const PopupMenuItem(value: 'ur', child: Text('اردو')),
                      const PopupMenuItem(
                          value: 'roman_ur', child: Text('Roman Urdu')),
                    ])
          ]),
      body: SafeArea(
          top: false,
          child: ListView(
              controller: _scroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
              children: [
                _notice(_offline
                    ? _t(
                        'Limited offline guide · not live AI · no scores or notifications',
                        'محدود آف لائن رہنمائی · براہ راست AI نہیں · اسکور یا اطلاعات نہیں',
                        'Limited offline guide · live AI nahi · scores ya notifications nahi')
                    : _t(
                        'Server support · research-only, not diagnosis · private history',
                        'سرور کی مدد · تحقیقی، تشخیص نہیں · نجی گفتگو',
                        'Server support · research-only, diagnosis nahi · private history')),
                ExpansionTile(
                    key: const PageStorageKey<String>(
                        'hum-raaz-privacy-controls'),
                    maintainState: true,
                    tilePadding: EdgeInsets.zero,
                    title: Text(_t('Conversation & privacy',
                        'گفتگو اور رازداری', 'Conversation aur privacy')),
                    children: [
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        OutlinedButton.icon(
                            onPressed: _sending || _loading
                                ? null
                                : () => _newConversation(offline: _offline),
                            icon: const Icon(Icons.add),
                            label: Text(_t('New', 'نئی گفتگو', 'Nayi'))),
                        OutlinedButton.icon(
                            onPressed:
                                _sending || _offline ? null : _showHistory,
                            icon: const Icon(Icons.history),
                            label: Text(_t('History', 'تاریخ', 'History'))),
                        if (_session != null)
                          OutlinedButton.icon(
                              onPressed: _sending || _loading ? null : _delete,
                              icon: const Icon(Icons.delete_outline),
                              label: Text(_t('Delete', 'حذف', 'Delete'))),
                      ]),
                      SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _status?.consent.enabled == true,
                          title: Text(_t(
                              'Use my aggregate scores',
                              'میرے مجموعی اسکور استعمال کریں',
                              'Meray aggregate scores use karein')),
                          subtitle: Text(_t(
                              'Optional; no raw journals or guardian chats',
                              'اختیاری؛ نجی جریدہ یا سرپرست چیٹ نہیں',
                              'Optional; raw journals ya guardian chats nahi')),
                          onChanged: _status == null ||
                                  _loading ||
                                  _sending ||
                                  _offline
                              ? null
                              : _consent),
                      Text(
                          _t(
                              'Past conversations stay on the server until you delete them. Offline conversations stay only in this screen’s memory.',
                              'پچھلی گفتگو حذف کرنے تک سرور پر رہے گی۔ آف لائن گفتگو صرف اس اسکرین کی یادداشت میں رہے گی۔',
                              'Past conversations delete karnay tak server par rahengi. Offline conversation sirf screen ki memory mein rahegi.'),
                          style: Theme.of(context).textTheme.bodySmall),
                    ]),
                if (_error != null) _notice(_error!, error: true),
                if (_loading)
                  const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator())),
                if (!_offline && (_error != null || _status?.available != true))
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton(
                        onPressed: _loading || _sending ? null : _connect,
                        child: Text(_t('Retry connection', 'رابطے کی کوشش',
                            'Connection retry'))),
                    OutlinedButton(
                        onPressed: _loading || _sending
                            ? null
                            : () => _newConversation(offline: true),
                        child: Text(_t('Limited offline support',
                            'محدود آف لائن مدد', 'Limited offline support'))),
                  ]),
                if (_messages.isEmpty && !_loading)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      child: Text(_offline
                          ? OfflineSupport.reply(language)
                          : _t(
                              'How are you feeling today? Ask about HerCare, your check-ins, or gentle coping support. Hum-Raaz cannot diagnose, prescribe or provide emergency care.',
                              'آج آپ کیسا محسوس کر رہی ہیں؟ HerCare، صحت کے اندراج یا سکون کی مدد پوچھیں۔ ہم راز تشخیص، دوا یا ہنگامی علاج فراہم نہیں کرتا۔',
                              'Aaj aap kaisa mehsoos kar rahi hain? HerCare, check-ins ya gentle support ke baray mein poochain. Hum-Raaz diagnosis, prescription ya emergency care nahi deta.'))),
                if (_messageCursor != null)
                  TextButton(
                      onPressed: _loading ? null : _older,
                      child: Text(_t('Earlier messages', 'پرانے پیغامات',
                          'Puranay messages'))),
                for (final message in _messages) _bubble(message),
                if (_pending != null && !_sending)
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_t('Pending confirmation', 'تصدیق باقی ہے',
                                    'Confirmation pending')),
                                Text(_pending!.text),
                                Wrap(spacing: 8, children: [
                                  TextButton(
                                      onPressed: _send,
                                      child: Text(_t(
                                          'Retry same message',
                                          'اسی پیغام کی کوشش',
                                          'Same message retry'))),
                                  TextButton(
                                      onPressed: () => setState(() {
                                            _pending = null;
                                            _controller.clear();
                                          }),
                                      child: Text(_t(
                                          'Dismiss pending copy',
                                          'عارضی نقل ہٹائیں',
                                          'Pending copy hata dein')))
                                ]),
                              ]))),
                if (_offline)
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    if (!_offlineUrgent)
                      OutlinedButton(
                          onPressed: () {
                            setState(() {
                              _messages.add(ChatbotMessage(
                                  id: ChatbotService.requestId(),
                                  role: 'assistant',
                                  content: OfflineSupport.grounding(language),
                                  language: language,
                                  createdAt: DateTime.now(),
                                  metadata: const {'mode': 'offline_support'}));
                            });
                            _scrollEnd();
                          },
                          child: Text(_t('Grounding card', 'توجہ کی مشق',
                              'Grounding card'))),
                    OutlinedButton(
                        onPressed: () {
                          _newConversation();
                          _connect();
                        },
                        child: Text(_t('Reconnect online', 'آن لائن رابطہ',
                            'Online reconnect'))),
                  ]),
                const SizedBox(height: 10),
                Directionality(
                    textDirection: language == 'ur'
                        ? TextDirection.rtl
                        : TextDirection.ltr,
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                              child: TextField(
                                  key: const ValueKey('chatbot-composer'),
                                  controller: _controller,
                                  enabled: !_sending &&
                                      _pending == null &&
                                      !_loading &&
                                      (_offline || _status?.available == true),
                                  minLines: 1,
                                  maxLines: 4,
                                  maxLength: 2000,
                                  decoration: InputDecoration(
                                      counterText: '',
                                      filled: true,
                                      fillColor: context.hcInputFill,
                                      hintText: _t('Write a message…',
                                          'پیغام لکھیں…', 'Message likhein…'),
                                      border: const OutlineInputBorder()))),
                          const SizedBox(width: 8),
                          IconButton.filled(
                              tooltip: _t('Send', 'ارسال', 'Send'),
                              onPressed: _sending ||
                                      _pending != null ||
                                      _loading ||
                                      (!_offline && _status?.available != true)
                                  ? null
                                  : _send,
                              icon: _sending
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : const Icon(Icons.send)),
                        ])),
                const SizedBox(height: 10),
                TextButton.icon(
                    onPressed: () => context.push(AppRoutes.crisis),
                    icon: const Icon(Icons.health_and_safety_outlined,
                        color: AppColors.crisis),
                    label: Text(
                        _t('Immediate Help', 'فوری مدد', 'Immediate Help'))),
              ])),
    );
  }

  Widget _notice(String text, {bool error = false}) => Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
          color: error ? AppColors.errorContainer : AppColors.primaryContainer,
          borderRadius: BorderRadius.circular(12)),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: error ? AppColors.error : AppColors.primary)));

  Widget _bubble(ChatbotMessage message) => Directionality(
      textDirection:
          message.language == 'ur' ? TextDirection.rtl : TextDirection.ltr,
      child: Align(
          alignment: message.isUser
              ? AlignmentDirectional.centerEnd
              : AlignmentDirectional.centerStart,
          child: Container(
              width: double.infinity,
              margin: EdgeInsetsDirectional.only(
                  start: message.isUser ? 28 : 0,
                  end: message.isUser ? 0 : 28,
                  bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: message.isUser
                      ? AppColors.primaryContainer
                      : context.hcSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: context.hcOutline)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        message.isUser
                            ? _t('You', 'آپ', 'Aap')
                            : _t('Hum-Raaz', 'ہم راز', 'Hum-Raaz'),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: message.isUser
                                ? AppColors.primary
                                : context.hcTextPrimary)),
                    const SizedBox(height: 4),
                    SelectableText(message.content,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: message.isUser
                                ? AppColors.primary
                                : context.hcTextPrimary)),
                    if (!message.isUser && message.metadata['mode'] is String)
                      Text(
                          message.metadata['mode'] == 'offline_support'
                              ? _t(
                                  'Fixed offline guide',
                                  'مقررہ آف لائن رہنمائی',
                                  'Fixed offline guide')
                              : '${message.metadata['mode']}',
                          style: Theme.of(context).textTheme.labelSmall),
                    if (!message.isUser) ..._sources(message.metadata),
                    if (!message.isUser) ..._actions(message.metadata),
                  ]))));

  List<Widget> _sources(Map<String, dynamic> metadata) {
    final sources = metadata['sources'];
    if (sources is! List) return [];
    return sources
        .whereType<Map>()
        .take(5)
        .map((source) => Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectableText(
                '${source['title'] ?? source['id'] ?? 'Source'}${source['url'] is String ? '\n${source['url']}' : ''}',
                style: Theme.of(context).textTheme.bodySmall)))
        .toList();
  }

  List<Widget> _actions(Map<String, dynamic> metadata) {
    final actions = metadata['actions'];
    if (actions is! List) return [];
    const routes = {
      'tests': AppRoutes.tests,
      'mood': AppRoutes.mood,
      'journal': AppRoutes.journal,
      'breathing': AppRoutes.breathing,
      'grounding': AppRoutes.therapy,
      'guardian': AppRoutes.guardianLink,
      'crisis': AppRoutes.crisis
    };
    final widgets = <Widget>[];
    for (final action in actions.take(4)) {
      final id = action is String
          ? action
          : action is Map
              ? action['id']
              : null;
      final route = routes[id];
      if (route == null) continue;
      widgets.add(TextButton(
          onPressed: () => context.push(route),
          child: Text(action is Map && action['label'] is String
              ? action['label'] as String
              : '$id')));
    }
    return widgets;
  }
}

class _PendingSend {
  const _PendingSend(this.text, this.language, this.id);
  final String text, language, id;
}
