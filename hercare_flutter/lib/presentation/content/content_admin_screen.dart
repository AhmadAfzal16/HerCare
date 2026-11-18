import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../services/content_admin_service.dart';
import '../../services/content_service.dart' show ContentService;

class ContentAdminGuard extends StatelessWidget {
  const ContentAdminGuard(
      {super.key, required this.accountId, required this.child});
  final String accountId;
  final Widget child;
  static bool current(BuildContext context, String id) {
    final auth = context.read<AuthProvider>();
    return auth.isAuthenticated &&
        auth.user?.id == id &&
        auth.user?.role == 'admin';
  }

  @override
  Widget build(BuildContext context) {
    context.watch<AuthProvider>();
    final ur = context.watch<LanguageProvider>().isUrdu;
    if (!current(context, accountId)) {
      return Scaffold(
          body: SafeArea(
              child: ListView(padding: const EdgeInsets.all(24), children: [
        Text(ur
            ? 'اکاؤنٹ یا اجازت بدل گئی ہے۔ انتظام دوبارہ کھولیں۔'
            : 'Your account or permissions changed. Reopen administration.'),
        TextButton(
            onPressed: () => Navigator.maybePop(context),
            child: Text(ur ? 'واپس' : 'Back')),
      ])));
    }
    return child;
  }
}

class ContentAdminScreen extends StatelessWidget {
  const ContentAdminScreen({super.key, this.service});
  final ContentAdminService? service;
  @override
  Widget build(BuildContext context) {
    final id = context.watch<AuthProvider>().user?.id;
    if (id == null) {
      return const Scaffold(body: Center(child: Icon(Icons.lock_outline)));
    }
    return ContentAdminGuard(
        accountId: id,
        child: _Catalog(
            key: ValueKey(id),
            accountId: id,
            service: service ?? ContentAdminService(accountId: id)));
  }
}

class _Catalog extends StatefulWidget {
  const _Catalog({super.key, required this.accountId, required this.service});
  final String accountId;
  final ContentAdminService service;
  @override
  State<_Catalog> createState() => _CatalogState();
}

