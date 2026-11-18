import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/language_provider.dart';
import '../shared/hc_widgets.dart';
import '../../data/models/community_models.dart';
import '../../services/community_service.dart';
import 'community_composer.dart';
import 'community_widgets.dart';
import 'community_account_scope.dart';
import 'community_members.dart';
import 'community_sessions.dart';
export 'community_sessions.dart' show CommunitySessions;

class CommunityEntryCard extends StatelessWidget {
  const CommunityEntryCard({super.key});
  @override
  Widget build(BuildContext context) {
    final urdu = context.watch<LanguageProvider>().isUrdu;
    final theme = Theme.of(context);
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: HcCard(
            padding: const EdgeInsets.all(16),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const CommunityScreen())),
            child: Row(children: [
              const HcIconBadge(
                  icon: Icons.diversity_1_rounded,
                  color: AppColors.secondary,
                  background: AppColors.secondaryContainer,
                  size: 48),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(urdu ? 'ساتھیوں کا حلقہ' : 'Peer community',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text(
                        urdu
                            ? 'بات کرنے اور مدد کا محفوظ حلقہ'
                            : 'A moderated space to share and support',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: context.hcTextSecondary)),
                  ])),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: context.hcTextHint),
            ])));
  }
}

/// One paginated view serves topics, personal threads, discussions and review.
class CommunityScreen extends StatelessWidget {
  const CommunityScreen(
      {super.key,
      this.service,
      this.parentId,
      this.sessionId,
      this.sessionClosed = false,
      this.moderation = false});
  final CommunityService? service;
  final String? parentId, sessionId;
  final bool moderation, sessionClosed;
  @override
  Widget build(BuildContext context) => CommunityAccountScope(
      builder: (context, accountId) => _CommunityView(
          service: service ?? CommunityService(accountId: accountId),
          accountId: accountId,
          parentId: parentId,
          sessionId: sessionId,
          sessionClosed: sessionClosed,
          moderation: moderation));
}

