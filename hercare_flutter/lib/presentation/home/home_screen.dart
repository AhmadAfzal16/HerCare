import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/risk_provider.dart';
import 'widgets/home_header.dart';
import 'widgets/mood_hero_card.dart';
import 'widgets/wellbeing_grid.dart';
import 'widgets/epds_prompt_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/guardian_card.dart';
import '../../core/routing/app_router.dart';
import '../content/content_for_you_card.dart';

import '../epds/tests_screen.dart';
import '../hum_raaz/hum_raaz_screen.dart';
import '../wellbeing/wellbeing_screen.dart';
import '../profile/profile_screen.dart';
import '../community/community_screen.dart';

/// Home Dashboard — main hub after login.
///
/// Sections (scrollable):
///   1. Mood Hero Card      — daily check-in + day postpartum badge
///   2. Wellbeing Grid      — EPDS score, mood, sleep, Hum-Raaz
///   3. EPDS Prompt Card    — weekly screening CTA
///   4. Quick Actions Row   — breathe, journal, chatbot, crisis
///   5. Guardian Card       — connected spouse/guardian status
///   6. For You feed        — live, reviewed server content and optional verses
///
/// Bottom Nav: Home | Screening | Chat | Wellbeing | Profile
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;
  final Set<int> _visitedTabs = {0};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (mounted) context.read<RiskProvider>().syncIfDue();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    final List<Widget> pages = [
      _HomeDashboardView(active: _navIndex == 0),
      TestsScreen(embedded: true, active: _navIndex == 1),
      HumRaazScreen(key: ValueKey(context.watch<AuthProvider>().user?.id)),
      const WellbeingScreen(hideBackButton: true),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: context.hcBg,
      body: IndexedStack(
        index: _navIndex,
        children: [
          for (var i = 0; i < pages.length; i++)
            // Dispose private bot state on tab exit; server history is retained.
            (i == 2 ? _navIndex == 2 : _visitedTabs.contains(i))
                ? pages[i]
                : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        isUrdu: isUrdu,
        onTap: (i) => setState(() {
          _visitedTabs.add(i);
          _navIndex = i;
        }),
      ),
    );
  }
}

class _HomeDashboardView extends StatelessWidget {
  const _HomeDashboardView({required this.active});
  final bool active;

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 28);
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: const HomeHeader(),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          const MoodHeroCard(),
          gap,
          const QuickActionsRow(),
          gap,
          const WellbeingGrid(),
          gap,
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ContentForYouCard(
                  active: active,
                  onOpen: () => context.push(AppRoutes.content))),
          gap,
          const EpdsPromptCard(),
          gap,
          const GuardianCard(),
          const SizedBox(height: 16),
          const CommunityEntryCard(),
        ],
      ),
    );
  }
}

// ─── Bottom Navigation Bar ────────────────────────────────────────────────────

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final bool isUrdu;
  final void Function(int) onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.isUrdu,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const items = [
      _NavItem(
        icon: Icons.home_outlined,
        activeIcon: Icons.home_rounded,
        labelEn: 'Home',
        labelUr: 'ہوم',
      ),
      _NavItem(
        icon: Icons.assignment_outlined,
        activeIcon: Icons.assignment_rounded,
        labelEn: 'Tests',
        labelUr: 'جانچ',
      ),
      _NavItem(
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
        labelEn: 'Hum-Raaz',
        labelUr: 'ہم راز',
      ),
      _NavItem(
        icon: Icons.spa_outlined,
        activeIcon: Icons.spa_rounded,
        labelEn: 'Wellbeing',
        labelUr: 'صحت',
      ),
      _NavItem(
        icon: Icons.person_outline_rounded,
        activeIcon: Icons.person_rounded,
        labelEn: 'Profile',
        labelUr: 'پروفائل',
      ),
    ];
    final primary = Theme.of(context).colorScheme.primary;
    final muted = context.hcTextSecondary;

    return Container(
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          child: Row(
            children: List.generate(items.length, (i) {
              final selected = currentIndex == i;
              final item = items[i];
              final label = isUrdu ? item.labelUr : item.labelEn;
              return Expanded(
                  child: Semantics(
                selected: selected,
                button: true,
                child: InkResponse(
                  onTap: () => onTap(i),
                  radius: 36,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        width: 58,
                        height: 32,
                        decoration: BoxDecoration(
                          color: selected
                              ? (context.isDark
                                  ? primary.withValues(alpha: 0.2)
                                  : AppColors.primaryContainer)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(
                          selected ? item.activeIcon : item.icon,
                          color: selected ? primary : muted,
                          size: 23,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: selected ? primary : muted,
                          fontWeight:
                              selected ? FontWeight.w800 : FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ));
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String labelEn;
  final String labelUr;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.labelEn,
    required this.labelUr,
  });
}