class _CatalogState extends State<_Catalog> {
  final List<Map<String, dynamic>> _items = [];
  String _status = 'draft';
  String? _error;
  bool _loading = false, _more = false, _denied = false;
  int _generation = 0;
  bool get _current =>
      mounted && ContentAdminGuard.current(context, widget.accountId);
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String other) => ur ? other : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!_current || _loading) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _items.clear();
        _more = false;
      }
    });
    try {
      final page = await widget.service
          .list(status: _status, offset: more ? _items.length : 0);
      if (!_current || generation != _generation) return;
      final rows = (page['items'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map))
          .toList();
      setState(() {
        _items.addAll(rows);
        _more = rows.length == 30 && _items.length < 300;
      });
    } catch (error) {
      if (_current) {
        setState(() {
          _error = error is ContentAdminException
              ? error.message
              : tr('The catalog could not be refreshed. Please retry.',
                  'مواد دوبارہ حاصل نہیں ہو سکا۔ دوبارہ کوشش کریں۔');
          if (error is ContentAdminException && error.accessDenied) {
            _items.clear();
            _denied = true;
          }
        });
      }
    } finally {
      if (_current) setState(() => _loading = false);
    }
  }

  Future<void> _action(Future<dynamic> Function() action) async {
    if (_loading || !_current || _denied) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (_current) {
        setState(() {
          _error = error is ContentAdminException
              ? error.message
              : tr('This change was not confirmed. Refresh the catalog.',
                  'تبدیلی کی تصدیق نہیں ہوئی۔ فہرست دوبارہ کھولیں۔');
          if (error is ContentAdminException && error.accessDenied) {
            _items.clear();
            _denied = true;
          }
        });
      }
    } finally {
      if (_current) setState(() => _loading = false);
    }
    if (_current && !_denied && _error == null) await _load();
  }

  Future<void> _edit([Map<String, dynamic>? item]) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ContentAdminGuard(
                accountId: widget.accountId,
                child: _ContentEditor(
                    accountId: widget.accountId,
                    service: widget.service,
                    item: item))));
    if (_current) await _load();
  }

  Future<void> _review(Map<String, dynamic> item) async {
    final decision = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => ContentAdminGuard(
            accountId: widget.accountId, child: const _ReviewDialog()));
    if (!_current || decision == null) return;
    await _action(() => widget.service.review(
        item['id'] as String, {'version': item['version'], ...decision}));
  }

  Future<void> _archive(Map<String, dynamic> item) async {
    final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => ContentAdminGuard(
            accountId: widget.accountId,
            child: AlertDialog(
                scrollable: true,
                title: Text(tr(
                    'Archive this item?', 'یہ مواد محفوظ فہرست سے ہٹا دیں؟')),
                content: Text(tr(
                    'It will no longer be recommended. Existing offline copies expire on the device.',
                    'یہ مواد مزید تجویز نہیں ہوگا۔ پہلے محفوظ آف لائن نقول اپنی مدت پر ختم ہوں گی۔')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(tr('Cancel', 'منسوخ'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(tr('Archive', 'ہٹا دیں')))
                ])));
    if (_current && accepted == true) {
      await _action(() =>
          widget.service.archive(item['id'] as String, item['version'] as int));
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    return Scaffold(
        appBar: AppBar(title: Text(tr('Content catalog', 'مواد کا ذخیرہ'))),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(tr(
                  'Only reviewed, published items enter the live feed. Check source rights, Urdu wording and suitability; faith or music is not a treatment guarantee.',
                  'صرف جائزہ شدہ شائع مواد دکھایا جاتا ہے۔ حقوق، اردو متن اور موزونیت جانچیں۔ مذہبی مواد یا موسیقی علاج کی ضمانت نہیں۔')),
              const SizedBox(height: 12),
              Wrap(spacing: 10, runSpacing: 10, children: [
                FilledButton.icon(
                    onPressed: _loading || _denied ? null : _edit,
                    icon: const Icon(Icons.add),
                    label: Text(tr('New draft', 'نیا مسودہ'))),
                for (final status in [
                  'draft',
                  'reviewed',
                  'published',
                  'archived'
                ])
                  ChoiceChip(
                      label: Text(_statusLabel(status)),
                      selected: status == _status,
                      onSelected: _loading || _denied
                          ? null
                          : (_) {
                              setState(() => _status = status);
                              _load();
                            }),
              ]),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(_error!)),
              if (!_loading && _items.isEmpty)
                Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(tr(
                        'No items here. Add a draft or use the documented source import, then review it.',
                        'یہاں مواد نہیں ہے۔ مسودہ شامل کریں یا ماخذ سے درآمد کر کے جائزہ لیں۔'))),
              for (final item in _items)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                  (item[ur ? 'title_ur' : 'title_en'] ?? '')
                                      .toString(),
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text(
                                  (item[ur ? 'summary_ur' : 'summary_en'] ?? '')
                                      .toString()),
                              Text(
                                  '${item['category']} · ${item['format']} · v${item['version']}'),
                              if (item['source_name'] != null)
                                Text(item['source_name'].toString()),
                              Wrap(spacing: 8, runSpacing: 6, children: [
                                if (_status != 'archived') ...[
                                  TextButton(
                                      onPressed:
                                          _loading ? null : () => _edit(item),
                                      child: Text(tr('Read / edit draft',
                                          'پڑھیں / مسودہ بدلیں'))),
                                  if (_status == 'draft' ||
                                      _status == 'reviewed')
                                    TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () => _review(item),
                                        child: Text(tr('Review', 'جائزہ'))),
                                  if (_status == 'reviewed' ||
                                      _status == 'published')
                                    TextButton(
                                        onPressed: _loading
                                            ? null
                                            : () => _action(() => widget.service
                                                .publication(
                                                    item['id'] as String,
                                                    item['version'] as int,
                                                    _status != 'published')),
                                        child: Text(_status == 'published'
                                            ? tr('Withdraw', 'اشاعت واپس لیں')
                                            : tr('Publish', 'شائع کریں'))),
                                  TextButton(
                                      onPressed: _loading
                                          ? null
                                          : () => _archive(item),
                                      child: Text(tr('Archive', 'ہٹا دیں'))),
                                ] else
                                  TextButton(
                                      onPressed: _loading || _denied
                                          ? null
                                          : () => _action(() => widget.service
                                              .publication(
                                                  item['id'] as String,
                                                  item['version'] as int,
                                                  false)),
                                      child: Text(tr('Restore as draft',
                                          'مسودے کے طور پر بحال کریں'))),
                              ]),
                            ]))),
              if (_more)
                TextButton(
                    onPressed: _loading ? null : () => _load(more: true),
                    child: Text(tr('Load more', 'مزید دکھائیں'))),
            ])));
  }

  String _statusLabel(String value) => switch (value) {
        'draft' => tr('Drafts', 'مسودے'),
        'reviewed' => tr('Reviewed', 'جائزہ شدہ'),
        'published' => tr('Published', 'شائع شدہ'),
        _ => tr('Archived', 'ہٹایا گیا'),
      };
}

