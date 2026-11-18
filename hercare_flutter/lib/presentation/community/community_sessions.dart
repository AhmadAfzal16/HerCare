import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/language_provider.dart';
import '../../services/community_service.dart';
import 'community_account_scope.dart';
import 'community_screen.dart';
import 'community_widgets.dart';

class CommunitySessions extends StatelessWidget {
  const CommunitySessions(
      {super.key, required this.service, required this.admin});
  final CommunityService service;
  final bool admin;
  @override
  Widget build(BuildContext context) => CommunityAccountScope(
      builder: (_, owner) =>
          _SessionsView(service: service, admin: admin, accountId: owner));
}

class _SessionsView extends StatefulWidget {
  const _SessionsView(
      {required this.service, required this.admin, required this.accountId});
  final CommunityService service;
  final bool admin;
  final String? accountId;
  @override
  State<_SessionsView> createState() => _SessionsViewState();
}

class _SessionsViewState extends State<_SessionsView> {
  final _sessions = <Map<String, dynamic>>[];
  String? _error;
  bool _loading = false;
  int _generation = 0;
  bool get _current =>
      mounted && CommunityAccountScope.current(context, widget.accountId);
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String other) => ur ? other : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_current) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _sessions.clear();
    });
    try {
      final sessions = await widget.service.sessions();
      if (_current && generation == _generation) {
        setState(() => _sessions.addAll(sessions.take(50)));
      }
    } catch (error) {
      if (_current && generation == _generation) {
        setState(() => _error = error.toString());
      }
    } finally {
      if (_current && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _schedule() async {
    if (!_current || _loading) return;
    await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CommunityAccountScope(
            accountId: widget.accountId,
            builder: (_, __) => _SessionEditor(
                service: widget.service, accountId: widget.accountId)));
    if (_current) await _load();
  }

  Future<void> _cancel(Map<String, dynamic> session) async {
    if (!_current || _loading) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => CommunityAccountScope(
            accountId: widget.accountId,
            builder: (_, __) => CommunityDialog(
                    title: Text(tr('Cancel this Q&A?', 'یہ نشست منسوخ کریں؟')),
                    content: Text(tr(
                        'Approved discussions remain readable. New messages will be closed.',
                        'منظور شدہ گفتگو پڑھ سکتے ہیں۔ نئے پیغامات بند ہو جائیں گے۔')),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(tr('Back', 'واپس'))),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(tr('Cancel session', 'نشست منسوخ کریں')))
                    ])));
    if (!_current || confirmed != true) return;
    setState(() => _loading = true);
    try {
      await widget.service.cancelSession(session['id'] as String);
      if (_current) await _load();
    } catch (error) {
      if (_current) {
        setState(() {
          _error = error.toString();
          _loading = false;
          if (error is CommunityException && error.unavailable) {
            _sessions.clear();
          }
        });
      }
    }
  }

  String _date(String value) {
    final date = DateTime.tryParse(value)?.toLocal();
    if (date == null) return tr('Time unavailable', 'وقت دستیاب نہیں');
    final local = MaterialLocalizations.of(context);
    return '${local.formatMediumDate(date)} ${local.formatTimeOfDay(TimeOfDay.fromDateTime(date))}';
  }

  Widget _card(Map<String, dynamic> session) {
    final end = DateTime.tryParse(session['ends_at'] as String? ?? '');
    final closed = session['cancelled'] == true ||
        end == null ||
        !end.isAfter(DateTime.now());
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(session['title'] as String,
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text('${session['expert_name']} · ${session['credentials']}'),
                  Text(session['description'] as String),
                  Text(
                      '${_date(session['starts_at'] as String)}\n${_date(session['ends_at'] as String)}'),
                  Text(session['cancelled'] == true
                      ? tr('Cancelled', 'منسوخ')
                      : closed
                          ? tr('Closed', 'بند')
                          : tr('Questions open until the session ends',
                              'نشست کے اختتام تک سوال بھیج سکتے ہیں')),
                  TextButton(
                      onPressed: _loading
                          ? null
                          : () async {
                              if (!_current) return;
                              await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => CommunityScreen(
                                          service: widget.service,
                                          sessionId: session['id'] as String,
                                          sessionClosed: closed)));
                              if (_current) await _load();
                            },
                      child: Text(closed
                          ? tr('Read discussion', 'گفتگو پڑھیں')
                          : tr('Open discussion', 'گفتگو کھولیں'))),
                  if (widget.admin && !closed)
                    OutlinedButton(
                        onPressed: _loading ? null : () => _cancel(session),
                        child: Text(tr('Cancel session', 'نشست منسوخ کریں'))),
                ])));
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    return Scaffold(
        appBar: AppBar(title: Text(tr('Expert Q&A', 'ماہر سے سوال')), actions: [
          IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: tr('Refresh', 'تازہ کریں'))
        ]),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(tr(
                          'Scheduled, moderated text discussions. Not individual medical care or an emergency service.',
                          'طے شدہ، زیر نگرانی تحریری گفتگو۔ یہ انفرادی علاج یا ہنگامی خدمت نہیں۔')),
                      if (widget.admin)
                        OutlinedButton(
                            onPressed: _loading ? null : _schedule,
                            child:
                                Text(tr('Schedule a session', 'نشست طے کریں'))),
                      if (_loading) const LinearProgressIndicator(),
                      if (_error != null)
                        CommunityNotice(
                            text: _error!,
                            action: TextButton(
                                onPressed: _load,
                                child: Text(tr('Retry', 'دوبارہ کوشش')))),
                      if (!_loading && _sessions.isEmpty && _error == null)
                        CommunityNotice(
                            text: tr('No sessions scheduled yet.',
                                'ابھی کوئی نشست طے نہیں۔')),
                      for (final session in _sessions) _card(session),
                    ]))));
  }
}

