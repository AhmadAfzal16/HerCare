import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/language_provider.dart';
import '../../providers/screening_provider.dart';

class ScreeningHistoryScreen extends StatefulWidget {
  const ScreeningHistoryScreen({super.key});

  @override
  State<ScreeningHistoryScreen> createState() => _ScreeningHistoryScreenState();
}

class _ScreeningHistoryScreenState extends State<ScreeningHistoryScreen> {
  String _type = 'epds';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ScreeningProvider>().loadOverview(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScreeningProvider>();
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final history = provider.history;
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        title: Text(_type == 'phq9'
            ? (isUrdu ? 'PHQ-9 کی تاریخ' : 'PHQ-9 history')
            : (isUrdu ? 'EPDS کی تاریخ' : 'EPDS history')),
        actions: [
          PopupMenuButton<String>(
            tooltip: isUrdu ? 'جانچ منتخب کریں' : 'Choose screening',
            initialValue: _type,
            onSelected: (value) {
              setState(() => _type = value);
              context.read<ScreeningProvider>().loadHistory(type: value);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'epds', child: Text('EPDS')),
              PopupMenuItem(value: 'phq9', child: Text('PHQ-9')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(
          _type == 'phq9' ? AppRoutes.phq9 : AppRoutes.epds,
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text(isUrdu ? 'نئی جانچ' : 'New screening'),
      ),
      body: SafeArea(
        child: history.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Text(
                    isUrdu
                        ? 'ابھی تک کوئی مکمل اسکریننگ موجود نہیں۔'
                        : 'No completed screenings yet.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.bodyLarge,
                  ),
                ),
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 96),
                itemCount: history.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = history[index];
                  final color = _riskColor(item.riskLevel);
                  final completed = item.completedAt?.toLocal();
                  final date = completed == null
                      ? '--'
                      : '${completed.day.toString().padLeft(2, '0')}/'
                          '${completed.month.toString().padLeft(2, '0')}/'
                          '${completed.year}';
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: context.hcSurface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: color.withValues(alpha: .3)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: color.withValues(alpha: .12),
                          foregroundColor: color,
                          child: Text('${item.totalScore ?? 0}'),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${item.instrumentType.toUpperCase()} · $date',
                                  style: AppTextStyles.titleSmall),
                              const SizedBox(height: 3),
                              Text(
                                '${_riskLabel(item.riskLevel, isUrdu)} · ${item.totalScore}/${item.instrumentType == 'phq9' ? 27 : 30}',
                                style: AppTextStyles.bodySmall
                                    .copyWith(color: color),
                              ),
                            ],
                          ),
                        ),
                        if (item.selfHarmPositive)
                          const Icon(Icons.health_and_safety_rounded,
                              color: AppColors.error),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }

  Color _riskColor(String? risk) => switch (risk) {
        'moderate' => AppColors.warning,
        'high' => Colors.deepOrange,
        'severe' => AppColors.error,
        _ => AppColors.success,
      };

  String _riskLabel(String? risk, bool isUrdu) => switch (risk) {
        'moderate' => isUrdu ? 'درمیانی' : 'Moderate',
        'high' => isUrdu ? 'زیادہ' : 'High',
        'severe' => isUrdu ? 'شدید' : 'Severe',
        _ => isUrdu ? 'کم' : 'Low',
      };
}
