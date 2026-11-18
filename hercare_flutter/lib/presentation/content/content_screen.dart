import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/content_models.dart';
import '../../providers/content_provider.dart';
import '../../providers/language_provider.dart';
import 'content_actions.dart';
import 'content_widgets.dart';

class ContentScreen extends StatelessWidget {
  const ContentScreen(
      {super.key,
      this.initialItemId,
      this.initialCategory,
      this.initialSaved = false});
  final String? initialItemId;
  final String? initialCategory;
  final bool initialSaved;
  @override
  Widget build(BuildContext context) => ContentAccountScope(
      child: _ContentPage(
          initialItemId: initialItemId,
          initialCategory: initialCategory,
          initialSaved: initialSaved));
}

class _ContentPage extends StatefulWidget {
  const _ContentPage(
      {this.initialItemId, this.initialCategory, required this.initialSaved});
  final String? initialItemId;
  final String? initialCategory;
  final bool initialSaved;
  @override
  State<_ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends State<_ContentPage>
    with WidgetsBindingObserver {
  Timer? _timer;
  String? _language, _category;
  int? _signalRevision;
  late bool _savedOnly;
  bool _foreground = true, _initialOpened = false;
  @override
  void initState() {
    super.initState();
    _savedOnly = widget.initialSaved;
    if (ContentItem.categories.contains(widget.initialCategory)) {
      _category = widget.initialCategory;
    }
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = context.watch<LanguageProvider>().isUrdu ? 'ur' : 'en';
    final revision = context.watch<ContentProvider>().signalRevision;
    if (next != _language || revision != _signalRevision) {
      _language = next;
      _signalRevision = revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh(force: true);
      });
    }
  }

  bool get _visible =>
      mounted && _foreground && (ModalRoute.of(context)?.isCurrent ?? true);
  Future<void> _refresh({bool force = false}) async {
    _timer?.cancel();
    if (!_visible) {
      _schedule();
      return;
    }
    final provider = context.read<ContentProvider>();
    await provider.load(
        language: _language ?? 'en', savedOnly: _savedOnly, force: force);
    if (!mounted) return;
    if (!_savedOnly) await provider.loadLive(language: _language ?? 'en');
    if (!mounted) return;
    if (!_initialOpened && widget.initialItemId != null) {
      _initialOpened = true;
      await _open(widget.initialItemId!);
    }
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!mounted || !_foreground) return;
    _timer = Timer(context.read<ContentProvider>().refreshInterval, _refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refresh(force: true);
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _open(String id, {String? reason}) async {
    final provider = context.read<ContentProvider>(),
        owner = context.read<ContentProvider>().accountId;
    _timer?.cancel();
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ContentAccountScope(
            child: _ContentDetailPage(id: id, reason: reason))));
    if (mounted && provider.accountId == owner && provider.canUseAccount) {
      await _refresh(force: true);
    }
  }

  Future<void> _preferences() async {
    _timer?.cancel();
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) =>
            const ContentAccountScope(child: _ContentPreferencesSheet()));
    if (mounted) _refresh(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<ContentProvider>();
    final items = provider
        .items(savedOnly: _savedOnly)
        .where((item) => _category == null || item.category == _category)
        .toList();
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
          backgroundColor: context.hcBg,
          title: Text(ur ? 'آپ کے لیے' : 'For you'),
          actions: [
            IconButton(
                onPressed: _preferences,
                tooltip: ur ? 'مواد کی پسند' : 'Content preferences',
                icon: const Icon(Icons.tune_rounded))
          ]),
      body: RefreshIndicator(
          onRefresh: () => _refresh(force: true),
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: context.isDark ? null : AppColors.heroGradient,
                    color: context.isDark ? context.hcSurface : null,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: Colors.white
                              .withValues(alpha: context.isDark ? 0.1 : 0.8),
                          borderRadius: BorderRadius.circular(16)),
                      child: const Icon(Icons.auto_awesome_rounded,
                          color: AppColors.primary),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                          provider.role == 'guardian'
                              ? (ur
                                  ? 'سننے، سمجھنے اور گھر میں تعاون کے لیے رہنمائی۔'
                                  : 'Guidance for listening, understanding and supporting at home.')
                              : (ur
                                  ? 'مختصر رہنمائی، سکون اور ہلکی مشقیں۔ صرف اپنی پسند کا مواد چنیں۔'
                                  : 'Small moments of learning, calm and gentle activity. Choose what feels right for you.'),
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: context.isDark
                                  ? context.hcTextPrimary
                                  : AppColors.textPrimary,
                              fontWeight: FontWeight.w600)),
                    ),
                  ]),
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 10, runSpacing: 6, children: [
                  ChoiceChip(
                      label: Text(ur ? 'تجاویز' : 'Recommended'),
                      selected: !_savedOnly,
                      onSelected: (_) {
                        setState(() => _savedOnly = false);
                        _refresh(force: true);
                      }),
                  ChoiceChip(
                      label: Text(ur ? 'محفوظ' : 'Saved'),
                      avatar: const Icon(Icons.bookmark_outline, size: 18),
                      selected: _savedOnly,
                      onSelected: (_) {
                        setState(() => _savedOnly = true);
                        _refresh(force: true);
                      }),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  FilterChip(
                      label: Text(ur ? 'سب' : 'All'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null)),
                  ...ContentItem.categories.map((category) => FilterChip(
                      label: Text(contentCategory(category, ur)),
                      selected: _category == category,
                      onSelected: (_) => setState(() => _category =
                          _category == category ? null : category))),
                ]),
                const SizedBox(height: 16),
                if (provider.isLoading)
                  const LinearProgressIndicator(minHeight: 2),
                if (provider.isOffline)
                  _Notice(
                      icon: Icons.cloud_off_outlined,
                      text: ur
                          ? 'آف لائن: صرف پہلے سے محفوظ تحریر دکھائی گئی ہے۔ یہ تازہ یا طبی تجویز نہیں۔ نقول 24 گھنٹے بعد ختم ہو جاتی ہیں۔'
                          : 'Offline: only previously saved text is shown. This is not a fresh or clinical recommendation. Copies expire after 24 hours.'),
                if (provider.error != null && !provider.isOffline)
                  _Notice(
                      icon: Icons.info_outline,
                      text: ur
                          ? 'مواد تازہ نہیں ہو سکا۔ دوبارہ تازہ کریں۔'
                          : provider.error!),
                if (provider.safetyPriority) ...[
                  _Notice(
                      icon: Icons.health_and_safety_outlined,
                      text: ur
                          ? 'اس وقت فوری انسانی تعاون پہلے ہے۔ ویڈیوز، موسیقی یا کھیل فوری مدد کا متبادل نہیں۔'
                          : 'Immediate human support comes first right now. Videos, music and games are not a substitute for urgent help.'),
                  FilledButton.icon(
                      onPressed: () => context.push('/crisis'),
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: Text(ur ? 'فوری مدد' : 'Immediate support')),
                ] else if (items.isEmpty && !provider.isLoading) ...[
                  const SizedBox(height: 16),
                  Icon(Icons.auto_stories_outlined,
                      size: 40, color: context.hcTextSecondary),
                  const SizedBox(height: 12),
                  Text(
                      _savedOnly
                          ? (ur
                              ? 'ابھی کوئی دستیاب محفوظ مواد نہیں۔'
                              : 'No available saved content yet.')
                          : (ur
                              ? 'اس پسند کے لیے ابھی جائزہ شدہ مواد دستیاب نہیں۔ اپنی پسند بدلیں یا بعد میں تازہ کریں۔'
                              : 'No reviewed content matches this selection yet. Adjust your preferences or refresh later.'),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 10),
                  TextButton.icon(
                      onPressed: _preferences,
                      icon: const Icon(Icons.tune),
                      label: Text(
                          ur ? 'اپنی پسند چنیں' : 'Choose your preferences')),
                ] else if (!provider.safetyPriority)
                  ...items.map((item) => ContentTile(
                      item: item,
                      onTap: () => _open(item.id, reason: item.primaryReason))),
                if (!_savedOnly &&
                    _category == null &&
                    !provider.safetyPriority)
                  const LiveVideoSection(),
                const SizedBox(height: 18),
                _Notice(
                    icon: Icons.privacy_tip_outlined,
                    text: ur
                        ? 'مواد سرور کے جائزہ شدہ کیٹلاگ سے آتا ہے۔ اسلامی مواد اور موسیقی الگ الگ اختیاری ہیں۔ ویڈیو کی تصویر یوٹیوب سے لوڈ ہوتی ہے؛ ویڈیو صرف آپ کے انتخاب کے بعد کھلتی ہے۔ نجی گفتگو یا صحت کے اسکور انہیں نہیں بھیجے جاتے۔ ایپ صرف یہ گنتی رکھتی ہے کہ آپ نے کیا کھولا یا مکمل کیا، تاکہ تجاویز بہتر ہوں۔'
                        : 'Content comes from the reviewed server catalogue. Islamic content and music are separate choices. Video preview images load from YouTube; videos open only after you choose. Private conversations and health scores are never sent to them. The app counts what you open or finish, to improve suggestions.'),
              ])),
    );
  }
}

