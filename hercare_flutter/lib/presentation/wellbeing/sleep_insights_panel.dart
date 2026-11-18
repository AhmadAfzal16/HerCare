import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../core/routing/app_router.dart';
import '../../data/models/sleep_models.dart';
import '../../providers/language_provider.dart';

class SleepInsightsPanel extends StatefulWidget {
  const SleepInsightsPanel(
      {super.key, required this.insights, this.cached = false});
  final SleepInsights insights;
  final bool cached;
  @override
  State<SleepInsightsPanel> createState() => _SleepInsightsPanelState();
}

class _SleepInsightsPanelState extends State<SleepInsightsPanel> {
  int _days = 7;
  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    String tr(String en, String urdu) => ur ? urdu : en;
    final insights = widget.insights;
    final selected = insights.windows.firstWhere((w) => w.days == _days);
    final correlation = insights.correlation;
    String duration(double value) =>
        '${value ~/ 60}${tr('h', 'گھ')} ${value.round() % 60}${tr('m', 'م')}';
    Widget card(String title, List<Widget> children) => Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ...children
                ])));
    final trendText = switch (selected.direction) {
      'less_recorded_sleep' => tr(
          'Less recorded sleep than the previous period',
          'پچھلی مدت سے کم نیند درج ہوئی'),
      'more_recorded_sleep' => tr(
          'More recorded sleep than the previous period',
          'پچھلی مدت سے زیادہ نیند درج ہوئی'),
      'similar_recorded_sleep' =>
        tr('Similar recorded sleep', 'درج نیند تقریباً ایک جیسی ہے'),
      _ => insights.stale
          ? tr('Recent sleep records are needed for a current comparison.',
              'حالیہ موازنہ کے لیے نئی نیند کا ریکارڈ درکار ہے۔')
          : tr('Not enough recorded nights in both periods to compare.',
              'دونوں مدتوں میں موازنہ کے لیے کافی راتیں درج نہیں۔'),
    };
    final associationText = switch (correlation.status) {
      'stale' => tr(
          'The matched sleep and mood records are old. No current association is shown.',
          'نیند اور موڈ کے مشترک ریکارڈ پرانے ہیں۔ موجودہ تعلق نہیں دکھایا جا رہا۔'),
      'no_variation' => tr(
          'These records do not vary enough to calculate an association.',
          'ان ریکارڈ میں تعلق حساب کرنے کے لیے کافی فرق نہیں۔'),
      'available' => switch (correlation.direction) {
          'positive' => tr(
              'Longer recorded sleep tended to go with higher recorded mood.',
              'زیادہ درج نیند کے ساتھ موڈ بھی نسبتاً زیادہ درج ہوا۔'),
          'negative' => tr(
              'Longer recorded sleep tended to go with lower recorded mood. Other factors may be involved.',
              'زیادہ درج نیند کے ساتھ موڈ نسبتاً کم درج ہوا۔ دوسری وجوہات بھی ہو سکتی ہیں۔'),
          _ => tr('No clear sleep–mood pattern in the matched records.',
              'مشترک ریکارڈ میں نیند اور موڈ کا واضح تعلق نہیں۔'),
        },
      _ => tr(
          'Build this card naturally with your regular sleep and mood check-ins. No extra questionnaire.',
          'اپنے معمول کے نیند اور موڈ اندراج سے یہ کارڈ بنے گا۔ اضافی سوالنامہ نہیں۔'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      card(tr('Your recorded sleep trends', 'آپ کی درج نیند کے رجحانات'), [
        Text('${tr('As of', 'تاریخ')}: ${insights.asOf}'),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final days in [7, 14, 30])
            ChoiceChip(
                key: ValueKey('sleep-window-$days'),
                label: Text('$days ${tr('days', 'دن')}'),
                selected: _days == days,
                onSelected: (_) => setState(() => _days = days))
        ]),
        const SizedBox(height: 12),
        Text(
            '${tr('Recorded nights', 'درج راتیں')}: ${selected.nights}/$_days'),
        if (selected.average != null)
          Text(
              '${tr('Average estimate', 'اوسط اندازہ')}: ${duration(selected.average!)}'),
        if (selected.quality != null)
          Text(
              '${tr('Recorded quality', 'درج معیار')}: ${selected.quality!.toStringAsFixed(1)}/5'),
        const SizedBox(height: 10),
        Text(trendText),
        if (selected.change != null)
          Text(
              '${tr('Average difference', 'اوسط فرق')}: ${selected.change!.round()} ${tr('minutes', 'منٹ')}'),
        if (selected.direction == 'insufficient_data' && !insights.stale)
          Text(tr(
              'At least ${selected.minimum} nights in each period are needed. Missing days are not filled in.',
              'ہر مدت میں کم از کم ${selected.minimum} راتیں درکار ہیں۔ خالی دن خود سے نہیں بھرے جاتے۔')),
        if (insights.patterns.isNotEmpty) ...[
          const Divider(height: 24),
          for (final pattern in insights.patterns)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(switch (pattern) {
                  'repeated_short_sleep' => tr(
                      'Several recent estimates were under six hours. Consider asking a trusted person for help making time to rest.',
                      'کئی حالیہ اندازے چھ گھنٹے سے کم ہیں۔ آرام کے لیے وقت نکالنے میں قابل اعتماد شخص سے مدد مانگنے پر غور کریں۔'),
                  'less_sleep_than_previous_period' => tr(
                      'Less sleep is recorded than before; this alone does not mean mental health is worsening.',
                      'پہلے سے کم نیند درج ہے؛ صرف اس سے ذہنی صحت خراب ہونے کا فیصلہ نہیں ہوتا۔'),
                  _ => tr(
                      'Recorded bed/wake times vary. Baby care can disrupt routines; seek support if rest remains difficult.',
                      'درج سونے اور جاگنے کے اوقات بدلتے ہیں۔ بچے کی دیکھ بھال سے معمول بدل سکتا ہے؛ آرام مشکل رہے تو مدد لیں۔'),
                })),
        ],
      ]),
      card(tr('Sleep & mood connection', 'نیند اور موڈ کا تعلق'), [
        Text(associationText),
        const SizedBox(height: 8),
        Text(
            '${tr('Same-date pairs in 30 days', '۳۰ دن میں ایک تاریخ کے مشترک اندراج')}: ${correlation.pairs}/${correlation.minimum}'),
        if (correlation.status == 'available' &&
            correlation.shortMood != null &&
            correlation.longerMood != null) ...[
          const SizedBox(height: 12),
          Text(tr(
              'Mood average on under-6-hour dates: ${correlation.shortMood!.toStringAsFixed(1)}/5 (${correlation.shortDays} days)',
              'چھ گھنٹے سے کم والی تاریخوں کا اوسط موڈ: ${correlation.shortMood!.toStringAsFixed(1)}/5 (${correlation.shortDays} دن)')),
          Text(tr(
              'Mood average on 6+ hour dates: ${correlation.longerMood!.toStringAsFixed(1)}/5 (${correlation.longerDays} days)',
              'چھ یا زیادہ گھنٹوں والی تاریخوں کا اوسط موڈ: ${correlation.longerMood!.toStringAsFixed(1)}/5 (${correlation.longerDays} دن)')),
        ],
        const SizedBox(height: 10),
        Text(
            tr('An observed association, not proof of cause, depression or recovery. All figures are self-reported estimates.',
                'یہ درج ریکارڈ کا تعلق ہے، وجہ، ڈیپریشن یا صحت یابی کا ثبوت نہیں۔ تمام اعداد آپ کے اپنے اندازے ہیں۔'),
            style: Theme.of(context).textTheme.bodySmall),
        if (correlation.coefficient != null)
          ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(tr('How this is calculated', 'حساب کیسے ہوتا ہے')),
              children: [
                Text(tr(
                    'Rank correlation (Spearman): ${correlation.coefficient!.toStringAsFixed(2)}. Only matched dates are used; no missing values are invented.',
                    'رتبوں کا تعلق (اسپیئر مین): ${correlation.coefficient!.toStringAsFixed(2)}۔ صرف مشترک تاریخیں استعمال ہوتی ہیں، خالی اعداد نہیں بنائے جاتے۔'))
              ]),
      ]),
      if (insights.digital != null)
        card(
            tr('Shared phone-usage records', 'شیئر شدہ فون استعمال کا ریکارڈ'),
            [
              Text(insights.digital!.sharingEnabled
                  ? tr(
                      'Aggregate records available for ${insights.digital!.days} of the last 7 days.',
                      'پچھلے ۷ دنوں میں ${insights.digital!.days} دنوں کا مجموعی ریکارڈ موجود ہے۔')
                  : tr(
                      'Phone-usage sharing is off. Local usage access does not turn sharing on.',
                      'فون کے استعمال کی شیئرنگ بند ہے۔ مقامی رسائی خود شیئرنگ شروع نہیں کرتی۔')),
              if (insights.digital!.socialMinutes != null)
                Text(
                    '${tr('Average social-app use', 'سوشل ایپس کا اوسط')}: ${duration(insights.digital!.socialMinutes!)}'),
              if (insights.digital!.lateMinutes != null)
                Text(
                    '${tr('Average midnight–5am use', 'رات ۱۲ تا ۵ اوسط')}: ${duration(insights.digital!.lateMinutes!)}'),
              if (insights.digital!.lateDays > 0)
                Text(tr(
                    'Night use was recorded on ${insights.digital!.lateDays} days. A short wind-down may help.',
                    '${insights.digital!.lateDays} دن رات کا استعمال درج ہوا۔ مختصر آرام کی سرگرمی پر غور کریں۔')),
              Text(
                  tr('Stored aggregates, not live permissions or a clinical distress score.',
                      'محفوظ مجموعی اعداد، موجودہ اجازت یا طبی پریشانی کا اسکور نہیں۔'),
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
      card(tr('One gentle next step', 'ایک نرم اگلا قدم'), [
        Text(insights.safetyPriority
            ? tr(
                'A safety concern is recorded. Open Immediate Help; an activity must not replace support.',
                'حفاظت سے متعلق تشویش درج ہے۔ فوری مدد کھولیں؛ سرگرمی مدد کا متبادل نہیں۔')
            : tr(
                'If comfortable, try a short activity. If tiredness or sleep difficulty persists, discuss it with a qualified health professional.',
                'اگر مناسب لگے تو مختصر سرگرمی کریں۔ تھکن یا نیند کا مسئلہ برقرار رہے تو مستند طبی ماہر سے بات کریں۔')),
        if (widget.cached)
          Text(tr('These are saved observations, not a live safety assessment.',
              'یہ محفوظ مشاہدات ہیں، موجودہ حفاظت کا جائزہ نہیں۔')),
        const SizedBox(height: 12),
        FilledButton.icon(
            key: const ValueKey('sleep-activity'),
            onPressed: () => context.push(insights.activity == 'crisis'
                ? AppRoutes.crisis
                : insights.activity == 'body_scan'
                    ? '${AppRoutes.meditation}?id=body_scan'
                    : '${AppRoutes.breathing}?id=box_breathing'),
            icon: Icon(insights.safetyPriority
                ? Icons.health_and_safety_outlined
                : Icons.spa_outlined),
            label: Text(insights.safetyPriority
                ? tr('Immediate help', 'فوری مدد')
                : tr('Open a short activity', 'مختصر سرگرمی کھولیں'))),
        if (!insights.safetyPriority)
          TextButton(
              onPressed: () => context.push(AppRoutes.crisis),
              child: Text(tr('Need immediate help?', 'فوری مدد درکار ہے؟'))),
      ]),
    ]);
  }
}
