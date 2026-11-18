import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../data/models/risk_models.dart';
import '../../providers/risk_provider.dart';

class RecoveryPanel extends StatefulWidget {
  const RecoveryPanel(
      {super.key,
      required this.provider,
      required this.isUrdu,
      this.collapseSummary = false});
  final RiskProvider provider;
  final bool isUrdu;
  final bool collapseSummary;
  @override
  State<RecoveryPanel> createState() => _RecoveryPanelState();
}

class _RecoveryPanelState extends State<RecoveryPanel> {
  int window = 7;
  Map<String, dynamic>? draft;
  String text(String en, String ur) => widget.isUrdu ? ur : en;
  String numeric(Object? value) =>
      value is num && value.isFinite ? value.toStringAsFixed(1) : '—';
  String clock(Object? value) {
    if (value is! num || !value.isFinite || value < 0 || value >= 1440) {
      return '—';
    }
    final minute = value.round() % 1440;
    return '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final provider = widget.provider;
    final periods = (provider.recovery?['periods'] as List?) ?? const [];
    final current = periods
        .whereType<Map>()
        .where((row) => row['window_days'] == window)
        .firstOrNull;
    final change = current?['relative_index_change_percent'];
    final rawMonitoring = provider.recovery?['depression_monitoring'];
    final monitoring = rawMonitoring is Map<String, dynamic>
        ? DepressionMonitoring.fromJson(rawMonitoring)
        : null;
    final summary = [
      if (monitoring != null) ..._monitoringCards(monitoring),
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      text('Your recorded wellbeing change',
                          'آپ کی ریکارڈ شدہ کیفیت میں تبدیلی'),
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [1, 7, 14, 30]
                          .map((days) => ChoiceChip(
                                label: Text(text(
                                    days == 1 ? 'Daily' : '$days days',
                                    days == 1 ? 'روزانہ' : '$days دن')),
                                selected: window == days,
                                onSelected: (_) =>
                                    setState(() => window = days),
                              ))
                          .toList()),
                  const SizedBox(height: 12),
                  if (current == null ||
                      current['direction'] == 'insufficient_data')
                    Text(text(
                        'Not enough comparable check-ins yet. Missing days are not filled in.',
                        'ابھی موازنہ کے لیے کافی اندراجات نہیں ہیں۔ غیر موجود ڈیٹا فرض نہیں کیا جاتا۔'))
                  else ...[
                    Text(
                        change == null
                            ? text(
                                'Index change: ${numeric(current['index_change_points'])} points',
                                'انڈیکس تبدیلی: ${numeric(current['index_change_points'])} پوائنٹس')
                            : text(
                                '${numeric(change)}% change in recorded index',
                                'ریکارڈ شدہ انڈیکس میں ${numeric(change)}% تبدیلی'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: AppColors.primary)),
                    Text(text(
                        'Current: ${numeric((current['current'] as Map?)?['index_mean'])}/100; previous: ${numeric((current['previous'] as Map?)?['index_mean'])}/100',
                        'موجودہ: ${numeric((current['current'] as Map?)?['index_mean'])}/100؛ سابقہ: ${numeric((current['previous'] as Map?)?['index_mean'])}/100')),
                    if (current['mixed_signals'] == true)
                      Text(text(
                          'Mood and screening changes point in different directions.',
                          'موڈ اور اسکریننگ کی تبدیلیاں مختلف سمتوں میں ہیں۔')),
                  ],
                  if (provider.recoveryError != null)
                    Text(text(
                        'Summary temporarily unavailable. Saved records are unchanged.',
                        'خلاصہ عارضی طور پر دستیاب نہیں۔ محفوظ ریکارڈ برقرار ہیں۔')),
                  if (monitoring?.requiresSafetyReview == true)
                    Text(text(
                        'While a safety review is needed, this wellbeing index must not be used as reassurance that depression is improving.',
                        'جب حفاظتی جائزہ ضروری ہو تو اس کیفیت کے انڈیکس کو ڈپریشن میں بہتری کی تسلی کے طور پر استعمال نہ کریں۔')),
                  const SizedBox(height: 8),
                  for (final screen
                      in (provider.recovery?['screening_changes'] as List? ??
                              const [])
                          .whereType<Map>())
                    Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                            '${screen['instrument'].toString().toUpperCase()}: ${screen['previous_score']} → ${screen['current_score']} (${screen['current_date']})')),
                  Text(
                      text(
                          'Descriptive change only—not a diagnosis, clinical recovery percentage or proof of treatment benefit.',
                          'یہ صرف ریکارڈ کی تبدیلی ہے، تشخیص، طبی صحت یابی کا فیصد یا علاج کی کامیابی کا ثبوت نہیں۔'),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ))),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.collapseSummary)
        Card(
          child: ExpansionTile(
            title:
                Text(text('Earlier wellbeing summary', 'کیفیت کا سابقہ خلاصہ')),
            children: summary,
          ),
        )
      else
        ...summary,
      if (provider.modelContext != null)
        Card(
            child: ExpansionTile(
          title:
              Text(text('Optional model details', 'ماڈل کی اختیاری معلومات')),
          subtitle: Text(text(
              'Update living children, affordability and your relationship with your mother-in-law here. Skip anything unknown.',
              'زندہ بچوں کی تعداد، بنیادی ضروریات پوری کرنے کی استطاعت، اور ساس سے تعلق یہاں درج کریں۔ نامعلوم سوال چھوڑ دیں۔')),
          childrenPadding: const EdgeInsets.all(16),
          children: [
            _field(
                'number_of_children',
                text('Number of living children', 'زندہ بچوں کی تعداد'),
                {for (int i = 0; i <= 20; i++) i: '$i'}),
            _field(
                'basic_needs_affordable',
                text('Can you afford basic needs?',
                    'کیا بنیادی ضروریات پوری کرنے کے وسائل ہیں؟'),
                {true: text('Yes', 'ہاں'), false: text('No', 'نہیں')}),
            _field(
                'mother_in_law_relationship',
                text('Relationship with mother-in-law, if applicable',
                    'اگر لاگو ہو تو ساس کے ساتھ تعلق'),
                {
                  'poor': text('Poor', 'مشکل'),
                  'moderate': text('Moderate', 'درمیانہ'),
                  'good': text('Good', 'اچھا')
                }),
            FilledButton(
                onPressed: provider.savingDetails || provider.working
                    ? null
                    : () async {
                        final saved = await provider
                            .saveModelContext(draft ?? provider.modelContext!);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(saved
                                  ? text('Details saved.',
                                      'معلومات محفوظ ہو گئیں۔')
                                  : text('Could not save details.',
                                      'معلومات محفوظ نہیں ہو سکیں۔'))));
                        }
                      },
                child: Text(text(
                    'Save optional details', 'اختیاری معلومات محفوظ کریں'))),
          ],
        )),
      if (provider.research != null)
        Card(
            child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(text('Optional research participation',
                            'تحقیق میں اختیاری شرکت')),
                        value: provider.research?['enabled'] == true,
                        onChanged: provider.savingDetails ||
                                (provider.research?['eligible'] != true &&
                                    provider.research?['enabled'] != true)
                            ? null
                            : (enabled) async {
                                if (enabled) {
                                  final accepted = await showDialog<bool>(
                                      context: context,
                                      builder: (dialogContext) => AlertDialog(
                                              scrollable: true,
                                              title: Text(text(
                                                  'Optional research consent',
                                                  'تحقیق کی اختیاری اجازت')),
                                              content: Text(text(
                                                  'I agree to future aggregate measurements, numeric journal-analysis signals and model outputs being used for the approved HerCare research study. Raw private journals, chats and audio are excluded. Participation is voluntary and is not medical treatment. Withdrawal removes server research copies; exported copies require research-team deletion.',
                                                  'میں منظور شدہ ہر کیئر تحقیق کے لیے آئندہ مجموعی اعداد کے استعمال کی اجازت دیتی ہوں۔ نجی ڈائری، چیٹ اور آڈیو شامل نہیں۔ شرکت اختیاری ہے اور طبی علاج نہیں۔ شرکت ختم کرنے پر سرور کی تحقیقی نقول حذف ہوں گی؛ برآمد شدہ نقول تحقیقی ٹیم حذف کرے گی۔')),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            dialogContext,
                                                            false),
                                                    child: Text(text('Not now',
                                                        'ابھی نہیں'))),
                                                FilledButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            dialogContext,
                                                            true),
                                                    child: Text(text('I agree',
                                                        'میں متفق ہوں')))
                                              ]));
                                  if (accepted != true) return;
                                }
                                await provider.setResearchConsent(enabled);
                              }),
                    Text(text(
                        'Only future aggregate mood, screening, sleep, device and activity measurements, plus numeric journal-analysis and model outputs. No private journal text, chats or audio. Your normal care features do not depend on joining.',
                        'صرف آئندہ موڈ، اسکریننگ، نیند، آلے اور سرگرمی کے مجموعی اعداد اور ڈائری تجزیے اور ماڈل کے عددی نتائج۔ نجی ڈائری متن، چیٹ یا آڈیو شامل نہیں۔ عام سہولتیں شرکت پر منحصر نہیں۔')),
                    const SizedBox(height: 6),
                    Text(
                        text(
                            'Adults only. You may withdraw; server research copies are removed. Previously exported files need controlled deletion by the research team.',
                            'صرف بالغ افراد۔ شرکت ختم کرنے پر سرور کی تحقیقی نقول حذف ہوں گی۔ پہلے برآمد شدہ فائلوں کا حذف کرنا تحقیقی ٹیم کی ذمہ داری ہے۔'),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ))),
    ]);
  }

  List<Widget> _monitoringCards(DepressionMonitoring monitoring) => [
        _summaryCard(
          text('Screening symptom changes', 'اسکریننگ کی علامات میں تبدیلی'),
          [
            if (monitoring.requiresSafetyReview) ...[
              Container(
                key: const ValueKey('monitoring-safety-review'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(text('Safety review needed', 'حفاظتی جائزہ ضروری ہے'),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppColors.error,
                            )),
                    const SizedBox(height: 6),
                    Text(text(
                        'A safety response needs prompt professional support. A lower total score does not cancel this concern. If you or your baby are in immediate danger, contact local emergency help now.',
                        'حفاظت سے متعلق جواب پر جلد پیشہ ورانہ مدد لیں۔ کم مجموعی اسکور اس تشویش کو ختم نہیں کرتا۔ اگر آپ یا بچہ فوری خطرے میں ہیں تو مقامی ہنگامی مدد سے ابھی رابطہ کریں۔')),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (monitoring.screeningTrends.isEmpty)
              Text(text(
                  'Comparable EPDS and PHQ-9 records are not available yet.',
                  'ابھی EPDS اور PHQ-9 کے قابلِ موازنہ ریکارڈ دستیاب نہیں۔')),
            for (final trend in monitoring.screeningTrends)
              _screeningTrend(trend, monitoring.requiresSafetyReview),
            Text(
                text(
                    'Each questionnaire is compared only with its own matching version and language. These are recorded symptoms, not a diagnosis or a clinical recovery percentage.',
                    'ہر سوالنامے کا موازنہ اسی کے یکساں ورژن اور زبان سے ہوتا ہے۔ یہ ریکارڈ شدہ علامات ہیں، تشخیص یا طبی صحت یابی کا فیصد نہیں۔'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        _summaryCard(
          text('Future depression outlook', 'آئندہ ڈپریشن کا جائزہ'),
          [
            Text(
                text('Future probability: not available',
                    'آئندہ امکان: دستیاب نہیں'),
                key: const ValueKey('future-probability-unavailable'),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(text(
                'The follow-up model is not trained and validated yet. Genuine dated follow-up outcomes are needed before HerCare can estimate whether new symptoms may appear. Missing probability is not 0%.',
                'فالو اپ ماڈل ابھی تربیت یافتہ اور تصدیق شدہ نہیں۔ نئی علامات کے امکان کا اندازہ لگانے کے لیے حقیقی تاریخ وار فالو اپ نتائج ضروری ہیں۔ غیر موجود امکان کا مطلب صفر فیصد نہیں۔')),
            const SizedBox(height: 6),
            Text(
                text(
                    'The separate research baseline does not predict future onset. Screening positivity also does not confirm depression.',
                    'الگ تحقیقی بنیادی ماڈل مستقبل میں آغاز کی پیش گوئی نہیں کرتا۔ مثبت اسکریننگ بھی ڈپریشن کی تصدیق نہیں ہے۔'),
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
        _summaryCard(
          text('Supporting daily records', 'معاون روزانہ ریکارڈ'),
          [
            Text(text('Mood', 'موڈ'),
                style: Theme.of(context).textTheme.titleSmall),
            Text(text(
                'Daily mood check-ins support the picture, but do not establish whether depression has improved.',
                'روزانہ موڈ کے اندراجات معاون ہیں، لیکن ڈپریشن میں بہتری کی تصدیق نہیں کرتے۔')),
            const SizedBox(height: 12),
            Text(text('Sleep', 'نیند'),
                style: Theme.of(context).textTheme.titleSmall),
            Text(text(
                'Self-reported sleep duration, quality, awakenings and timing are shown separately. More sleep alone is not proof of recovery.',
                'خود درج کی گئی نیند کی مدت، معیار، بیداری اور اوقات الگ دکھائے جاتے ہیں۔ صرف زیادہ نیند صحت یابی کا ثبوت نہیں۔')),
            for (final row in monitoring.sleep.windows
                .where((row) => row['window_days'] == window))
              _sleepWindow(row),
            if (monitoring.sleep.windows.isEmpty ||
                monitoring.sleep.status == 'insufficient_data')
              Text(text(
                  'Not enough comparable sleep records yet. Missing records are not invented.',
                  'ابھی نیند کے قابلِ موازنہ ریکارڈ کافی نہیں۔ غیر موجود ریکارڈ فرض نہیں کیے جاتے۔')),
          ],
        ),
      ];

  Widget _summaryCard(String title, List<Widget> children) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );

  Widget _screeningTrend(ScreeningSymptomTrend trend, bool safetyReview) {
    final instrument =
        trend.instrument == 'phq9' ? 'PHQ-9' : trend.instrument.toUpperCase();
    final comparable = !trend.stale &&
        trend.previousScore != null &&
        trend.currentScore != null &&
        trend.scoreChangePoints != null &&
        trend.direction != 'insufficient_data';
    final direction = switch (trend.direction) {
      'lower_recorded_symptoms' =>
        text('Lower recorded symptom score', 'ریکارڈ شدہ علامات کا اسکور کم'),
      'higher_recorded_symptoms' => text(
          'Higher recorded symptom score', 'ریکارڈ شدہ علامات کا اسکور زیادہ'),
      'no_change' => text('Recorded score unchanged', 'ریکارڈ شدہ اسکور یکساں'),
      _ => text('Not enough comparable tests', 'قابلِ موازنہ ٹیسٹ کافی نہیں'),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(instrument, style: Theme.of(context).textTheme.titleSmall),
          if (trend.currentScore != null)
            Text(text(
                'Latest recorded score: ${numeric(trend.currentScore)} (${trend.currentDate ?? '—'})',
                'تازہ ریکارڈ شدہ اسکور: ${numeric(trend.currentScore)} (${trend.currentDate ?? '—'})')),
          if (comparable) ...[
            Text(
                '${numeric(trend.previousScore)} → ${numeric(trend.currentScore)}; ${numeric(trend.scoreChangePoints)} ${text('score points', 'اسکور پوائنٹس')}'),
            Text(safetyReview && trend.direction == 'lower_recorded_symptoms'
                ? text('Lower total recorded; safety review is still needed.',
                    'مجموعی اسکور کم درج ہوا؛ حفاظتی جائزہ پھر بھی ضروری ہے۔')
                : direction),
          ] else
            Text(trend.stale
                ? text(
                    'The latest test is older than its follow-up schedule. Take the next scheduled test before interpreting a current trend.',
                    'تازہ ٹیسٹ فالو اپ وقت سے پرانا ہے۔ موجودہ رجحان سمجھنے سے پہلے اگلا مقررہ ٹیسٹ مکمل کریں۔')
                : text(
                    'Not enough comparable tests yet. No improvement or worsening is inferred.',
                    'ابھی قابلِ موازنہ ٹیسٹ کافی نہیں۔ بہتری یا خرابی فرض نہیں کی جاتی۔')),
        ],
      ),
    );
  }

  Widget _sleepWindow(Map<String, dynamic> row) {
    final previous = row['previous'] is Map ? row['previous'] as Map : const {};
    final current = row['current'] is Map ? row['current'] as Map : const {};
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text(
              'Selected window: $window days', 'منتخب دورانیہ: $window دن')),
          Text(text(
              'Sleep minutes: ${numeric(previous['sleep_minutes_mean'])} → ${numeric(current['sleep_minutes_mean'])}',
              'نیند کے منٹ: ${numeric(previous['sleep_minutes_mean'])} → ${numeric(current['sleep_minutes_mean'])}')),
          Text(text(
              'Awakenings: ${numeric(previous['awakenings_mean'])} → ${numeric(current['awakenings_mean'])}',
              'بیداری کی تعداد: ${numeric(previous['awakenings_mean'])} → ${numeric(current['awakenings_mean'])}')),
          Text(text(
              'Quality (1–5): ${numeric(previous['quality_mean'])} → ${numeric(current['quality_mean'])}',
              'معیار (۱ تا ۵): ${numeric(previous['quality_mean'])} → ${numeric(current['quality_mean'])}')),
          Text(text(
              'Average bedtime: ${clock((previous['bedtime_minute'] as Map?)?['mean_minute'])} → ${clock((current['bedtime_minute'] as Map?)?['mean_minute'])}',
              'اوسط سونے کا وقت: ${clock((previous['bedtime_minute'] as Map?)?['mean_minute'])} → ${clock((current['bedtime_minute'] as Map?)?['mean_minute'])}')),
          Text(text(
              'Average wake time: ${clock((previous['wake_minute'] as Map?)?['mean_minute'])} → ${clock((current['wake_minute'] as Map?)?['mean_minute'])}',
              'اوسط جاگنے کا وقت: ${clock((previous['wake_minute'] as Map?)?['mean_minute'])} → ${clock((current['wake_minute'] as Map?)?['mean_minute'])}')),
          if (row['status'] == 'insufficient_data')
            Text(text('Coverage is too low for a reliable comparison.',
                'قابلِ اعتماد موازنے کے لیے اندراجات کافی نہیں۔')),
        ],
      ),
    );
  }

  Widget _field(String key, String label, Map<Object, String> values) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label),
          const SizedBox(height: 6),
          DropdownButtonFormField<Object>(
            initialValue:
                (draft ?? widget.provider.modelContext)?[key] ?? 'unknown',
            isExpanded: true,
            items: [
              DropdownMenuItem(
                  value: 'unknown',
                  child: Text(
                      text('Unknown / not applicable', 'نامعلوم / لاگو نہیں'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
              ...values.entries.map((value) => DropdownMenuItem(
                  value: value.key,
                  child: Text(value.value,
                      maxLines: 1, overflow: TextOverflow.ellipsis)))
            ],
            onChanged: (value) => setState(() {
              draft ??=
                  Map<String, dynamic>.from(widget.provider.modelContext!);
              draft![key] = value == 'unknown' ? null : value;
            }),
          )
        ]),
      );
}