class _ContentDetailPage extends StatefulWidget {
  const _ContentDetailPage({required this.id, this.reason});
  final String id;

  /// The recommendation reason on the card she tapped, reported once.
  final String? reason;
  @override
  State<_ContentDetailPage> createState() => _ContentDetailPageState();
}

class _ContentDetailPageState extends State<_ContentDetailPage>
    with WidgetsBindingObserver {
  ContentDetail? _detail;
  String? _error;
  bool _loading = false, _foreground = true, _reasonSent = false;
  Timer? _timer;
  int _request = 0;
  // Engagement: time on this page while visible, and time away after
  // opening media in the YouTube app or browser.
  ContentProvider? _provider;
  final Stopwatch _onPage = Stopwatch();
  DateTime? _mediaOpenedAt;
  bool _completedSent = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refresh();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<ContentProvider>();
  }

  @override
  void dispose() {
    _request++;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _reportReading();
    super.dispose();
  }

  /// Article reading: send the seconds spent, and "completed" once she spent
  /// about as long as the text takes to read (capped at one minute).
  void _reportReading() {
    _onPage.stop();
    final item = _detail?.item, provider = _provider;
    if (item == null || provider == null || _detail!.offline) return;
    final seconds = _onPage.elapsed.inSeconds;
    if (seconds < 10) return;
    final text = item.bodyEn.isNotEmpty ? item.bodyEn : item.bodyUr;
    final words = text.split(RegExp(r'\s+')).length;
    final readSeconds = (words / 200 * 60 * .6).clamp(15, 60).round();
    final finished = item.format == 'article' && seconds >= readSeconds;
    provider.recordEngagement(
        item, finished && !_completedSent ? 'completed' : 'engaged',
        seconds: seconds.clamp(0, 7200));
  }

  /// Back from the YouTube app/browser: treat a long enough visit as finished.
  void _reportMediaReturn() {
    final openedAt = _mediaOpenedAt, item = _detail?.item;
    _mediaOpenedAt = null;
    if (openedAt == null || item == null || _provider == null) return;
    final away = DateTime.now().difference(openedAt).inSeconds.clamp(0, 7200);
    final duration = item.durationSeconds;
    final finished = away >= 60 &&
        (duration == null || away >= (duration * .5).clamp(60, 1800));
    if (finished && !_completedSent) {
      _completedSent = true;
      _provider!.recordEngagement(item, 'completed', seconds: away);
    } else if (away >= 10) {
      _provider!.recordEngagement(item, 'engaged', seconds: away);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _onPage.start();
      _reportMediaReturn();
      _refresh();
    } else {
      _onPage.stop();
      _timer?.cancel();
    }
  }

  Future<void> _refresh() async {
    _timer?.cancel();
    if (!mounted ||
        !_foreground ||
        !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final provider = context.read<ContentProvider>(),
        owner = context.read<ContentProvider>().accountId;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await provider.detail(widget.id,
          reason: _reasonSent ? null : widget.reason);
      if (!mounted || request != _request || provider.accountId != owner) {
        return;
      }
      _reasonSent = true;
      if (detail != null && !detail.offline && !_onPage.isRunning) {
        _onPage.start();
      }
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || request != _request || provider.accountId != owner) {
        return;
      }
      setState(() {
        _detail = null;
        _loading = false;
        _error =
            'This content is unavailable or could not be refreshed. Please retry.';
      });
    }
    if (mounted && request == _request && _foreground) {
      _timer = Timer(provider.refreshInterval, _refresh);
    }
  }

  Future<void> _change(
      Future<bool> Function(ContentProvider, ContentItem) action) async {
    final item = _detail?.item;
    if (item == null || _detail!.offline) return;
    final provider = context.read<ContentProvider>(),
        owner = context.read<ContentProvider>().accountId;
    final ur = context.read<LanguageProvider>().isUrdu;
    final accepted = await action(provider, item);
    if (!mounted || provider.accountId != owner) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accepted
            ? (ur ? 'محفوظ ہو گیا۔' : 'Your choice was saved.')
            : (ur
                ? 'تبدیلی کی تصدیق نہیں ہوئی۔ دوبارہ کوشش کریں۔'
                : 'This change was not confirmed. Please retry.'))));
    await _refresh();
  }

  Future<void> _launch({bool source = false}) async {
    final provider = context.read<ContentProvider>(),
        owner = context.read<ContentProvider>().accountId;
    final ur = context.read<LanguageProvider>().isUrdu;
    try {
      // Recheck publication/preferences immediately before leaving the app.
      final fresh = await provider.detail(widget.id);
      if (!mounted ||
          provider.accountId != owner ||
          fresh == null ||
          fresh.offline) {
        return;
      }
      final uri = source
          ? ContentActions.httpsLink(fresh.item.sourceUrl)
          : ContentActions.mediaLink(
              fresh.item.mediaUrl, provider.allowedMediaHosts);
      if (uri == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ur
                ? 'یہ بیرونی لنک ابھی دستیاب نہیں۔'
                : 'This external link is not available.')));
        return;
      }
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: Text(
                      ur ? 'بیرونی سائٹ کھولیں؟' : 'Open an external site?'),
                  content: SingleChildScrollView(
                      child: Text(ur
                          ? '${uri.host}\n\nیہ سائٹ اپنا ڈیٹا، اشتہارات یا کوکیز استعمال کر سکتی ہے۔ آپ کے نجی اسکور اور گفتگو اس لنک میں شامل نہیں ہیں۔ مواد علاج کا متبادل نہیں۔'
                          : '${uri.host}\n\nThis site may use its own data collection, ads or cookies. Your private scores and conversations are not included in this link. Content is not a substitute for care.')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(ur ? 'منسوخ' : 'Cancel')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(ur ? 'کھولیں' : 'Open'))
                  ]));
      if (!mounted || confirmed != true || provider.accountId != owner) return;
      final accepted = await provider.detail(widget.id);
      if (!mounted ||
          provider.accountId != owner ||
          accepted == null ||
          accepted.offline) {
        return;
      }
      final acceptedUri = source
          ? ContentActions.httpsLink(accepted.item.sourceUrl)
          : ContentActions.mediaLink(
              accepted.item.mediaUrl, provider.allowedMediaHosts);
      if (acceptedUri != uri) {
        await _refresh();
        return;
      }
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) throw StateError('No browser available');
      if (!source) {
        _mediaOpenedAt = DateTime.now();
        provider.recordEngagement(accepted.item, 'media_opened');
      }
    } catch (_) {
      if (mounted && provider.accountId == owner) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(ur
                ? 'لنک نہیں کھل سکا۔ انٹرنیٹ اور براؤزر چیک کریں۔'
                : 'The link could not be opened. Check your connection and browser.')));
      }
    } finally {
      if (mounted && provider.accountId == owner && _foreground) {
        _timer?.cancel();
        _timer = Timer(provider.refreshInterval, _refresh);
      }
    }
  }

  Future<void> _activity() async {
    final provider = context.read<ContentProvider>(),
        owner = context.read<ContentProvider>().accountId;
    try {
      final fresh = await provider.detail(widget.id);
      if (!mounted ||
          provider.accountId != owner ||
          fresh == null ||
          fresh.offline) {
        return;
      }
      final route =
          ContentActions.activityRoute(fresh.item, role: provider.role);
      if (route != null) {
        _timer?.cancel();
        await context.push(route);
        if (mounted && provider.accountId == owner) _refresh();
      }
    } catch (_) {
      if (mounted && provider.accountId == owner) _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<ContentProvider>();
    final detail = _detail, item = detail?.item;
    final allowed = item != null &&
        provider.preferences.allows(item) &&
        !provider.safetyPriority;
    return Scaffold(
        backgroundColor: context.hcBg,
        appBar: AppBar(
            backgroundColor: context.hcSurface,
            title: Text(ur ? 'مواد' : 'Content'),
            actions: [
              IconButton(
                  onPressed: _loading ? null : _refresh,
                  tooltip: ur ? 'تازہ کریں' : 'Refresh',
                  icon: const Icon(Icons.refresh))
            ]),
        body: ListView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 36),
            children: [
              if (_loading) const LinearProgressIndicator(minHeight: 2),
              if (provider.safetyPriority) ...[
                _Notice(
                    icon: Icons.health_and_safety_outlined,
                    text: ur
                        ? 'اس وقت فوری انسانی تعاون پہلے ہے۔ مواد فوری مدد کا متبادل نہیں۔'
                        : 'Immediate human support comes first right now. Content does not replace urgent help.'),
                FilledButton.icon(
                    onPressed: () => context.push('/crisis'),
                    icon: const Icon(Icons.health_and_safety_outlined),
                    label: Text(ur ? 'فوری مدد' : 'Immediate support')),
                const SizedBox(height: 14),
              ],
              if (_error != null || (!allowed && !_loading)) ...[
                const Icon(Icons.info_outline, size: 36),
                const SizedBox(height: 14),
                Text(ur
                    ? 'یہ مواد دستیاب نہیں یا اسے تازہ نہیں کیا جا سکا۔ دوبارہ کوشش کریں۔'
                    : _error ??
                        'This content is no longer available for your preferences.'),
                TextButton(
                    onPressed: _refresh,
                    child: Text(ur ? 'دوبارہ کوشش' : 'Retry')),
              ],
              if (allowed) ...[
                if (detail!.offline)
                  _Notice(
                      icon: Icons.cloud_off_outlined,
                      text: ur
                          ? 'پہلے سے محفوظ آف لائن نقل۔ تازہ دستیابی کی تصدیق نہیں ہو سکی۔ بیرونی میڈیا اور تبدیلیاں آن لائن ہونے پر دستیاب ہوں گی۔'
                          : 'Previously saved offline copy. Current availability could not be checked. External media and changes require a connection.'),
                if (!detail.offline &&
                    item.thumbnailUrl != null &&
                    ContentActions.mediaLink(
                            item.mediaUrl, provider.allowedMediaHosts) !=
                        null) ...[
                  ContentVideoPreview(
                      item: item,
                      onTap: _launch,
                      semanticLabel: ur ? 'ویڈیو چلائیں' : 'Play video'),
                  const SizedBox(height: 16),
                ],
                Text(contentCategory(item.category, ur),
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: AppColors.primary)),
                const SizedBox(height: 10),
                SelectableText(item.title(ur),
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (item.summary(ur).isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SelectableText(item.summary(ur),
                      style: Theme.of(context).textTheme.bodyLarge)
                ],
                if (item.arabicText.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Directionality(
                      textDirection: TextDirection.rtl,
                      child: SelectableText(item.arabicText,
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 25, height: 1.8)))
                ],
                if (item.verseReference.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText(item.verseReference,
                      style: Theme.of(context).textTheme.labelLarge)
                ],
                if (item.transliteration.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(ur ? 'تلفظ میں مدد' : 'Transliteration',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Directionality(
                      textDirection: TextDirection.ltr,
                      child: SelectableText(item.transliteration))
                ],
                if (item.body(ur).isNotEmpty) ...[
                  const SizedBox(height: 22),
                  SelectableText(item.body(ur),
                      style: Theme.of(context)
                          .textTheme
                          .bodyLarge
                          ?.copyWith(height: ur ? 2 : 1.65))
                ],
                if (item.reason(ur).isNotEmpty && !detail.offline) ...[
                  const SizedBox(height: 20),
                  _Notice(
                      icon: Icons.info_outline,
                      text:
                          '${ur ? 'یہ کیوں دکھایا گیا' : 'Why this appears'}: ${item.reason(ur)}')
                ],
                const SizedBox(height: 20),
                if (item.format == 'audio' || item.format == 'video')
                  FilledButton.icon(
                      onPressed: detail.offline ||
                              ContentActions.mediaLink(item.mediaUrl,
                                      provider.allowedMediaHosts) ==
                                  null
                          ? null
                          : _launch,
                      icon: Icon(item.format == 'video'
                          ? Icons.play_circle_outline
                          : Icons.headphones),
                      label: Text(item.youtubeId != null
                          ? (ur ? 'یوٹیوب پر چلائیں' : 'Play on YouTube')
                          : (ur
                              ? 'جائزہ شدہ میڈیا کھولیں'
                              : 'Open reviewed media'))),
                if (ContentActions.activityRoute(item, role: provider.role) !=
                    null)
                  FilledButton.icon(
                      onPressed: detail.offline ? null : _activity,
                      icon: const Icon(Icons.spa_outlined),
                      label: Text(ur ? 'مشق شروع کریں' : 'Start activity')),
                const SizedBox(height: 14),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  OutlinedButton.icon(
                      onPressed: detail.offline || provider.busy(item.id)
                          ? null
                          : () => _change((provider, item) =>
                              provider.setSaved(item, !item.saved)),
                      icon: Icon(
                          item.saved ? Icons.bookmark : Icons.bookmark_outline),
                      label: Text(item.saved
                          ? (ur ? 'محفوظ سے ہٹائیں' : 'Unsave')
                          : (ur ? 'محفوظ کریں' : 'Save'))),
                  OutlinedButton.icon(
                      onPressed: detail.offline || provider.busy(item.id)
                          ? null
                          : () => _change((provider, item) =>
                              provider.giveFeedback(item, 'helpful')),
                      icon: Icon(item.feedback == 'helpful'
                          ? Icons.thumb_up
                          : Icons.thumb_up_outlined),
                      label: Text(ur ? 'مفید' : 'Helpful')),
                  OutlinedButton.icon(
                      onPressed: detail.offline || provider.busy(item.id)
                          ? null
                          : () => _change((provider, item) =>
                              provider.giveFeedback(item, 'not_helpful')),
                      icon: Icon(item.feedback == 'not_helpful'
                          ? Icons.thumb_down
                          : Icons.thumb_down_outlined),
                      label: Text(ur ? 'مفید نہیں' : 'Not helpful')),
                  TextButton(
                      onPressed: detail.offline || provider.busy(item.id)
                          ? null
                          : () => _change((provider, item) =>
                              provider.giveFeedback(item, 'dismissed')),
                      child: Text(ur ? 'اسے نہ دکھائیں' : 'Do not show this')),
                ]),
                if (item.canSaveOffline)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                          ur
                              ? 'محفوظ تحریر اس آلے پر خفیہ آف لائن نقل کے طور پر 24 گھنٹے دستیاب ہو سکتی ہے۔ میڈیا ڈاؤن لوڈ نہیں ہوتا۔'
                              : 'Saved text may be kept as an encrypted offline copy on this device for 24 hours. Media is never downloaded.',
                          style: Theme.of(context).textTheme.bodySmall)),
                const Divider(height: 36),
                Text(ur ? 'ماخذ اور استعمال' : 'Source and use',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                if (item.sourceName.isNotEmpty) SelectableText(item.sourceName),
                if (item.attribution.isNotEmpty)
                  SelectableText(item.attribution),
                if (item.licenseName.isNotEmpty)
                  SelectableText(item.licenseName),
                if (ContentActions.httpsLink(item.sourceUrl) != null)
                  TextButton.icon(
                      onPressed:
                          detail.offline ? null : () => _launch(source: true),
                      icon: const Icon(Icons.open_in_new, size: 17),
                      label: Text(ur ? 'ماخذ دیکھیں' : 'View source')),
                const SizedBox(height: 12),
                Text(
                    ur
                        ? 'یہ تعلیمی اور سکون کے لیے مواد ہے، تشخیص یا علاج نہیں۔ اگر آپ کو فوری خطرہ ہے تو فوری مدد لیں۔'
                        : 'This is educational or calming content, not a diagnosis or treatment. Seek immediate support if you are in danger.',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ]));
  }
}

