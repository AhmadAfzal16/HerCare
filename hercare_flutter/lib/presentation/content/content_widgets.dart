import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/content_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/content_provider.dart';
import '../../providers/language_provider.dart';
import '../shared/hc_widgets.dart';
import 'content_actions.dart';

String contentCategory(String category, bool ur) => switch (category) {
      'quran' => ur ? 'قرآن' : 'Quran',
      'islamic' => ur ? 'اسلامی' : 'Islamic',
      'soothing' => ur ? 'سکون' : 'Soothing',
      'psychoeducation' => ur ? 'رہنمائی' : 'Learn',
      'bonding' => ur ? 'خاندانی تعاون' : 'Family support',
      'game' => ur ? 'ہلکے کھیل' : 'Light games',
      _ => ur ? 'مشقیں' : 'Activities',
    };

String contentInterest(String key, bool ur) => switch (key) {
      'sleep' => ur ? 'نیند' : 'Sleep',
      'calm' => ur ? 'سکون اور آرام' : 'Calm and relaxation',
      'music' => ur ? 'پرسکون موسیقی' : 'Soothing music',
      'low_mood' => ur ? 'اداسی یا بوجھل دل' : 'Feeling low',
      'anxiety' => ur ? 'فکر اور بے چینی' : 'Worry and anxiety',
      'feeding' => ur ? 'دودھ پلانا' : 'Feeding',
      'body_recovery' => ur ? 'جسمانی بحالی' : 'Body recovery',
      'baby_bonding' => ur ? 'بچے سے تعلق' : 'Bonding with baby',
      'relationships' => ur ? 'شوہر اور خاندان' : 'Husband and family',
      'faith' => ur ? 'قرآن اور دعا' : 'Quran and dua',
      _ => ur ? 'سمجھنا اور سیکھنا' : 'Understanding what I feel',
    };

String contentFormat(String format, bool ur) => switch (format) {
      'video' => ur ? 'ویڈیوز' : 'Videos',
      'audio' => ur ? 'سننا' : 'Listening',
      'article' => ur ? 'پڑھنا' : 'Reading',
      _ => ur ? 'مشقیں' : 'Activities',
    };

/// A YouTube preview image with a play button. The image is fetched from
/// YouTube's image host; the video itself opens only when she taps.
class ContentVideoPreview extends StatelessWidget {
  const ContentVideoPreview(
      {super.key,
      required this.item,
      required this.onTap,
      required this.semanticLabel});
  final ContentItem item;
  final VoidCallback onTap;
  final String semanticLabel;
  @override
  Widget build(BuildContext context) {
    final url = item.thumbnailUrl;
    if (url == null) return const SizedBox.shrink();
    return Semantics(
        button: true,
        label: semanticLabel,
        child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Material(
                    color: context.hcSurfaceVariant,
                    child: InkWell(
                        onTap: onTap,
                        child: Stack(fit: StackFit.expand, children: [
                          Image.network(url,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (_, __, ___) => Icon(
                                  contentIcon(item),
                                  size: 40,
                                  color: AppColors.primary)),
                          Center(
                              child: DecoratedBox(
                                  decoration: BoxDecoration(
                                      color:
                                          Colors.black.withValues(alpha: .55),
                                      shape: BoxShape.circle),
                                  child: const Padding(
                                      padding: EdgeInsets.all(10),
                                      child: Icon(Icons.play_arrow_rounded,
                                          color: Colors.white, size: 38)))),
                        ]))))));
  }
}

/// "Live from YouTube": unreviewed results from trusted channels, kept visibly
/// separate from the reviewed feed. Each video opens only after confirmation.
class LiveVideoSection extends StatelessWidget {
  const LiveVideoSection({super.key});

