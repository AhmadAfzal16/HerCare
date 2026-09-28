import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../data/models/community_models.dart';
import '../../services/community_service.dart';
import 'community_composer.dart';
import 'community_widgets.dart';

class CommunityEntryCard extends StatelessWidget {
  const CommunityEntryCard({super.key});
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
          child: ListTile(
        leading: const Icon(Icons.diversity_1_outlined),
        title: Text(context.watch<LanguageProvider>().isUrdu
            ? 'ساتھیوں کا حلقہ'
            : 'Peer community'),
        subtitle: const Text('A moderated space to share and support'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const CommunityScreen())),
      )));
}

/// One paginated view serves topics, personal threads, discussions and review.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen(
      {super.key,
      this.service,
      this.parentId,
      this.sessionId,
      this.moderation = false});
  final CommunityService? service;
  final String? parentId, sessionId;
  final bool moderation;
  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  late final CommunityService _service = widget.service ?? CommunityService();
  Map<String, dynamic>? _status;
  final List<CommunityPost> _posts = [];
  CommunityPost? _parent;
  String? _topic, _cursor, _error;
  bool _mine = false, _loading = false, _accepted = false;
  int _generation = 0;
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String other) => ur ? other : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loading || _cursor == null)) return;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await _service.status();
      CommunityPost? parent;
      CommunityPage? page;
      if (status['joined'] == true) {
        if (widget.parentId != null) {
          parent = await _service.detail(widget.parentId!);
        }
        page = widget.moderation
            ? await _service.queue(cursor: more ? _cursor : null)
            : widget.parentId != null
                ? await _service.comments(widget.parentId!,
                    cursor: more ? _cursor : null)
                : await _service.feed(
                    topic: _topic,
                    mine: _mine,
                    sessionId: widget.sessionId,
                    cursor: more ? _cursor : null);
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _status = status;
        _parent = parent;
        if (!more) _posts.clear();
        if (page != null) {
          final ids = _posts.map((p) => p.id).toSet();
          _posts.addAll(page.items.where((p) => !ids.contains(p.id)));
        }
        _cursor = page?.cursor;
      });
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      if (mounted) await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<String?> _reason(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: Text(title),
              content: SingleChildScrollView(
                  child: TextField(
                      controller: controller,
                      minLines: 2,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: const InputDecoration(
                          labelText: 'Reason (at least 3 characters)'))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel')),
                TextButton(
                    onPressed: () {
                      if (controller.text.trim().length >= 3) {
                        Navigator.pop(ctx, controller.text.trim());
                      }
                    },
                    child: const Text('Confirm'))
              ],
            ));
    // Dialog transition can still reference its controller until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
    return result;
  }

  Future<void> _action(CommunityPost post, String action) async {
    if (action == 'report') {
      final reason = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
                  title: Text(tr('Report reason', 'رپورٹ کی وجہ')),
                  children: [
                    for (final entry in {
                      'bullying': 'Bullying / ہراسانی',
                      'self_harm': 'Safety concern / تحفظ',
                      'spam': 'Spam / فضول مواد',
                      'privacy': 'Personal information / نجی معلومات',
                      'medical_advice':
                          'Unsafe medical advice / غیر محفوظ طبی مشورہ',
                      'other': 'Other / دیگر'
                    }.entries)
                      SimpleDialogOption(
                          onPressed: () => Navigator.pop(ctx, entry.key),
                          child: Text(entry.value))
                  ]));
      if (reason != null && mounted) {
        await _run(() => _service.report(post.id, reason));
      }
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text(action == 'delete'
                    ? tr('Delete this content?', 'یہ مواد حذف کریں؟')
                    : tr('Block this member?', 'اس رکن کو بلاک کریں؟')),
                content: Text(action == 'delete'
                    ? tr('This cannot be undone.', 'یہ واپس نہیں ہو سکتا۔')
                    : tr('You will no longer see each other’s content.',
                        'آپ ایک دوسرے کا مواد نہیں دیکھ سکیں گے۔')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(tr('Cancel', 'منسوخ'))),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(tr('Confirm', 'تصدیق')))
                ]));
    if (confirmed == true && mounted) {
      await _run(() => action == 'delete'
          ? _service.remove(post.id)
          : _service.block(post.authorId));
    }
  }

  Future<void> _compose() async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CommunityComposer(
                service: _service,
                urdu: ur,
                parentId: widget.parentId,
                sessionId: widget.sessionId,
                topic: _topic)));
    if (mounted) await _load();
  }

  Future<void> _blocks() async {
    try {
      final blocks = await _service.blocks();
      if (!mounted) return;
      final id = await showDialog<String>(
          context: context,
          builder: (ctx) => SimpleDialog(
              title: Text(tr('Blocked members', 'بلاک کیے گئے اراکین')),
              children: blocks.isEmpty
                  ? [
                      Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(tr('No blocked members.',
                              'کوئی بلاک شدہ رکن نہیں۔')))
                    ]
                  : [
                      for (final b in blocks)
                        SimpleDialogOption(
                            onPressed: () => Navigator.pop(ctx, b['id']),
                            child: Text(
                                '${b['alias']} — ${tr('Unblock', 'بلاک ہٹائیں')}'))
                    ]));
      if (id != null && mounted) {
        await _run(() => _service.block(id, active: false));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Widget _card(CommunityPost p, {bool parent = false}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CommunityPostCard(
            post: p,
            urdu: ur,
            busy: _loading,
            expanded: parent || widget.moderation,
            onAction: widget.moderation ? null : (action) => _action(p, action),
            onReaction: widget.moderation
                ? null
                : (kind) => _run(() =>
                    _service.react(p.id, kind, !p.myReactions.contains(kind))),
            onOpen: parent || widget.parentId != null || widget.moderation
                ? null
                : () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CommunityScreen(
                                service: _service, parentId: p.id)));
                    if (mounted) await _load();
                  }),
        if (widget.moderation) ...[
          Text('Triage: ${p.moderation}\nReports: ${p.reports.join(', ')}'),
          Wrap(spacing: 8, children: [
            for (final decision in ['publish', 'remove', 'suspend', 'restore'])
              OutlinedButton(
                  onPressed: _loading
                      ? null
                      : () async {
                          final reason =
                              await _reason('$decision content / member');
                          if (reason != null && mounted) {
                            await _run(() => decision == 'suspend' ||
                                    decision == 'restore'
                                ? _service.suspend(
                                    p.authorId, decision == 'suspend', reason)
                                : _service.review(p, decision, reason));
                          }
                        },
                  child: Text(decision))
          ]),
          const SizedBox(height: 20),
        ],
      ]);
  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final joined = _status?['joined'] == true;
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.moderation
                ? 'Moderation'
                : tr('Peer community', 'ساتھیوں کا حلقہ')),
            actions: [
              IconButton(
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Refresh'),
              if (joined)
                PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'blocks') _blocks();
                      if (v == 'review') {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CommunityScreen(
                                    service: _service, moderation: true)));
                      }
                      if (v == 'sessions') {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => CommunitySessions(
                                    service: _service,
                                    admin: _status?['is_moderator'] == true)));
                      }
                    },
                    itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'sessions',
                              child: Text('Expert Q&A / ماہر سے سوال')),
                          const PopupMenuItem(
                              value: 'blocks',
                              child: Text('Blocked members / بلاک اراکین')),
                          if (_status?['is_moderator'] == true)
                            const PopupMenuItem(
                                value: 'review',
                                child: Text('Moderation queue'))
                        ]),
            ]),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (_loading) const LinearProgressIndicator(),
                      if (_error != null)
                        CommunityNotice(
                            text: _error!,
                            action: TextButton(
                                onPressed: () => _load(),
                                child: Text(tr('Retry', 'دوبارہ کوشش')))),
                      if (_status != null && !joined) ...[
                        Text(
                            tr('A gentle space, with clear boundaries',
                                'محفوظ گفتگو کے لیے اصول'),
                            style: Theme.of(context).textTheme.headlineSmall),
                        const SizedBox(height: 16),
                        Text(tr(
                            'An anonymous alias hides your name from other members, not from authorised moderators. Never share names, contacts, journal entries or other people’s information. Be kind: no harassment, advertising, dangerous advice or instructions for self-harm. Share medication experiences, not prescriptions. Every post and reply needs moderator approval. Report concerns or block members. This is peer support, not medical care or an emergency service.',
                            'دوسرے اراکین کو آپ کا اصل نام نہیں دکھایا جاتا، مجاز نگران آپ کی شناخت جان سکتے ہیں۔ نام، رابطے، نجی ڈائری یا دوسروں کی معلومات نہ بانٹیں۔ ہراسانی، اشتہار، خطرناک مشورے اور خود کو نقصان کی ہدایات منع ہیں۔ ادویات کے تجربات بانٹیں، نسخے نہیں۔ ہر پیغام کا جائزہ ضروری ہے۔ مسئلے کی رپورٹ کریں یا رکن کو بلاک کریں۔ یہ طبی یا ہنگامی خدمت نہیں۔')),
                        CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _accepted,
                            onChanged: _loading
                                ? null
                                : (v) => setState(() => _accepted = v ?? false),
                            title: Text(tr('I agree to these community rules',
                                'میں ان اصولوں سے متفق ہوں'))),
                        FilledButton(
                            onPressed: _accepted && !_loading
                                ? () => _run(() => _service
                                    .join(_status!['rules_version'] as String))
                                : null,
                            child: Text(
                                tr('Join the circle', 'حلقے میں شامل ہوں'))),
                      ],
                      if (joined) ...[
                        Text(
                            '${tr('Your community name', 'حلقے میں آپ کا نام')}: ${_status!['alias']}'),
                        const SizedBox(height: 12),
                        if (widget.parentId == null && !widget.moderation) ...[
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            ChoiceChip(
                                label: Text(tr('All topics', 'تمام موضوعات')),
                                selected: _topic == null,
                                onSelected: _loading
                                    ? null
                                    : (_) {
                                        _topic = null;
                                        _load();
                                      }),
                            for (final t in communityTopics.keys)
                              ChoiceChip(
                                  label: Text(communityTopic(t, ur)),
                                  selected: _topic == t,
                                  onSelected: _loading
                                      ? null
                                      : (_) {
                                          _topic = t;
                                          _load();
                                        }),
                            FilterChip(
                                label: Text(tr('My posts', 'میری پوسٹس')),
                                selected: _mine,
                                onSelected: _loading
                                    ? null
                                    : (v) {
                                        _mine = v;
                                        _load();
                                      })
                          ]),
                          const SizedBox(height: 12),
                        ],
                        if (!widget.moderation &&
                            (widget.parentId == null ||
                                _parent?.status == 'published'))
                          FilledButton.icon(
                              onPressed: _loading ? null : _compose,
                              icon: const Icon(Icons.edit_outlined),
                              label: Text(widget.parentId == null
                                  ? tr('Share an experience',
                                      'اپنا تجربہ بانٹیں')
                                  : tr('Write a reply', 'جواب لکھیں'))),
                        const SizedBox(height: 16),
                        if (_parent != null) _card(_parent!, parent: true),
                        for (final post in _posts) _card(post),
                        if (!_loading && _posts.isEmpty)
                          CommunityNotice(
                              text: tr(
                                  'No messages here yet. New messages appear after review.',
                                  'ابھی کوئی پیغام نہیں۔ نئے پیغامات جائزے کے بعد ظاہر ہوں گے۔')),
                        if (_cursor != null)
                          OutlinedButton(
                              onPressed:
                                  _loading ? null : () => _load(more: true),
                              child: Text(tr('Load more', 'مزید دیکھیں'))),
                      ],
                    ]))));
  }
}