class _SessionEditor extends StatefulWidget {
  const _SessionEditor({required this.service, required this.accountId});
  final CommunityService service;
  final String? accountId;
  @override
  State<_SessionEditor> createState() => _SessionEditorState();
}

class _SessionEditorState extends State<_SessionEditor> {
  final _requestId = CommunityService.requestId();
  final _form = GlobalKey<FormState>();
  final _fields = {
    for (final key in ['title', 'description', 'expert_name', 'credentials'])
      key: TextEditingController()
  };
  DateTime _start = DateTime.now().add(const Duration(hours: 1));
  late DateTime _end = _start.add(const Duration(hours: 1));
  bool _verified = false, _saving = false, _uncertain = false;
  String? _error;
  bool get _current =>
      mounted && CommunityAccountScope.current(context, widget.accountId);
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String other) => ur ? other : en;
  @override
  void dispose() {
    for (final controller in _fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    if (!_current || _saving || _uncertain) return;
    final initial = start ? _start : _end;
    final date = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime.now().subtract(const Duration(days: 1)),
        lastDate: DateTime.now().add(const Duration(days: 365)));
    if (date == null || !mounted || !_current) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(initial));
    if (time == null || !_current) return;
    final value =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (start) {
        _start = value;
        _end = value.add(const Duration(hours: 1));
      } else {
        _end = value;
      }
    });
  }

  Future<void> _save() async {
    if (!_current || _saving || !_form.currentState!.validate()) return;
    if (!_verified ||
        !_start.isAfter(DateTime.now()) ||
        !_end.isAfter(_start) ||
        _end.difference(_start) > const Duration(hours: 8)) {
      setState(() => _error = tr(
          'Verify credentials and choose future times, with an end within eight hours of the start.',
          'اسناد کی تصدیق کریں اور مستقبل کا وقت چنیں۔ نشست آٹھ گھنٹے سے زیادہ نہ ہو۔'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.schedule({
        for (final entry in _fields.entries) entry.key: entry.value.text.trim(),
        'client_request_id': _requestId,
        'starts_at': _start.toUtc().toIso8601String(),
        'ends_at': _end.toUtc().toIso8601String()
      });
      if (mounted && _current) Navigator.pop(context, true);
    } catch (error) {
      if (_current) {
        setState(() {
          _error = error.toString();
          _uncertain = error is! CommunityException || error.deliveryUncertain;
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final labels = {
      'title': tr('Session title', 'نشست کا عنوان'),
      'description': tr('Description', 'تفصیل'),
      'expert_name': tr('Verified expert name', 'تصدیق شدہ ماہر کا نام'),
      'credentials': tr('Professional credentials', 'پیشہ ورانہ اسناد')
    };
    final minima = {
      'title': 3,
      'description': 5,
      'expert_name': 2,
      'credentials': 3
    };
    final maxima = {
      'title': 160,
      'description': 1500,
      'expert_name': 100,
      'credentials': 300
    };
    return PopScope(
        canPop: !_saving,
        child: CommunityDialog(
            title: Text(tr('Schedule expert Q&A', 'ماہر کی نشست طے کریں')),
            content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                    child: Form(
                        key: _form,
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (final entry in _fields.entries)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: TextFormField(
                                        controller: entry.value,
                                        enabled: !_saving && !_uncertain,
                                        maxLength: maxima[entry.key],
                                        maxLines:
                                            entry.key == 'description' ? 4 : 2,
                                        minLines: 1,
                                        validator: (value) =>
                                            (value?.trim().length ?? 0) <
                                                    minima[entry.key]!
                                                ? tr('Please add more detail.',
                                                    'کچھ مزید تفصیل شامل کریں۔')
                                                : null,
                                        decoration: InputDecoration(
                                            labelText: labels[entry.key]))),
                              Text(tr('Times use this device’s local timezone.',
                                  'وقت اس آلے کے مقامی ٹائم زون کے مطابق ہے۔')),
                              OutlinedButton(
                                  onPressed: _saving || _uncertain
                                      ? null
                                      : () => _pick(true),
                                  child: Text(
                                      '${tr('Starts', 'آغاز')}: ${_start.toLocal()}')),
                              OutlinedButton(
                                  onPressed: _saving || _uncertain
                                      ? null
                                      : () => _pick(false),
                                  child: Text(
                                      '${tr('Ends', 'اختتام')}: ${_end.toLocal()}')),
                              CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  value: _verified,
                                  onChanged: _saving || _uncertain
                                      ? null
                                      : (value) => setState(
                                          () => _verified = value == true),
                                  title: Text(tr(
                                      'I have verified this professional’s credentials.',
                                      'میں نے ماہر کی پیشہ ورانہ اسناد کی تصدیق کی ہے۔'))),
                              if (_saving) const LinearProgressIndicator(),
                              if (_error != null)
                                Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)),
                              if (_uncertain)
                                Text(tr(
                                    'Delivery is uncertain. Retry this exact session request; fields stay locked to avoid duplicate scheduling.',
                                    'بھیجنے کی تصدیق نہیں ہوئی۔ اسی نشست کی درخواست دوبارہ بھیجیں۔ دہری نشست سے بچنے کے لیے معلومات مقفل ہیں۔')),
                            ])))),
            actions: [
              TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: Text(tr('Close', 'بند کریں'))),
              FilledButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_uncertain
                      ? tr('Retry scheduling', 'دوبارہ طے کریں')
                      : tr('Schedule', 'طے کریں')))
            ]));
  }
}
