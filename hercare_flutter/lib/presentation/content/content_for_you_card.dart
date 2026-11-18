import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/content_provider.dart';
import '../../providers/language_provider.dart';
import '../shared/hc_widgets.dart';
import 'content_widgets.dart';

/// A foreground/visible home preview, not a background polling service. The
/// IndexedStack owner must pass active:false while a different tab is selected.
class ContentForYouCard extends StatefulWidget {
  const ContentForYouCard({super.key, this.onOpen, this.active = true});
  final VoidCallback? onOpen;
  final bool active;
  @override
  State<ContentForYouCard> createState() => _ContentForYouCardState();
}

class _ContentForYouCardState extends State<ContentForYouCard>
    with WidgetsBindingObserver {
  Timer? _timer;
  String? _language, _owner;
  int? _signalRevision;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final language = context.watch<LanguageProvider>().isUrdu ? 'ur' : 'en';
    final owner = context.watch<ContentProvider>().accountId;
    final revision = context.watch<ContentProvider>().signalRevision;
    if (_language != language ||
        _owner != owner ||
        revision != _signalRevision) {
      _language = language;
      _owner = owner;
      _signalRevision = revision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  @override
  void didUpdateWidget(ContentForYouCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
    if (!widget.active) _timer?.cancel();
  }

  bool get _visible =>
      mounted &&
      widget.active &&
      _foreground &&
      (ModalRoute.of(context)?.isCurrent ?? true);
  Future<void> _refresh() async {
    _timer?.cancel();
    if (!_visible) {
      _schedule();
      return;
    }
    await context.read<ContentProvider>().load(language: _language ?? 'en');
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (!mounted || !widget.active || !_foreground) return;
    _timer = Timer(context.read<ContentProvider>().refreshInterval, _refresh);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      _refresh();
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

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<ContentProvider>();
    final items = provider.items();
    final verse = provider.dailyVerse;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      HcSectionHeader(
          title: ur ? 'آپ کے لیے' : 'For you',
          subtitle: ur
              ? 'ویڈیوز، سکون بخش آوازیں اور آیات'
              : 'Videos, calming sounds and verses',
          actionLabel: ur ? 'سب دیکھیں' : 'View all',
          onAction: widget.onOpen ?? () => context.push('/content')),
      const SizedBox(height: 12),
      if (provider.safetyPriority)
        HcCard(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const HcIconBadge(
                      icon: Icons.favorite_rounded,
                      color: AppColors.secondary,
                      background: AppColors.secondaryContainer,
                      size: 40),
                  const SizedBox(height: 10),
                  Text(ur
                      ? 'اس وقت براہ راست تعاون پہلے ہے۔ عام مواد فوری مدد کا متبادل نہیں۔'
                      : 'Direct support comes first right now. Ordinary content is not a substitute for immediate help.'),
                  const SizedBox(height: 6),
                  TextButton.icon(
                      onPressed: () => context.push('/crisis'),
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: Text(ur ? 'فوری مدد' : 'Immediate support')),
                ]))
      else if (items.isNotEmpty) ...[
        if (provider.isOffline)
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                  ur
                      ? 'آف لائن: صرف پہلے سے محفوظ تحریر۔ تازہ تجویز نہیں۔'
                      : 'Offline: previously saved text only, not a fresh recommendation.',
                  style: Theme.of(context).textTheme.bodySmall)),
        if (verse != null)
          ContentTile(
              item: verse,
              compact: true,
              onTap: () =>
                  context.push('/content?id=${Uri.encodeComponent(verse.id)}')),
        ...items
            .where((item) => item.id != verse?.id)
            .take(verse == null ? 2 : 1)
            .map((item) => ContentTile(
                item: item,
                compact: true,
                onTap: () => context
                    .push('/content?id=${Uri.encodeComponent(item.id)}'))),
      ] else
        HcCard(
            onTap: widget.onOpen ?? () => context.push('/content'),
            child: Row(children: [
              const HcIconBadge(
                  icon: Icons.auto_awesome_rounded,
                  color: AppColors.primary,
                  background: AppColors.primaryContainer,
                  size: 44),
              const SizedBox(width: 14),
              Expanded(
                          child: Text(provider.isLoading
                              ? (ur
                                  ? 'مواد تازہ ہو رہا ہے…'
                                  : 'Refreshing your content…')
                              : provider.error != null
                                  ? (ur
                                      ? 'مواد تازہ نہیں ہوا۔ دوبارہ کوشش کریں۔'
                                      : 'Content could not be refreshed. Tap to retry.')
                                  : (ur
                                      ? 'جائزہ شدہ مواد اور اپنی پسند دیکھیں۔ اسلامی مواد اور موسیقی آپ کی مرضی سے۔'
                                      : 'Explore reviewed content and your preferences. Islamic content and music are optional.'))),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: context.hcTextHint),
            ])),
    ]);
  }
}
