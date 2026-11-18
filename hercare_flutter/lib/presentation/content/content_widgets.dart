import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/content_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/content_provider.dart';
import '../../providers/language_provider.dart';

String contentCategory(String category, bool ur) => switch (category) {
      'quran' => ur ? 'قرآن' : 'Quran',
      'islamic' => ur ? 'اسلامی' : 'Islamic',
      'soothing' => ur ? 'سکون' : 'Soothing',
      'psychoeducation' => ur ? 'رہنمائی' : 'Learn',
      'bonding' => ur ? 'خاندانی تعاون' : 'Family support',
      'game' => ur ? 'ہلکے کھیل' : 'Light games',
      _ => ur ? 'مشقیں' : 'Activities',
    };

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
    return Card(
      color: context.hcSurface,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: context.hcOutline.withValues(alpha: .45))),
      child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 18),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(contentIcon(item), color: AppColors.primary, size: 24),
                    Text(contentCategory(item.category, ur),
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: AppColors.primary)),
                    if (item.saved)
                      Icon(Icons.bookmark,
                          size: 17,
                          color: AppColors.primary,
                          semanticLabel: ur ? 'محفوظ' : 'Saved'),
                    if (item.durationSeconds != null)
                      Text(
                          ur
                              ? '${(item.durationSeconds! / 60).ceil()} منٹ'
                              : '${(item.durationSeconds! / 60).ceil()} min',
                          style: Theme.of(context).textTheme.labelSmall),
                  ]),
              const SizedBox(height: 9),
              Text(item.title(ur),
                  maxLines: compact ? 3 : 5,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              if (item.summary(ur).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(item.summary(ur),
                    maxLines: compact ? 2 : 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: context.hcTextSecondary)),
              ],
              if (item.reason(ur).isNotEmpty && !compact) ...[
                const SizedBox(height: 12),
                Text(
                    '${ur ? 'کیوں تجویز ہوا' : 'Why this appears'}: ${item.reason(ur)}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: context.hcTextSecondary)),
              ],
              const SizedBox(height: 10),
              Text(ur ? 'تفصیل دیکھیں ←' : 'View content →',
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: AppColors.primary)),
            ]),
          )),
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
