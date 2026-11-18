import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/language_provider.dart';

enum _Period {
  daily('Daily', 'روزانہ'),
  weekly('Weekly', 'ہفتہ وار'),
  fortnightly('14 days', '۱۴ دن');

  const _Period(this.english, this.urdu);
  final String english;
  final String urdu;
}

class GuardianTrendsScreen extends StatefulWidget {
  const GuardianTrendsScreen({super.key});

  @override
  State<GuardianTrendsScreen> createState() => _GuardianTrendsScreenState();
}

class _GuardianTrendsScreenState extends State<GuardianTrendsScreen>
    with WidgetsBindingObserver {
  _Period _period = _Period.weekly;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _started = true);
      _refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ModalRoute.of(context)?.isCurrent == true) {
      _refresh();
    }
  }

  Future<void> _refresh() =>
      context.read<GuardianProvider>().loadWellbeingTrends();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urdu = context.watch<LanguageProvider>().isUrdu;
    final guardian = context.watch<GuardianProvider>();
    final periods = guardian.wellbeingTrends?['periods'] as Map?;
    final report = periods?[_period.name] as Map?;
    final bars = report?['bars'] as List?;
    final direction = switch (report?['direction']) {
      'improving' => urdu ? 'اسکور بہتر ہوا' : 'Score improving',
      'declining' => urdu ? 'اسکور کم ہوا' : 'Score declining',
      'similar' => urdu ? 'معمولی تبدیلی' : 'Little change',
      _ =>
        urdu ? 'موازنے کے لیے ناکافی ریکارڈ' : 'Not enough comparable records',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(
          urdu ? 'خیریت کا رجحان' : 'Wellbeing trends',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: urdu ? 'رپورٹ کی تاریخ' : 'Report history',
            icon: const Icon(Icons.history),
            onPressed: () async {
              await context.push(AppRoutes.reports);
              if (mounted) await _refresh();
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final period in _Period.values)
                  ChoiceChip(
                    label: Text(urdu ? period.urdu : period.english),
                    selected: _period == period,
                    onSelected: (_) => setState(() => _period = period),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_started || guardian.loadingWellbeingTrends)
              const LinearProgressIndicator()
            else if (bars == null) ...[
              Text(urdu
                  ? 'رپورٹ دستیاب نہیں۔ فعال سرپرست لنک اور شیئرنگ کی اجازت درکار ہے۔'
                  : 'Reports are unavailable. Check the connection and that guardian sharing is active.'),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton(
                  onPressed: _refresh,
                  child: Text(urdu ? 'دوبارہ کوشش کریں' : 'Try again'),
                ),
              ),
            ] else ...[
              Semantics(
                liveRegion: true,
                header: true,
                child: Text(direction,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              const SizedBox(height: 4),
              Text(urdu
                  ? 'تازہ ترین دو ادوار کا موازنہ۔'
                  : 'Compares the latest two periods.'),
              const SizedBox(height: 16),
              Text(
                urdu
                    ? 'شیئر کردہ خیریت کا اسکور (۰–۱۰۰)'
                    : 'Shared wellbeing score (0–100)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(urdu
                  ? 'زیادہ اسکور شیئر کردہ ریکارڈ میں بہتر خیریت کو ظاہر کرتا ہے۔'
                  : 'Higher scores reflect more favorable shared records.'),
              const SizedBox(height: 8),
              for (final bar in bars.whereType<Map>())
                _ScoreBar(bar: bar, urdu: urdu),
              const SizedBox(height: 8),
              Text(urdu
                  ? 'حالیہ EPDS کا نتیجہ سات دن تک اسکور میں شامل ہو سکتا ہے۔'
                  : 'A recent EPDS result can contribute to scores for up to seven days.'),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.bar, required this.urdu});

  final Map bar;
  final bool urdu;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    final start = DateTime.tryParse(bar['start_date'] as String? ?? '');
    final end = DateTime.tryParse(bar['end_date'] as String? ?? '');
    final score = bar['score'] as num?;
    final measures = bar['measures'] as List? ?? const [];
    final scoreLabel = score == null
        ? (urdu ? 'ناکافی ریکارڈ' : 'Insufficient data')
        : '${score.toStringAsFixed(1)} / 100';
    final source =
        switch ((measures.contains('mood'), measures.contains('epds'))) {
      (true, true) => urdu ? 'موڈ اور EPDS' : 'Mood and EPDS',
      (true, false) => urdu ? 'صرف موڈ' : 'Mood only',
      (false, true) => urdu ? 'صرف EPDS' : 'EPDS only',
      _ => null,
    };
    if (start == null || end == null) return const SizedBox.shrink();
    final dateLabel = start == end
        ? localizations.formatShortDate(end)
        : '${localizations.formatShortDate(start)} – ${localizations.formatShortDate(end)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(dateLabel, style: Theme.of(context).textTheme.labelLarge),
              Text(scoreLabel, style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          if (score != null) ...[
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: LinearProgressIndicator(
                value: (score / 100).clamp(0.0, 1.0),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            if (source != null) ...[
              const SizedBox(height: 4),
              Text(source, style: Theme.of(context).textTheme.bodySmall),
            ],
          ],
        ],
      ),
    );
  }
}
