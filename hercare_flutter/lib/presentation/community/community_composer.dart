import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/community_service.dart';
import '../crisis/crisis_support_screen.dart';
import 'community_widgets.dart';
import 'community_account_scope.dart';

class CommunityComposer extends StatelessWidget {
  const CommunityComposer(
      {super.key,
      required this.service,
      required this.urdu,
      this.accountId,
      this.parentId,
      this.sessionId,
      this.topic});
  final CommunityService service;
  final bool urdu;
  final String? accountId, parentId, sessionId, topic;
  @override
  Widget build(BuildContext context) => CommunityAccountScope(
      accountId: accountId,
      builder: (_, owner) => _CommunityComposerView(
          service: service,
          urdu: urdu,
          accountId: owner,
          parentId: parentId,
          sessionId: sessionId,
          topic: topic));
}

class _CommunityComposerView extends StatefulWidget {
  const _CommunityComposerView(
      {required this.service,
      required this.urdu,
      required this.accountId,
      this.parentId,
      this.sessionId,
      this.topic});
  final CommunityService service;
  final bool urdu;
  final String? accountId, parentId, sessionId, topic;
  @override
  State<_CommunityComposerView> createState() => _CommunityComposerState();
}

class _CommunityComposerState extends State<_CommunityComposerView> {
  final _title = TextEditingController(), _body = TextEditingController();
  late String _topic = widget.topic ?? 'coping';
  String _requestId = CommunityService.requestId();
  bool _sending = false;
  String? _error;
  bool _uncertain = false;
  bool _accessDenied = false;
  bool get ur => context.read<LanguageProvider?>()?.isUrdu ?? widget.urdu;
  bool get _current =>
      mounted && CommunityAccountScope.current(context, widget.accountId);
  String tr(String en, String other) => ur ? other : en;
  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _requestId = CommunityService.requestId();
  }

  Future<void> _submit() async {
    if (!_current || _sending) return;
    if (_body.text.trim().length < 2 ||
        (widget.parentId == null && _title.text.trim().length < 3)) {
      setState(() => _error = tr('Add a title and a little more detail.',
          'عنوان اور کچھ مزید تفصیل شامل کریں۔'));
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await widget.service.submit({
        'body': _body.text.trim(),
        'title': _title.text.trim(),
        'topic': _topic,
        'client_request_id': _requestId,
        if (widget.parentId != null) 'parent_id': widget.parentId,
        if (widget.sessionId != null) 'session_id': widget.sessionId,
      });
      if (!mounted || !_current) return;
      _uncertain = false;
      final support = await showDialog<bool>(
          context: context,
          builder: (context) => CommunityAccountScope(
              accountId: widget.accountId,
              builder: (_, __) => CommunityDialog(
                    title: Text(tr('Sent for review', 'جائزے کے لیے بھیج دیا')),
                    content: SingleChildScrollView(
                        child: Text(result['safety_support'] == true
                            ? tr(
                                'Your message is waiting for a moderator. If you feel unsafe now, open immediate support or contact someone you trust. The community is not monitored as an emergency service.',
                                'آپ کا پیغام جائزے میں ہے۔ اگر آپ غیر محفوظ محسوس کریں تو فوری مدد کھولیں یا کسی قابل اعتماد شخص سے رابطہ کریں۔ یہ ہنگامی سروس نہیں ہے۔')
                            : tr(
                                'Your post will appear after a moderator reviews it. You can find your threads under My posts.',
                                'جائزے کے بعد آپ کی پوسٹ نظر آئے گی۔ اپنی گفتگو میری پوسٹس میں دیکھیں۔'))),
                    actions: [
                      if (result['safety_support'] == true)
                        TextButton(
                            onPressed: () {
                              Navigator.pop(context, true);
                            },
                            child: Text(tr('Immediate support', 'فوری مدد'))),
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(tr('Done', 'ٹھیک ہے'))),
                    ],
                  )));
      if (support == true && mounted && _current) {
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CrisisSupportScreen()));
      }
      if (mounted && _current) Navigator.pop(context, true);
    } catch (error) {
      if (_current) {
        setState(() {
          _error = error.toString();
          _accessDenied = error is CommunityException && error.accessDenied;
          if (_accessDenied) {
            _title.clear();
            _body.clear();
          }
          // Editing uncertain content would create a second submission. Retry
          // the exact original UUID first; do not silently replay after reconnect.
          _uncertain = error is! CommunityException || error.deliveryUncertain;
        });
      }
    } finally {
      if (_current) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider?>();
    if (_accessDenied) {
      return Scaffold(
          appBar: AppBar(title: Text(tr('Peer community', 'ساتھیوں کا حلقہ'))),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(24), children: [
            Text(_error ??
                tr('Access unavailable. Reopen the community.',
                    'رسائی دستیاب نہیں۔ حلقہ دوبارہ کھولیں۔')),
            TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: Text(tr('Back', 'واپس'))),
          ])));
    }
    return PopScope(
        canPop: !_sending,
        child: Scaffold(
          appBar: AppBar(
              title: Text(widget.parentId == null
                  ? tr('Share with the circle', 'حلقے میں بات کریں')
                  : tr('Write a supportive reply', 'حوصلہ افزا جواب لکھیں'))),
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(tr(
                'Share your experience in English, Urdu or Roman Urdu. Leave out names, phone numbers, addresses and links. Moderators review every submission.',
                'اپنا تجربہ اردو، رومن اردو یا انگریزی میں بانٹیں۔ نام، فون نمبر، پتے اور لنکس شامل نہ کریں۔ ہر پیغام کا جائزہ لیا جاتا ہے۔')),
            const SizedBox(height: 20),
            if (widget.parentId == null) ...[
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final key in communityTopics.keys)
                  ChoiceChip(
                      label: Text(communityTopic(key, ur)),
                      selected: _topic == key,
                      onSelected: _sending || _uncertain
                          ? null
                          : (_) => setState(() {
                                _topic = key;
                                _changed('');
                              })),
              ]),
              const SizedBox(height: 18),
              TextField(
                  controller: _title,
                  enabled: !_sending && !_uncertain,
                  maxLength: 120,
                  onChanged: _changed,
                  decoration: InputDecoration(
                      labelText: tr('Title', 'عنوان'),
                      border: const OutlineInputBorder())),
              const SizedBox(height: 14),
            ],
            TextField(
                controller: _body,
                enabled: !_sending && !_uncertain,
                minLines: 6,
                maxLines: 12,
                maxLength: 2000,
                onChanged: _changed,
                decoration: InputDecoration(
                    labelText: tr('Your words', 'آپ کی بات'),
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder())),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            if (_uncertain)
              Text(tr(
                  'Delivery is uncertain. Retry the same message before editing. It may already be waiting for review.',
                  'بھیجنے کی تصدیق نہیں ہوئی۔ تبدیلی سے پہلے یہی پیغام دوبارہ بھیجیں۔ ممکن ہے یہ جائزے میں ہو۔')),
            FilledButton.icon(
                onPressed: _sending ? null : _submit,
                icon: const Icon(Icons.send_outlined),
                label: Text(_sending
                    ? tr('Sending…', 'بھیج رہے ہیں…')
                    : _uncertain
                        ? tr('Retry this message', 'یہی پیغام دوبارہ بھیجیں')
                        : tr('Send for review', 'جائزے کے لیے بھیجیں'))),
          ])),
        ));
  }
}