  Future<void> _play(BuildContext context, LiveVideo video) async {
    final provider = context.read<ContentProvider>();
    final ur = context.read<LanguageProvider>().isUrdu;
    final uri =
        ContentActions.mediaLink(video.mediaUrl, provider.allowedMediaHosts);
    if (uri == null) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(ur ? 'یوٹیوب کھولیں؟' : 'Open YouTube?'),
                content: SingleChildScrollView(
                    child: Text(ur
                        ? '${video.channelTitle}\n\nیہ ویڈیو ایک بھروسے مند چینل سے ہے لیکن ہرکیئر نے اس کا الگ جائزہ نہیں لیا۔ یوٹیوب اپنے اشتہارات اور ڈیٹا استعمال کر سکتا ہے۔ اگر کچھ پریشان کن لگے تو ویڈیو بند کریں اور ایپ میں "یہ نہ دکھائیں" دبائیں۔ یہ علاج کا متبادل نہیں۔'
                        : '${video.channelTitle}\n\nThis video is from a trusted channel but has not been individually reviewed by HerCare. YouTube may show ads and use its own data collection. If anything feels upsetting, close it and tap "Don\'t show this" here. This is not a substitute for care.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: Text(ur ? 'منسوخ' : 'Cancel')),
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: Text(ur ? 'کھولیں' : 'Open')),
                ]));
    if (confirmed != true || !context.mounted) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
        context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              ur ? 'لنک نہیں کھل سکا۔' : 'The link could not be opened.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<ContentProvider>();
    final videos = provider.liveVideos;
    if (videos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 12),
      Row(children: [
        const HcIconBadge(
            icon: Icons.smart_display_rounded,
            color: AppColors.secondary,
            background: AppColors.secondaryContainer,
            size: 40),
        const SizedBox(width: 12),
        Expanded(
            child: Text(ur ? 'یوٹیوب سے تازہ' : 'Live from YouTube',
                style: theme.textTheme.titleLarge?.copyWith(fontSize: 18))),
      ]),
      const SizedBox(height: 8),
      Text(provider.liveFeed?.notice(ur) ?? '',
          style: theme.textTheme.bodySmall
              ?.copyWith(color: context.hcTextSecondary)),
      const SizedBox(height: 14),
      for (final video in videos)
        Card(
            key: ValueKey('live-${video.videoId}'),
            color: context.hcSurface,
            margin: const EdgeInsets.only(bottom: 14),
            clipBehavior: Clip.antiAlias,
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                          button: true,
                          label: ur ? 'ویڈیو چلائیں' : 'Play video',
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: AspectRatio(
                                  aspectRatio: 16 / 9,
                                  child: Material(
                                      color: context.hcSurfaceVariant,
                                      child: InkWell(
                                          onTap: () => _play(context, video),
                                          child: Stack(
                                              fit: StackFit.expand,
                                              children: [
                                                Image.network(
                                                    video.thumbnailUrl,
                                                    fit: BoxFit.cover,
                                                    excludeFromSemantics: true,
                                                    errorBuilder: (_, __,
                                                            ___) =>
                                                        const Icon(
                                                            Icons
                                                                .play_circle_outline,
                                                            size: 40,
                                                            color: AppColors
                                                                .primary)),
                                                const Center(
                                                    child: Icon(
                                                        Icons.play_circle_fill,
                                                        color: Colors.white,
                                                        size: 52)),
                                              ])))))),
                      const SizedBox(height: 10),
                      // Untrusted YouTube text: plain Text only, bounded lines.
                      Text(video.title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                          [
                            video.channelTitle,
                            if (video.durationSeconds != null)
                              ur
                                  ? '${(video.durationSeconds! / 60).ceil()} منٹ'
                                  : '${(video.durationSeconds! / 60).ceil()} min',
                          ].join(' · '),
                          style: theme.textTheme.labelMedium
                              ?.copyWith(color: AppColors.primary)),
                      if (video.reason(ur).isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(video.reason(ur),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: context.hcTextSecondary)),
                      ],
                      Wrap(spacing: 8, children: [
                        TextButton.icon(
                            onPressed: () => _play(context, video),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(ur ? 'چلائیں' : 'Play')),
                        TextButton(
                            onPressed: () async {
                              await provider.hideLive(video);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(ur
                                        ? 'یہ ویڈیو آپ کو دوبارہ نہیں دکھائی جائے گی۔'
                                        : 'You won\'t see this video again.')));
                              }
                            },
                            child: Text(
                                ur ? 'یہ نہ دکھائیں' : 'Don\'t show this')),
                      ]),
                    ]))),
    ]);
  }
}

IconData contentIcon(ContentItem item) => switch (item.category) {
      'quran' || 'islamic' => Icons.auto_stories_outlined,
      'bonding' => Icons.family_restroom_outlined,
      'game' => Icons.extension_outlined,
      'psychoeducation' => Icons.lightbulb_outline,
      _ => switch (item.format) {
          'video' => Icons.play_circle_outline,
          'audio' => Icons.headphones_outlined,
          _ => Icons.spa_outlined,
        },
    };

