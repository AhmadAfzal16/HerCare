import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';
import '../../providers/risk_provider.dart';
import 'widgets/home_header.dart';
import 'widgets/mood_hero_card.dart';
import 'widgets/wellbeing_grid.dart';
import 'widgets/epds_prompt_card.dart';
import 'widgets/quick_actions_row.dart';
import 'widgets/guardian_card.dart';
import 'widgets/daily_verse_card.dart';

import '../epds/epds_screen.dart';
import '../hum_raaz/hum_raaz_screen.dart';
import '../wellbeing/wellbeing_screen.dart';
import '../profile/profile_screen.dart';

/// Home Dashboard — main hub after login.
///
/// Sections (scrollable):
///   1. Mood Hero Card      — daily check-in + day postpartum badge
///   2. Wellbeing Grid      — EPDS score, mood, sleep, Hum-Raaz
///   3. EPDS Prompt Card    — weekly screening CTA
///   4. Quick Actions Row   — breathe, journal, chatbot, crisis
///   5. Guardian Card       — connected spouse/guardian status
///   6. Daily Verse Card    — Quranic ayah + Urdu translation
///
/// Bottom Nav: Home | Screening | Chat | Wellbeing | Profile
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _navIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<RiskProvider>().syncIfDue(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    final List<Widget> pages = [
      const _HomeDashboardView(),
      const EpdsScreen(hideBackButton: true),
      const HumRaazScreen(),
      const WellbeingScreen(hideBackButton: true),
      const ProfileScreen(),
    ];

    return Scaffold(
      backgroundColor: context.hcBg,
      body: IndexedStack(
        index: _navIndex,
        children: pages,
      ),
      bottomNavigationBar: _BottomNav(
        currentIndex: _navIndex,
        isUrdu: isUrdu,
        onTap: (i) => setState(() => _navIndex = i),
      ),
    );
  }
}

class _HomeDashboardView extends StatelessWidget {
  const _HomeDashboardView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: const HomeHeader(),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        children: const [
          MoodHeroCard(),
          SizedBox(height: 24),
          WellbeingGrid(),
          SizedBox(height: 24),
          EpdsPromptCard(),
          SizedBox(height: 24),
          QuickActionsRow(),
          SizedBox(height: 24),
          GuardianCard(),
          SizedBox(height: 24),
          DailyVerseCard(),
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
        icon: Icons.home_rounded,
        labelEn: 'Home',
        labelUr: 'ہوم',
      ),
      _NavItem(
        icon: Icons.assignment_outlined,
        labelEn: 'EPDS',
        labelUr: 'جانچ',
      ),
      _NavItem(
        icon: Icons.chat_bubble_outline_rounded,
        labelEn: 'Hum-Raaz',
        labelUr: 'ہم راز',
      ),
      _NavItem(
        icon: Icons.bedtime_outlined,
        labelEn: 'Wellbeing',
        labelUr: 'صحت',
      ),
      _NavItem(
        icon: Icons.person_outline_rounded,
        labelEn: 'Profile',
        labelUr: 'پروفائل',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: context.hcSurface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(items.length, (i) {
              final selected = currentIndex == i;
              final item = items[i];
              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 64,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: selected
                              ? AppColors.primaryContainer
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          item.icon,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 24,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        isUrdu ? item.labelUr : item.labelEn,
                        style: AppTextStyles.labelSmall.copyWith(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w400,
                          fontSize: 10,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 2),
                      // Active dot indicator
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: selected ? 6 : 0,
                        height: selected ? 6 : 0,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String labelEn;
  final String labelUr;

  const _NavItem({
    required this.icon,
    required this.labelEn,
    required this.labelUr,
  });
}