class _ContentPreferencesSheet extends StatefulWidget {
  const _ContentPreferencesSheet();
  @override
  State<_ContentPreferencesSheet> createState() =>
      _ContentPreferencesSheetState();
}

class _ContentPreferencesSheetState extends State<_ContentPreferencesSheet> {
  bool? _religious, _music;
  Set<String>? _disabled, _interests, _formats;
  int? _version;
  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<ContentProvider>(),
        preferences = context.read<ContentProvider>().preferences;
    _religious ??= preferences.religiousEnabled;
    _music ??= preferences.musicEnabled;
    _disabled ??= preferences.disabledCategories.toSet();
    _interests ??= preferences.interests.toSet();
    _formats ??= preferences.preferredFormats.toSet();
    _version ??= preferences.version;
    return ConstrainedBox(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
        child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                18, 18, 18, 24 + MediaQuery.viewInsetsOf(context).bottom),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ur ? 'آپ کی پسند' : 'Your preferences',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Text(ur
                      ? 'یہ اختیاری ہیں۔ آپ کی پسند علاج یا خاندان کے ساتھ معلومات بانٹنے کی رضامندی کو نہیں بدلتی۔'
                      : 'These choices are optional. They do not change your care or your consent to share information with family.'),
                  const SizedBox(height: 14),
                  SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(ur
                          ? 'اسلامی اور قرآنی مواد'
                          : 'Islamic and Quran content'),
                      subtitle: Text(ur
                          ? 'تلاوت، ترجمہ اور ثقافتی رہنمائی'
                          : 'Recitation, translation and cultural support'),
                      value: _religious!,
                      onChanged: provider.savingPreferences
                          ? null
                          : (value) => setState(() => _religious = value)),
                  SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(ur ? 'موسیقی' : 'Music'),
                      subtitle: Text(ur
                          ? 'غیر مذہبی سکون کی آوازوں سے الگ پسند'
                          : 'Separate from non-music calming sounds'),
                      value: _music!,
                      onChanged: provider.savingPreferences
                          ? null
                          : (value) => setState(() => _music = value)),
                  const Divider(height: 28),
                  Text(
                      ur
                          ? 'آج کل آپ کو کس چیز میں مدد چاہیے؟'
                          : 'What would help you right now?',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                      ur
                          ? 'جو موضوع چنیں گی وہ تجاویز میں پہلے آئیں گے۔ کبھی بھی بدل سکتی ہیں۔'
                          : 'Topics you choose come first in your suggestions. Change them any time.',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: ContentPreferences.interestKeys
                          .where((key) =>
                              (key != 'music' || _music!) &&
                              (key != 'faith' || _religious!))
                          .map((key) => FilterChip(
                              label: Text(contentInterest(key, ur)),
                              selected: _interests!.contains(key),
                              onSelected: provider.savingPreferences
                                  ? null
                                  : (on) => setState(() => on
                                      ? _interests!.add(key)
                                      : _interests!.remove(key))))
                          .toList()),
                  const SizedBox(height: 14),
                  Text(
                      ur
                          ? 'آپ کو کیا پسند ہے؟'
                          : 'How do you like to take things in?',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: ContentItem.formats
                          .map((format) => FilterChip(
                              label: Text(contentFormat(format, ur)),
                              selected: _formats!.contains(format),
                              onSelected: provider.savingPreferences
                                  ? null
                                  : (on) => setState(() => on
                                      ? _formats!.add(format)
                                      : _formats!.remove(format))))
                          .toList()),
                  const Divider(height: 28),
                  Text(
                      ur
                          ? 'کن اقسام کو دکھایا جائے؟'
                          : 'Which categories should appear?',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 8),
                  ...ContentItem.categories.map((category) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: Text(contentCategory(category, ur)),
                      value: !_disabled!.contains(category),
                      onChanged: provider.savingPreferences
                          ? null
                          : (value) => setState(() {
                                if (value == true) {
                                  _disabled!.remove(category);
                                } else {
                                  _disabled!.add(category);
                                }
                              }))),
                  if (provider.error != null)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                            ur
                                ? 'پسند محفوظ نہیں ہوئی۔ اگر دوسرے آلے پر بدلی ہے تو بند کر کے دوبارہ کھولیں۔'
                                : provider.error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))),
                  SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                          onPressed: provider.savingPreferences
                              ? null
                              : () async {
                                  final owner = provider.accountId;
                                  final saved = await provider
                                      .updatePreferences(ContentPreferences(
                                          religiousEnabled: _religious!,
                                          musicEnabled: _music!,
                                          disabledCategories:
                                              _disabled!.toList(),
                                          // A topic needing an opt-in that is
                                          // now off is dropped, not kept hidden.
                                          interests: _interests!
                                              .where((key) =>
                                                  (key != 'music' || _music!) &&
                                                  (key != 'faith' ||
                                                      _religious!))
                                              .toList(),
                                          preferredFormats: _formats!.toList(),
                                          version: _version!));
                                  if (context.mounted &&
                                      saved &&
                                      provider.accountId == owner) {
                                    Navigator.pop(context);
                                  }
                                },
                          child: Text(provider.savingPreferences
                              ? (ur ? 'محفوظ ہو رہا ہے…' : 'Saving…')
                              : (ur
                                  ? 'پسند محفوظ کریں'
                                  : 'Save preferences')))),
                  TextButton(
                      onPressed: provider.savingPreferences
                          ? null
                          : () => Navigator.pop(context),
                      child: Text(ur ? 'منسوخ' : 'Cancel')),
                ])));
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: context.hcSurfaceVariant,
          borderRadius: BorderRadius.circular(18)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: context.hcTextSecondary)),
        ),
      ]));
}