/// Pastel colour per content category, so the feed is easy to scan.
(Color, Color) contentColors(ContentItem item) => switch (item.category) {
      'quran' || 'islamic' => (AppColors.success, AppColors.successContainer),
      'soothing' => (AppColors.sky, AppColors.skyContainer),
      'psychoeducation' => (AppColors.peach, AppColors.peachContainer),
      'bonding' => (AppColors.secondary, AppColors.secondaryContainer),
      'game' => (AppColors.accent, AppColors.accentContainer),
      _ => (AppColors.primary, AppColors.primaryContainer),
    };

class ContentTile extends StatelessWidget {
  const ContentTile(
      {super.key,
      required this.item,
      required this.onTap,
      this.compact = false});
  final ContentItem item;
  final VoidCallback onTap;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final theme = Theme.of(context);
    final (color, tint) = contentColors(item);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: context.hcSoftShadow,
        border: context.isDark ? Border.all(color: context.hcOutline) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(compact ? 14 : 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!compact && item.thumbnailUrl != null) ...[
                      ContentVideoPreview(
                          item: item,
                          onTap: onTap,
                          semanticLabel: ur ? 'تفصیل دیکھیں' : 'View content'),
                      const SizedBox(height: 14),
                    ],
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: context.isDark
                                ? color.withValues(alpha: 0.18)
                                : tint,
                            borderRadius: BorderRadius.circular(15)),
                        child: Icon(contentIcon(item), color: color, size: 23),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Text(contentCategory(item.category, ur),
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(color: color)),
                                  if (item.durationSeconds != null)
                                    Text(
                                        ur
                                            ? '· ${(item.durationSeconds! / 60).ceil()} منٹ'
                                            : '· ${(item.durationSeconds! / 60).ceil()} min',
                                        style: theme.textTheme.labelSmall
                                            ?.copyWith(
                                                color:
                                                    context.hcTextSecondary)),
                                  if (item.saved)
                                    Icon(Icons.bookmark_rounded,
                                        size: 16,
                                        color: color,
                                        semanticLabel: ur ? 'محفوظ' : 'Saved'),
                                ]),
                            const SizedBox(height: 4),
                            Text(item.title(ur),
                                maxLines: compact ? 3 : 5,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium),
                          ])),
                    ]),
                    if (item.summary(ur).isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(item.summary(ur),
                          maxLines: compact ? 2 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(color: context.hcTextSecondary)),
                    ],
                    if (item.reason(ur).isNotEmpty && !compact) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                            color: context.hcSurfaceVariant,
                            borderRadius: BorderRadius.circular(14)),
                        child: Text(
                            '${ur ? 'کیوں تجویز ہوا' : 'Why this appears'}: ${item.reason(ur)}',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: context.hcTextSecondary)),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Text(ur ? 'تفصیل دیکھیں ←' : 'View content →',
                        style: theme.textTheme.labelLarge
                            ?.copyWith(color: theme.colorScheme.primary)),
                  ]),
            )),
      ),
    );
  }
}

/// A mounted article/dialog never transfers its state to a newly signed-in
/// person. Production routes additionally have the shared auth guards.
class ContentAccountScope extends StatefulWidget {
  const ContentAccountScope({super.key, required this.child});
  final Widget child;
  @override
  State<ContentAccountScope> createState() => _ContentAccountScopeState();
}

class _ContentAccountScopeState extends State<ContentAccountScope> {
  String? _owner;
  bool _captured = false, _invalid = false;
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ContentProvider>();
    final auth = context.watch<AuthProvider?>();
    if (!_captured) {
      _captured = true;
      _owner = provider.accountId;
    }
    if (_owner != provider.accountId ||
        !provider.canUseAccount ||
        (auth != null &&
            (!auth.isAuthenticated ||
                auth.user?.id != _owner ||
                auth.user?.onboardingComplete != true))) {
      _invalid = true;
    }
    if (!_invalid) return widget.child;
    final ur = context.watch<LanguageProvider>().isUrdu;
    return Material(
        color: context.hcSurface,
        child: SafeArea(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_outline, size: 32),
                  const SizedBox(height: 16),
                  Text(ur
                      ? 'اکاؤنٹ بدل گیا ہے یا رسائی دستیاب نہیں۔ مواد دوبارہ کھولیں۔'
                      : 'Your account changed or access is unavailable. Reopen your content.'),
                  TextButton(
                      onPressed: () => Navigator.maybePop(context),
                      child: Text(ur ? 'واپس' : 'Back')),
                ]))));
  }
}