class _ReviewDialog extends StatefulWidget {
  const _ReviewDialog();
  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  final _note = TextEditingController(),
      _qualification = TextEditingController();
  bool _approved = false;
  @override
  void dispose() {
    _note.dispose();
    _qualification.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    return Dialog(
        child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(ur ? 'جائزے کا ریکارڈ' : 'Review record',
                      style: Theme.of(context).textTheme.titleLarge),
                  Text(ur
                      ? 'متن، ماخذ، حقوق اور موزونیت خود جانچیں۔ یہ خودکار تصدیق نہیں۔'
                      : 'Personally check text, source, rights and suitability. This is not automatic verification.'),
                  TextField(
                      key: const ValueKey('content-review-qualification'),
                      controller: _qualification,
                      maxLength: 200,
                      maxLines: 3,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: ur
                              ? 'آپ کی قابلیت یا ذمہ داری'
                              : 'Your qualification / review role')),
                  TextField(
                      key: const ValueKey('content-review-note'),
                      controller: _note,
                      maxLength: 1000,
                      maxLines: 5,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                          labelText: ur
                              ? 'ماخذ، ترجمے اور حقوق کے جائزے کی وجہ'
                              : 'Source, translation and rights review notes')),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(ur ? 'جائزہ منظور' : 'Approve review'),
                      value: _approved,
                      onChanged: (v) => setState(() => _approved = v)),
                  Text(ur
                      ? 'یہ آپ کا درج کردہ جائزہ ہے، قابلیت یا طبی افادیت کی آزاد تصدیق نہیں۔'
                      : 'This records your review; it is not independent verification of qualifications or clinical benefit.'),
                  Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(ur ? 'منسوخ' : 'Cancel')),
                    FilledButton(
                        key: const ValueKey('content-review-save'),
                        onPressed: _note.text.trim().length < 10 ||
                                _qualification.text.trim().length < 3
                            ? null
                            : () => Navigator.pop(context, {
                                  'decision': _approved
                                      ? 'approved'
                                      : 'changes_requested',
                                  'review_note': _note.text.trim(),
                                  'reviewer_qualification':
                                      _qualification.text.trim(),
                                }),
                        child: Text(ur ? 'جائزہ محفوظ کریں' : 'Save review')),
                  ]),
                ])));
  }
}

class _ContentEditor extends StatefulWidget {
  const _ContentEditor(
      {required this.accountId, required this.service, this.item});
  final String accountId;
  final ContentAdminService service;
  final Map<String, dynamic>? item;
  @override
  State<_ContentEditor> createState() => _ContentEditorState();
}

class _ContentEditorState extends State<_ContentEditor> {
  final _fields = <String, TextEditingController>{};
  late final String _requestId = ContentService.requestId();
  late String _category =
      widget.item?['category'] as String? ?? 'psychoeducation';
  late String _format = widget.item?['format'] as String? ?? 'article';
  late String _audience = widget.item?['audience'] as String? ?? 'both';
  late bool _religious = widget.item?['is_religious'] == true,
      _music = widget.item?['is_music'] == true;
  bool _saving = false, _uncertain = false, _denied = false;
  String? _error;
  bool get _current =>
      mounted && ContentAdminGuard.current(context, widget.accountId);
  static const _labels = {
    'title_en': ['English title', 'انگریزی عنوان'],
    'title_ur': ['Urdu title', 'اردو عنوان'],
    'summary_en': ['English summary', 'انگریزی خلاصہ'],
    'summary_ur': ['Urdu summary', 'اردو خلاصہ'],
    'body_en': ['English text', 'انگریزی متن'],
    'body_ur': ['Urdu text', 'اردو متن'],
    'media_url': ['HTTPS media link', 'میڈیا کا HTTPS لنک'],
    'source_url': ['Source link', 'ماخذ کا لنک'],
    'source_name': ['Publisher / source', 'ناشر یا ماخذ'],
    'license_name': ['Rights / licence', 'حقوق یا اجازت'],
    'attribution': [
      'Creator / translator attribution',
      'خالق یا مترجم کا حوالہ'
    ],
    'arabic_text': ['Exact Arabic text', 'اصل عربی متن'],
    'transliteration': ['Transliteration', 'رومن تلفظ'],
    'verse_reference': ['Surah:ayah reference', 'سورت اور آیت کا حوالہ'],
    'activity_type': ['Existing activity type', 'موجودہ سرگرمی کی قسم'],
    'activity_id': ['Existing activity ID', 'موجودہ سرگرمی کی شناخت'],
    'tags': ['Tags (comma-separated)', 'موضوعات، کاما سے الگ'],
    'duration_seconds': ['Duration in seconds', 'دورانیہ، سیکنڈ میں'],
    'priority': ['Editorial priority 0–100', 'ادارتی ترجیح صفر تا سو'],
    'review_after': [
      'Review expiry (ISO date/time)',
      'جائزے کی آخری تاریخ، ISO'
    ],
    'available_from': [
      'Available from (ISO, optional)',
      'ابتدائی وقت، اختیاری ISO'
    ],
    'available_until': [
      'Available until (ISO, optional)',
      'آخری وقت، اختیاری ISO'
    ],
  };
  @override
  void initState() {
    super.initState();
    for (final key in _labels.keys) {
      final value = widget.item?[key];
      _fields[key] = TextEditingController(
          text: key == 'tags' && value is List
              ? value.join(', ')
              : value?.toString() ?? '');
    }
  }

