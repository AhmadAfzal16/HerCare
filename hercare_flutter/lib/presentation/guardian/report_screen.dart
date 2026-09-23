import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/language_provider.dart';

/// Health Reports screen — Daily / Weekly / Monthly tabs with charts and summaries.
class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _types = ['daily', 'weekly', 'monthly'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        context
            .read<GuardianProvider>()
            .loadReports(type: _types[_tabController.index]);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<GuardianProvider>().loadReports(type: 'weekly');
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<GuardianProvider>();
    final isMother = context.watch<AuthProvider>().user?.role == 'mother';

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.hcTextPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isUrdu ? 'صحت کی رپورٹس' : 'Health Reports',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
        actions: [
          if (isMother)
            IconButton(
              icon: Icon(Icons.add_circle_outline_rounded,
                  color: AppColors.primary),
              tooltip: isUrdu ? 'رپورٹ بنائیں' : 'Generate Report',
              onPressed: provider.isLoading
                  ? null
                  : () => _generateReport(
                        isUrdu,
                        _types[_tabController.index],
                      ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: context.hcTextSecondary,
          indicatorColor: AppColors.primary,
          indicatorWeight: 3,
          tabs: [
            Tab(text: isUrdu ? 'روزانہ' : 'Daily'),
            Tab(text: isUrdu ? 'ہفتہ وار' : 'Weekly'),
            Tab(text: isUrdu ? 'ماہانہ' : 'Monthly'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _types
            .map((type) => _buildReportList(context, provider, isUrdu, type))
            .toList(),
      ),
    );
  }

  Widget _buildReportList(BuildContext context, GuardianProvider provider,
      bool isUrdu, String type) {
    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.error, size: 44),
              const SizedBox(height: 12),
              Text(provider.error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () =>
                    context.read<GuardianProvider>().loadReports(type: type),
                child: Text(isUrdu ? 'دوبارہ کوشش کریں' : 'Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final reports = provider.reportsFor(type);
    if (reports.isEmpty) return _buildEmpty(context, isUrdu, type);

    return RefreshIndicator(
      onRefresh: () => context.read<GuardianProvider>().loadReports(type: type),
      child: ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: reports.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final report = reports[index] as Map<String, dynamic>;
          return _ReportCard(report: report, isUrdu: isUrdu);
        },
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, bool isUrdu, String type) {
    final isMother = context.read<AuthProvider>().user?.role == 'mother';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_rounded, size: 64, color: context.hcTextHint),
            const SizedBox(height: 16),
            Text(
              isUrdu ? 'ابھی کوئی رپورٹ نہیں' : 'No reports yet',
              style: AppTextStyles.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isUrdu
                  ? 'اوپر + بٹن دبائیں رپورٹ بنانے کے لیے'
                  : 'Tap + above to generate your first report',
              style: AppTextStyles.bodySmall,
              textAlign: TextAlign.center,
            ),
            if (isMother) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => _generateReport(isUrdu, type),
                icon: const Icon(Icons.add_rounded),
                label: Text(isUrdu ? 'رپورٹ بنائیں' : 'Generate Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _generateReport(bool isUrdu, String type) async {
    final provider = context.read<GuardianProvider>();
    final generated = await provider.generateReport(type: type);
    if (!mounted) return;
    final err = provider.error;
    if (generated && err == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isUrdu ? '✅ رپورٹ بن گئی' : '✅ Report generated'),
          backgroundColor: AppColors.success,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err ?? 'Could not generate report'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

// ─── Report Card ─────────────────────────────────────────────────────────────

class _ReportCard extends StatelessWidget {
  final Map<String, dynamic> report;
  final bool isUrdu;
  const _ReportCard({required this.report, required this.isUrdu});

  Color _riskColor(String? risk) {
    switch (risk) {
      case 'severe':
        return AppColors.error;
      case 'high':
        return AppColors.error.withOpacity(0.75);
      case 'moderate':
        return AppColors.warning;
      case 'low':
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  String _riskLabel(String? risk, bool isUrdu) {
    switch (risk) {
      case 'severe':
        return isUrdu ? 'شدید' : 'Severe';
      case 'high':
        return isUrdu ? 'زیادہ' : 'High';
      case 'moderate':
        return isUrdu ? 'معتدل' : 'Moderate';
      case 'low':
        return isUrdu ? 'کم' : 'Low';
      default:
        return isUrdu ? 'ڈیٹا دستیاب نہیں' : 'Insufficient data';
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskLevel = report['risk_level'] as String?;
    final epdsScore = report['epds_score'] as int?;
    final avgMood = report['avg_mood'];
    final sleepAvg = report['sleep_avg_h'];
    final moodEntries = report['mood_entries'] as int? ?? 0;
    final periodStart = report['period_start'] as String?;
    final periodEnd = report['period_end'] as String?;

    final color = _riskColor(riskLevel);

    return Container(
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hcOutline),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _riskLabel(riskLevel, isUrdu),
                    style: AppTextStyles.labelSmall.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${_formatDate(periodStart)} — ${_formatDate(periodEnd)}',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),

          // Stats grid
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _StatCell(
                  icon: Icons.psychology_rounded,
                  color: AppColors.primary,
                  label: isUrdu ? 'EPDS' : 'EPDS',
                  value: epdsScore != null ? '$epdsScore/30' : '--',
                ),
                _divider(),
                _StatCell(
                  icon: Icons.sentiment_satisfied_alt_rounded,
                  color: AppColors.secondary,
                  label: isUrdu ? 'اوسط موڈ' : 'Avg Mood',
                  value: avgMood != null ? avgMood.toString() : '--',
                ),
                _divider(),
                _StatCell(
                  icon: Icons.bedtime_rounded,
                  color: AppColors.accent,
                  label: isUrdu ? 'نیند' : 'Sleep',
                  value: sleepAvg != null ? '${sleepAvg}h' : '--',
                ),
                _divider(),
                _StatCell(
                  icon: Icons.edit_note_rounded,
                  color: AppColors.success,
                  label: isUrdu ? 'اندراج' : 'Entries',
                  value: '$moodEntries',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() => Container(
        width: 1,
        height: 40,
        color: AppColors.outline.withOpacity(0.3),
        margin: const EdgeInsets.symmetric(horizontal: 4),
      );
}

class _StatCell extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  const _StatCell({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 4),
          Text(value,
              style: AppTextStyles.titleSmall.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              )),
          Text(label,
              style: AppTextStyles.bodySmall.copyWith(fontSize: 9),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
