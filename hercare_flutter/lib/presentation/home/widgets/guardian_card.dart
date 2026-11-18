import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../providers/guardian_provider.dart';
import '../../../providers/language_provider.dart';
import '../../shared/hc_widgets.dart';

/// Shows the mother's real guardian link (name and relationship), or an
/// invitation to connect someone she trusts when no one is linked yet.
class GuardianCard extends StatefulWidget {
  const GuardianCard({super.key});

  @override
  State<GuardianCard> createState() => _GuardianCardState();
}

class _GuardianCardState extends State<GuardianCard> {
  static final _tonal = FilledButton.styleFrom(
    backgroundColor: AppColors.primaryContainer,
    foregroundColor: AppColors.primary,
    minimumSize: const Size(64, 44),
  );

  static const _relationEn = {
    'husband': 'Husband',
    'mother': 'Mother',
    'sister': 'Sister',
    'brother': 'Brother',
    'father': 'Father',
    'friend': 'Friend',
    'other': 'Family',
  };
  static const _relationUr = {
    'husband': 'شوہر',
    'mother': 'والدہ',
    'sister': 'بہن',
    'brother': 'بھائی',
    'father': 'والد',
    'friend': 'دوست',
    'other': 'خاندان',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final guardian = context.read<GuardianProvider>();
      if (!guardian.hasActiveLink && !guardian.isLoading) guardian.loadLink();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final link = context.watch<GuardianProvider>().link;
    final theme = Theme.of(context);
    final name = (link?['guardian_name'] as String?)?.trim();
    final relation = link?['relationship'] as String?;
    final relationLabel = relation == null
        ? null
        : (isUrdu ? _relationUr[relation] : _relationEn[relation]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HcSectionHeader(title: isUrdu ? 'آپ کا سہارا' : 'Your support'),
          const SizedBox(height: 12),
          HcCard(
            onTap: () => context.push(AppRoutes.guardianLink),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (link != null)
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: AppColors.accentContainer,
                        child: Text(
                          (name == null || name.isEmpty)
                              ? '♥'
                              : name.characters.first.toUpperCase(),
                          style: theme.textTheme.titleLarge
                              ?.copyWith(color: AppColors.accent),
                        ),
                      )
                    else
                      const HcIconBadge(
                        icon: Icons.family_restroom_rounded,
                        color: AppColors.accent,
                        background: AppColors.accentContainer,
                        size: 48,
                      ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            link == null
                                ? (isUrdu
                                    ? 'کسی قابلِ اعتماد کو جوڑیں'
                                    : 'Connect someone you trust')
                                : (name == null || name.isEmpty
                                    ? (isUrdu
                                        ? 'آپ کا سرپرست'
                                        : 'Your guardian')
                                    : name),
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (link == null)
                            Text(
                              isUrdu
                                  ? 'شوہر یا گھر والوں کو اپنی خیریت سے باخبر رکھیں'
                                  : 'Keep your husband or family gently in the loop',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: context.hcTextSecondary),
                            )
                          else
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (relationLabel != null)
                                  HcPill(
                                      label: relationLabel,
                                      color: AppColors.accent),
                                HcPill(
                                  label: isUrdu ? 'منسلک' : 'Connected',
                                  icon: Icons.check_circle_rounded,
                                  color: AppColors.success,
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: link == null
                      ? FilledButton.tonalIcon(
                          style: _tonal,
                          onPressed: () => context.push(AppRoutes.guardianLink),
                          icon: const Icon(Icons.person_add_alt_1_rounded,
                              size: 18),
                          label: Text(isUrdu ? 'دعوت دیں' : 'Invite'),
                        )
                      : FilledButton.tonalIcon(
                          style: _tonal,
                          onPressed: () => context.push(AppRoutes.reports),
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: Text(isUrdu ? 'اپ ڈیٹ بھیجیں' : 'Send update'),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