  @override
  void dispose() {
    for (final field in _fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || _denied || !_current) return;
    final ur = context.read<LanguageProvider>().isUrdu;
    final priorityText = _fields['priority']!.text.trim();
    final durationText = _fields['duration_seconds']!.text.trim();
    final priority = priorityText.isEmpty ? 0 : int.tryParse(priorityText);
    final duration = durationText.isEmpty ? null : int.tryParse(durationText);
    if (priority == null ||
        priority < 0 ||
        priority > 100 ||
        (durationText.isNotEmpty &&
            (duration == null || duration < 1 || duration > 7200))) {
      setState(() => _error = context.read<LanguageProvider>().isUrdu
          ? 'ترجیح صفر سے سو اور دورانیہ ایک سے ۷۲۰۰ سیکنڈ کے درمیان پورا عدد ہونا چاہیے۔'
          : 'Priority must be a whole number from 0 to 100; duration must be 1 to 7200 seconds.');
      return;
    }
    final data = <String, dynamic>{
      for (final entry in _fields.entries)
        if (!['tags', 'priority', 'duration_seconds'].contains(entry.key))
          entry.key:
              entry.value.text.trim().isEmpty ? null : entry.value.text.trim(),
      'category': _category,
      'format': _format,
      'audience': _audience,
      'is_religious':
          _religious || _category == 'quran' || _category == 'islamic',
      'is_music': _music,
      'tags': _fields['tags']!
          .text
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      // Clear fields that are incompatible with the selected format; hidden
      // values must not make a video-to-article edit impossible to save.
      if (_format != 'activity') ...{
        'activity_type': null,
        'activity_id': null
      },
      if (_format == 'article' || _format == 'activity') 'media_url': null,
      'priority': priority,
      'duration_seconds': duration,
      if (widget.item == null)
        'client_request_id': _requestId
      else
        'version': widget.item!['version'],
    };
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.item == null) {
        await widget.service.create(data);
      } else {
        await widget.service.update(widget.item!['id'] as String, data);
      }
      if (mounted && ContentAdminGuard.current(context, widget.accountId)) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      if (_current) {
        setState(() {
          _error = error is ContentAdminException
              ? error.message
              : ur
                  ? 'مسودہ محفوظ ہونے کی تصدیق نہیں ہوئی۔ دوبارہ کوشش کریں۔'
                  : 'The draft was not confirmed. Please retry.';
          _denied = error is ContentAdminException && error.accessDenied;
          _uncertain = error is! ContentAdminException ||
              error.statusCode == null ||
              error.statusCode! >= 500;
        });
      }
    } finally {
      if (_current) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    String tr(String en, String other) => ur ? other : en;
    final disabled = _saving || _uncertain || _denied;
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
            appBar: AppBar(title: Text(tr('Content draft', 'مواد کا مسودہ'))),
            body: ListView(padding: const EdgeInsets.all(20), children: [
              Text(tr(
                  'Saving an edit returns it to draft and removes it from recommendations until reviewed again.',
                  'تبدیلی محفوظ کرنے سے مواد دوبارہ مسودہ بنے گا۔ نئے جائزے تک تجویز نہیں ہوگا۔')),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              if (_uncertain)
                Text(tr(
                    'Saving is uncertain. Retry this exact draft; fields are locked. If the item changed, reopen it. Check the catalog before creating another copy.',
                    'محفوظ ہونے کی تصدیق نہیں۔ اسی مسودے کی دوبارہ کوشش کریں؛ متن بند ہے۔ مواد بدل چکا ہو تو دوبارہ کھولیں۔ دوسری نقل بنانے سے پہلے فہرست دیکھیں۔')),
              DropdownButtonFormField<String>(
                  key: const ValueKey('content-admin-category'),
                  initialValue: _category,
                  isExpanded: true,
                  decoration:
                      InputDecoration(labelText: tr('Category', 'زمرہ')),
                  items: [
                    'quran',
                    'islamic',
                    'soothing',
                    'psychoeducation',
                    'bonding',
                    'game',
                    'activity'
                  ]
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged:
                      disabled ? null : (v) => setState(() => _category = v!)),
              DropdownButtonFormField<String>(
                  key: const ValueKey('content-admin-format'),
                  initialValue: _format,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: tr('Format', 'صورت')),
                  items: ['article', 'audio', 'video', 'activity']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: disabled
                      ? null
                      : (v) => setState(() {
                            _format = v!;
                            if (_format == 'activity') _audience = 'mother';
                          })),
              DropdownButtonFormField<String>(
                  key: ValueKey('content-admin-audience-$_format'),
                  initialValue: _audience,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: tr('Audience', 'استعمال کنندہ')),
                  items: (_format == 'activity'
                          ? ['mother']
                          : ['mother', 'guardian', 'both'])
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged:
                      disabled ? null : (v) => setState(() => _audience = v!)),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _religious,
                  onChanged:
                      disabled ? null : (v) => setState(() => _religious = v),
                  title: Text(tr('Religious content', 'مذہبی مواد'))),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _music,
                  onChanged:
                      disabled ? null : (v) => setState(() => _music = v),
                  title: Text(tr('Contains music', 'موسیقی شامل ہے'))),
              for (final key in [
                'title_en',
                'title_ur',
                'summary_en',
                'summary_ur',
                // Quran translations are retained in these fields even when
                // the entry is audio, and must remain visible to a reviewer.
                if (_format == 'article' ||
                    _category == 'quran' ||
                    _fields['body_en']!.text.isNotEmpty ||
                    _fields['body_ur']!.text.isNotEmpty) ...[
                  'body_en',
                  'body_ur'
                ]
              ])
                _field(key, ur, disabled),
              if (_format == 'audio' || _format == 'video')
                _field('media_url', ur, disabled),
              for (final key in [
                'source_url',
                'source_name',
                'license_name',
                'attribution'
              ])
                _field(key, ur, disabled),
              if (_category == 'quran')
                for (final key in [
                  'arabic_text',
                  'transliteration',
                  'verse_reference'
                ])
                  _field(key, ur, disabled),
              if (_format == 'activity')
                for (final key in ['activity_type', 'activity_id'])
                  _field(key, ur, disabled),
              ExpansionTile(
                  title: Text(tr('Tags, timing and review expiry',
                      'موضوعات، اوقات اور جائزے کی مدت')),
                  children: [
                    for (final key in [
                      'tags',
                      'duration_seconds',
                      'priority',
                      'review_after',
                      'available_from',
                      'available_until'
                    ])
                      _field(key, ur, disabled),
                  ]),
              const SizedBox(height: 20),
              FilledButton(
                  key: const ValueKey('content-draft-save'),
                  onPressed: _saving || _denied ? null : _save,
                  child: Text(_saving
                      ? tr('Saving…', 'محفوظ ہو رہا ہے…')
                      : _uncertain
                          ? tr('Retry exact draft', 'اسی مسودے کی دوبارہ کوشش')
                          : tr('Save draft', 'مسودہ محفوظ کریں'))),
            ])));
  }

  Widget _field(String key, bool ur, bool disabled) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: TextField(
        key: ValueKey('content-admin-$key'),
        controller: _fields[key],
        enabled: !disabled,
        minLines: 1,
        maxLines: key.startsWith('body') ? 10 : 5,
        maxLength: _maximum(key),
        textDirection: key.endsWith('_ur') || key == 'arabic_text'
            ? TextDirection.rtl
            : TextDirection.ltr,
        decoration: InputDecoration(labelText: _labels[key]![ur ? 1 : 0]),
      ));

  int _maximum(String key) => switch (key) {
        'title_en' => 180,
        'title_ur' => 240,
        'summary_en' => 800,
        'summary_ur' => 1000,
        'body_en' => 16000,
        'body_ur' => 20000,
        'source_name' => 180,
        'license_name' => 300,
        'attribution' => 1000,
        'arabic_text' || 'transliteration' => 6000,
        'verse_reference' => 80,
        'activity_type' => 20,
        'activity_id' => 40,
        'priority' => 3,
        'duration_seconds' => 4,
        'tags' => 820,
        'review_after' || 'available_from' || 'available_until' => 64,
        _ => 2000,
      };
}