class CommunitySessions extends StatefulWidget {
  const CommunitySessions(
      {super.key, required this.service, required this.admin});
  final CommunityService service;
  final bool admin;
  @override
  State<CommunitySessions> createState() => _CommunitySessionsState();
}

class _CommunitySessionsState extends State<CommunitySessions> {
  late Future<List<Map<String, dynamic>>> _future = widget.service.sessions();
  void reload() => setState(() => _future = widget.service.sessions());
  Future<void> schedule() async {
    final fields = {
      for (final k in [
        'title',
        'description',
        'expert_name',
        'credentials',
        'starts_at',
        'ends_at'
      ])
        k: TextEditingController()
    };
    String? error;
    bool saving = false;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                  title: const Text('Schedule verified expert Q&A'),
                  content: SizedBox(
                      width: 450,
                      child: SingleChildScrollView(
                          child:
                              Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text(
                            'Verify professional credentials before scheduling. Dates: YYYY-MM-DDTHH:mm with timezone (for example +05:00).'),
                        for (final e in fields.entries)
                          TextField(
                              controller: e.value,
                              enabled: !saving,
                              decoration: InputDecoration(labelText: e.key)),
                        if (error != null) Text(error!),
                      ]))),
                  actions: [
                    TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                update(() => saving = true);
                                try {
                                  await widget.service.schedule(fields.map(
                                      (k, v) => MapEntry(k, v.text.trim())));
                                  if (ctx.mounted) Navigator.pop(ctx);
                                } catch (e) {
                                  if (ctx.mounted) {
                                    update(() {
                                      error = e.toString();
                                      saving = false;
                                    });
                                  }
                                }
                              },
                        child: const Text('Schedule'))
                  ],
                )));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final c in fields.values) {
        c.dispose();
      }
    });
    if (mounted) reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Expert Q&A / ماہر سے سوال'), actions: [
        IconButton(onPressed: reload, icon: const Icon(Icons.refresh))
      ]),
      body: SafeArea(
          child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (context, snapshot) =>
                  ListView(padding: const EdgeInsets.all(16), children: [
                    const Text(
                        'Scheduled, moderated text discussions. Not individual medical care. / یہ انفرادی طبی علاج نہیں۔'),
                    if (widget.admin)
                      OutlinedButton(
                          onPressed: schedule,
                          child: const Text('Schedule a session')),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const LinearProgressIndicator(),
                    if (snapshot.hasError)
                      CommunityNotice(text: snapshot.error.toString()),
                    if (snapshot.hasData && snapshot.data!.isEmpty)
                      const CommunityNotice(
                          text:
                              'No sessions scheduled yet. / ابھی کوئی نشست طے نہیں۔'),
                    for (final s in snapshot.data ?? <Map<String, dynamic>>[])
                      Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Text(s['title'] as String,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    Text(
                                        '${s['expert_name']} · ${s['credentials']}'),
                                    Text(s['description'] as String),
                                    if (s['cancelled'] == true)
                                      const Text('Cancelled / منسوخ'),
                                    Text(
                                        '${DateTime.parse(s['starts_at'] as String).toLocal()} – ${DateTime.parse(s['ends_at'] as String).toLocal()}'),
                                    TextButton(
                                        onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (_) => CommunityScreen(
                                                    service: widget.service,
                                                    sessionId:
                                                        s['id'] as String))),
                                        child: const Text(
                                            'Open discussion / گفتگو کھولیں')),
                                  ]))),
                  ]))));
}
