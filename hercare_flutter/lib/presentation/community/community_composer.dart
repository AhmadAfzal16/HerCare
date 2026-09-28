import 'package:flutter/material.dart';
import '../../services/community_service.dart';
import '../crisis/crisis_support_screen.dart';
import 'community_widgets.dart';

class CommunityComposer extends StatefulWidget {
  const CommunityComposer(
      {super.key,
      required this.service,
      required this.urdu,
      this.parentId,
      this.sessionId,
      this.topic});
  final CommunityService service;
  final bool urdu;
  final String? parentId, sessionId, topic;
  @override
  State<CommunityComposer> createState() => _CommunityComposerState();
}

class _CommunityComposerState extends State<CommunityComposer> {
  final _title = TextEditingController(), _body = TextEditingController();
  late String _topic = widget.topic ?? 'coping';
  String _requestId = CommunityService.requestId();
  bool _sending = false;
  String? _error;
  String tr(String en, String ur) => widget.urdu ? ur : en;
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
      if (!mounted) return;
      final support = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
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
              ));
      if (support == true && mounted) {
        await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const CrisisSupportScreen()));
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_sending,
      child: Scaffold(
        appBar: AppBar(
            title: Text(widget.parentId == null
                ? tr('Share with the circle', 'حلقے میں بات کریں')
                : tr('Write a supportive reply', 'حوصلہ افزا جواب لکھیں'))),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(tr(
              'Share your experience in English or Urdu. Leave out names, phone numbers, addresses and links. Moderators review every submission.',
              'اپنا تجربہ اردو یا انگریزی میں بانٹیں۔ نام، فون نمبر، پتے اور لنکس شامل نہ کریں۔ ہر پیغام کا جائزہ لیا جاتا ہے۔')),
          const SizedBox(height: 20),
          if (widget.parentId == null) ...[
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final key in communityTopics.keys)
                ChoiceChip(
                    label: Text(communityTopic(key, widget.urdu)),
                    selected: _topic == key,
                    onSelected: _sending
                        ? null
                        : (_) => setState(() {
                              _topic = key;
                              _changed('');
                            })),
            ]),
            const SizedBox(height: 18),
            TextField(
                controller: _title,
                enabled: !_sending,
                maxLength: 120,
                onChanged: _changed,
                decoration: InputDecoration(
                    labelText: tr('Title', 'عنوان'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 14),
          ],
          TextField(
              controller: _body,
              enabled: !_sending,
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
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: const Icon(Icons.send_outlined),
              label: Text(_sending
                  ? tr('Sending…', 'بھیج رہے ہیں…')
                  : tr('Send for review', 'جائزے کے لیے بھیجیں'))),
        ])),
      ));
}