class _CommunityView extends StatefulWidget {
  const _CommunityView(
      {required this.service,
      required this.accountId,
      this.parentId,
      this.sessionId,
      this.sessionClosed = false,
      this.moderation = false});
  final CommunityService service;
  final String? accountId, parentId, sessionId;
  final bool moderation, sessionClosed;
  @override
  State<_CommunityView> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<_CommunityView> {
  late final CommunityService _service = widget.service;
  Map<String, dynamic>? _status;
  final List<CommunityPost> _posts = [];
  CommunityPost? _parent;
  Map<String, dynamic>? _moderationStatus;
  String? _topic, _cursor, _error;
  bool _mine = false, _loading = false, _accepted = false;
  int _generation = 0;
  static const _maxLoaded = 200;
  bool get _current =>
      mounted && CommunityAccountScope.current(context, widget.accountId);
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String other) => ur ? other : en;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!_current || (more && (_loading || _cursor == null))) return;
    final generation = ++_generation;
    final cursor = more ? _cursor : null;
    final topic = _topic;
    final mine = _mine;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _posts.clear();
        _parent = null;
        _cursor = null;
      }
    });
    try {
      final status = await _service.status();
      if (!_current || generation != _generation) return;
      CommunityPost? parent;
      CommunityPage? page;
      if (status['joined'] == true) {
        if (widget.moderation) {
          _moderationStatus = await _service.moderationStatus();
          if (!_current || generation != _generation) return;
        }
        if (widget.parentId != null) {
          parent = await _service.detail(widget.parentId!);
          if (!_current || generation != _generation) return;
        }
        page = widget.moderation
            ? await _service.queue(cursor: cursor)
            : widget.parentId != null
                ? await _service.comments(widget.parentId!, cursor: cursor)
                : await _service.feed(
                    topic: topic,
                    mine: mine,
                    includeReplies: mine,
                    sessionId: widget.sessionId,
                    cursor: cursor);
      }
      if (!_current || generation != _generation) return;
      setState(() {
        if (status['joined'] == true ||
            _status?['rules_version'] != status['rules_version']) {
          _accepted = false;
        }
        _status = status;
        _parent = parent;
        if (!more || status['joined'] != true) _posts.clear();
        if (page != null) {
          final ids = _posts.map((p) => p.id).toSet();
          _posts.addAll(page.items
              .where((p) => !ids.contains(p.id))
              .take(_maxLoaded - _posts.length));
        }
        _cursor = _posts.length >= _maxLoaded ? null : page?.cursor;
      });
    } catch (e) {
      if (_current && generation == _generation) {
        setState(() {
          _error = e.toString();
          if (e is CommunityException && e.unavailable) {
            _posts.clear();
            _parent = null;
            _cursor = null;
            _status = null;
            _accepted = false;
          }
        });
      }
    } finally {
      if (_current && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!_current || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
      if (_current) await _load();
    } catch (e) {
      if (_current) {
        setState(() {
          _error = e.toString();
          _loading = false;
          if (e is CommunityException && e.unavailable) {
            _posts.clear();
            _parent = null;
            _status = null;
            _accepted = false;
            _cursor = null;
          }
        });
      }
    }
  }

  Widget _dialog(Widget child) => CommunityAccountScope(
      accountId: widget.accountId, builder: (_, __) => child);

  Future<String?> _reason(String title) => showDialog<String>(
      context: context,
      builder: (_) => _dialog(CommunityReasonDialog(title: title)));

  Future<void> _action(CommunityPost post, String action) async {
    if (!_current || _loading) return;
    if (action == 'report') {
      final reason = await showDialog<String>(
          context: context,
          builder: (ctx) => _dialog(SimpleDialog(
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
                  ])));
      if (reason != null && _current) {
        await _run(() => _service.report(post.id, reason));
      }
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => _dialog(CommunityDialog(
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
                ])));
    if (confirmed == true && _current) {
      await _run(() => action == 'delete'
          ? _service.remove(post.id)
          : _service.block(post.authorId));
    }
  }

  Future<void> _compose() async {
    if (!_current || _loading) return;
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CommunityComposer(
                service: _service,
                accountId: widget.accountId,
                urdu: ur,
                parentId: widget.parentId,
                sessionId: widget.sessionId ?? _parent?.sessionId,
                topic: _parent?.topic ?? _topic)));
    if (_current) await _load();
  }

  Future<void> _blocks() async {
    if (!_current || _loading) return;
    try {
      final blocks = await _service.blocks();
      if (!mounted || !_current) return;
      final id = await showDialog<String>(
          context: context,
          builder: (ctx) => _dialog(SimpleDialog(
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
                    ])));
      if (id != null && _current) {
        await _run(() => _service.block(id, active: false));
      }
    } catch (e) {
      if (_current) setState(() => _error = e.toString());
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
            onOpen: parent ||
                    widget.parentId != null ||
                    (widget.moderation && p.status != 'published')
                ? null
                : () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CommunityScreen(
                                service: _service,
                                parentId: p.parentId ?? p.id,
                                sessionClosed: p.sessionClosed)));
                    if (_current) await _load();
                  }),
        if (widget.moderation) ...[
          _triage(p),
          if (!p.canPublish)
            Text(tr(
                'Publication is blocked: member or parent discussion is unavailable. You may remove this content.',
                'رکن یا اصل گفتگو دستیاب نہ ہونے کی وجہ سے اشاعت بند ہے۔ مواد ہٹا سکتے ہیں۔')),
          Wrap(spacing: 8, children: [
            for (final decision in ['publish', 'remove', 'suspend', 'restore'])
              OutlinedButton(
                  onPressed: _loading ||
                          (decision == 'publish' &&
                              (!p.canPublish ||
                                  (_moderationStatus?['required'] == true &&
                                      _moderationStatus?['ready'] != true)))
                      ? null
                      : () async {
                          final reason =
                              await _reason(_decisionLabel(decision));
                          if (reason != null && _current) {
                            await _run(() => decision == 'suspend' ||
                                    decision == 'restore'
                                ? _service.suspend(
                                    p.authorId, decision == 'suspend', reason)
                                : _service.review(p, decision, reason));
                          }
                        },
                  child: Text(_decisionLabel(decision)))
          ]),
          const SizedBox(height: 20),
        ],
      ]);
  String _decisionLabel(String decision) => switch (decision) {
        'publish' => tr('Approve publication', 'شائع کرنے کی اجازت'),
        'remove' => tr('Remove content', 'مواد ہٹائیں'),
        'suspend' => tr('Suspend member', 'رکن معطل کریں'),
        _ => tr('Restore member', 'رکن بحال کریں'),
      };
  Widget _triage(CommunityPost post) {
    final data = post.moderation;
    final scores = data['scores'] is Map ? data['scores'] as Map : const {};
    final flags = data['flags'] is List ? data['flags'] as List : const [];
    final labels = {
      'self_harm': tr('Safety concern', 'تحفظ کی تشویش'),
      'bullying': tr('Bullying', 'ہراسانی'),
      'spam': tr('Spam', 'فضول مواد'),
      'medical_advice': tr('Medical advice', 'طبی مشورہ'),
      'support': tr('Supportive content', 'حوصلہ افزا مواد'),
      'privacy_or_link':
          tr('Personal information or link', 'نجی معلومات یا لنک'),
      'abuse_or_spam': tr('Abuse or spam', 'ہراسانی یا فضول مواد'),
    };
    return ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title:
            Text(tr('Review hints and reports', 'جائزے کے اشارے اور رپورٹس')),
        childrenPadding: const EdgeInsets.only(bottom: 12),
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(tr(
                'Triage hints are not clinical probabilities or a diagnosis. Read the full content before deciding.',
                'یہ اشارے طبی احتمال یا تشخیص نہیں۔ فیصلہ کرنے سے پہلے پورا مواد پڑھیں۔')),
            Text(
                '${tr('Rule flags', 'اصولوں کے اشارے')}: ${flags.isEmpty ? tr('None detected', 'کوئی اشارہ نہیں ملا') : flags.map((v) => labels[v] ?? v).join(', ')}'),
            Text(
                '${tr('AI triage', 'خودکار جائزہ')}: ${data['ai'] == 'available' ? tr('Available', 'دستیاب') : tr('Unavailable — check readiness', 'دستیاب نہیں — نظام جانچیں')}'),
            for (final key in [
              'self_harm',
              'bullying',
              'spam',
              'medical_advice',
              'support'
            ])
              if (scores[key] is num)
                Text(
                    '${labels[key]}: ${(scores[key] as num).toStringAsFixed(2)}'),
            if (data['model_version'] is String)
              Text(
                  '${tr('Model version', 'ماڈل کا ورژن')}: ${data['model_version']}'),
            Text(
                '${tr('Reports', 'رپورٹس')}: ${post.reports.isEmpty ? tr('None', 'کوئی نہیں') : post.reports.map((v) => labels[v] ?? v).join(', ')}'),
          ])
        ]);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final joined = _status?['joined'] == true;
    return Scaffold(
        appBar: AppBar(
            title: Text(
                widget.moderation
                    ? tr('Moderation', 'نگرانی')
                    : tr('Peer community', 'ساتھیوں کا حلقہ'),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                  onPressed: _loading ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                  tooltip: tr('Refresh', 'تازہ کریں')),
              if (joined)
                PopupMenuButton<String>(
                    onSelected: (v) {
                      if (!_current || _loading) return;
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
                      if (v == 'members') {
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) =>
                                    CommunityMembers(service: _service)));
                      }
                    },
                    itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'sessions',
                              child: Text(tr('Expert Q&A', 'ماہر سے سوال'))),
                          PopupMenuItem(
                              value: 'blocks',
                              child:
                                  Text(tr('Blocked members', 'بلاک اراکین'))),
                          if (_status?['is_moderator'] == true) ...[
                            PopupMenuItem(
                                value: 'review',
                                child: Text(
                                    tr('Moderation queue', 'جائزے کی فہرست'))),
                            PopupMenuItem(
                                value: 'members',
                                child: Text(
                                    tr('Manage members', 'اراکین کی نگرانی'))),
                          ]
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
                      if (widget.moderation && _moderationStatus != null)
                        CommunityNotice(
                            text: tr(
                                'AI provides triage hints only. Every post and reply still needs human review. Check AI readiness and arrange moderator staffing before launch.',
                                'خودکار نظام صرف جائزے کے اشارے دیتا ہے۔ ہر پوسٹ اور جواب کو انسانی جائزہ درکار ہے۔ اجرا سے پہلے نظام اور نگرانوں کی دستیابی جانچیں۔')),
                      if (widget.moderation && _moderationStatus != null)
                        Text(
                            '${tr('AI availability', 'خودکار نظام کی دستیابی')}: ${_moderationStatus!['ready'] == true ? tr('Ready', 'دستیاب') : tr('Unavailable', 'دستیاب نہیں')}'),
                      if (widget.moderation &&
                          _moderationStatus?['required'] == true &&
                          _moderationStatus?['ready'] != true)
                        Text(tr(
                            'Publication is paused until required AI triage is available. You can still review, report and remove content.',
                            'ضروری خودکار جائزہ دستیاب ہونے تک اشاعت رکی ہوئی ہے۔ جائزہ لے سکتے ہیں اور مواد ہٹا سکتے ہیں۔')),
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
                        if (widget.sessionClosed ||
                            _parent?.sessionClosed == true)
                          CommunityNotice(
                              text: tr(
                                  'This Q&A is closed. You can read approved discussions but cannot submit new messages.',
                                  'یہ نشست بند ہے۔ منظور شدہ گفتگو پڑھ سکتے ہیں، نیا پیغام نہیں بھیج سکتے۔')),
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
                            !widget.sessionClosed &&
                            _parent?.sessionClosed != true &&
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
                        if (_posts.length >= _maxLoaded)
                          Text(tr(
                              'Showing 200 messages. Choose a topic or refresh to view recent content.',
                              'دو سو پیغامات دکھائے گئے ہیں۔ تازہ مواد کے لیے موضوع چنیں یا تازہ کریں۔')),
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
