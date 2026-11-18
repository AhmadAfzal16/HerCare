import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/routing/app_router.dart';
import '../../providers/risk_provider.dart';
import '../crisis/care_directory_screen.dart';

typedef _Translate = String Function(String english, String urdu);

class M4ReportPanel extends StatefulWidget {
  const M4ReportPanel({
    super.key,
    required this.provider,
    required this.isUrdu,
  });

  final RiskProvider provider;
  final bool isUrdu;

  @override
  State<M4ReportPanel> createState() => _M4ReportPanelState();
}

class _M4ReportPanelState extends State<M4ReportPanel> {
  String _period = 'weekly';
  String _t(String en, String ur) => widget.isUrdu ? ur : en;

  @override
  Widget build(BuildContext context) {
    final data = widget.provider.m4;
    final report = _list(data?['reports'])
        .whereType<Map>()
        .where((item) => item['period'] == _period)
        .firstOrNull;
    final asOf = _day(data?['as_of']);
    final checkin = _map(data?['checkin']);
    final answers = <String, int?>{
      for (final key in _checkinKeys)
        key: checkin['date'] == asOf && checkin[key] is int
            ? checkin[key] as int
            : null,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  _t('My progress and early warnings',
                      'میری کیفیت اور ابتدائی اشارے'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (report == null)
                Text(_t('Report unavailable. Refresh to try again.',
                    'رپورٹ دستیاب نہیں۔ دوبارہ کوشش کریں۔'))
              else ...[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final option in const [
                      ('daily', 'Daily', 'روزانہ'),
                      ('weekly', 'Weekly', 'ہفتہ وار'),
                      ('fortnightly', '14 days', '۱۴ دن'),
                      ('overall', 'Overall', 'مجموعی'),
                    ])
                      ChoiceChip(
                        label: Text(_t(option.$2, option.$3)),
                        selected: _period == option.$1,
                        onSelected: (_) => setState(() => _period = option.$1),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                _ReportBody(
                  report: report,
                  asOf: asOf,
                  tr: _t,
                  safetyPriority: data?['safety_priority'] == true,
                ),
              ],
              const SizedBox(height: 12),
              Text(
                _t(
                  'The 14-day probability forecast is unavailable. These reports summarize recorded information.',
                  '۱۴ دن کے امکان کی پیش گوئی دستیاب نہیں۔ یہ رپورٹس درج شدہ معلومات کا خلاصہ ہیں۔',
                ),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      if (data != null && asOf != null) ...[
        _ContextCheckin(
          key: ValueKey((asOf, answers.values.join('|'))),
          tr: _t,
          provider: widget.provider,
          answers: answers,
          asOf: asOf,
        ),
        Card(
          child: SwitchListTile.adaptive(
            title: Text(_t('Include private text patterns',
                'نجی تحریر کے اشارے شامل کریں')),
            subtitle: Text(_t(
                'With this on, new journal entries, confirmed voice transcripts, and your own Hum-Raaz messages can contribute short distress summaries to this report. Turning it off deletes these report summaries.',
                'اس اجازت کے بعد نئی ڈائری، تصدیق شدہ صوتی متن اور ہم راز کو بھیجے گئے آپ کے پیغامات سے پریشانی کے مختصر خلاصے اس رپورٹ میں شامل ہو سکتے ہیں۔ اجازت بند کرنے سے یہ خلاصے حذف ہو جائیں گے۔')),
            value: data['text_enabled'] == true,
            onChanged: widget.provider.savingDetails || widget.provider.working
                ? null
                : (value) => widget.provider.setM4TextConsent(value),
          ),
        ),
      ],
    ]);
  }
}

const _checkinKeys = [
  'financial_strain',
  'relationship_strain',
  'support_gap',
  'recovery_difficulty',
];

class _ContextCheckin extends StatefulWidget {
  const _ContextCheckin({
    super.key,
    required this.tr,
    required this.provider,
    required this.answers,
    required this.asOf,
  });

  final _Translate tr;
  final RiskProvider provider;
  final Map<String, int?> answers;
  final String asOf;

  @override
  State<_ContextCheckin> createState() => _ContextCheckinState();
}

class _ContextCheckinState extends State<_ContextCheckin> {
  late final _answers = Map<String, int?>.of(widget.answers);

  @override
  Widget build(BuildContext context) {
    final tr = widget.tr;
    final busy = widget.provider.savingDetails || widget.provider.working;
    final questions = [
      tr('How difficult was it to pay for essentials?',
          'بنیادی ضروریات پوری کرنا کتنا مشکل تھا؟'),
      tr('How much strain did relationships at home cause, including with your mother-in-law if applicable?',
          'گھر کے تعلقات سے کتنی پریشانی ہوئی، اگر لاگو ہو تو ساس کے ساتھ تعلق بھی شامل کریں؟'),
      tr('When you needed help, how often did you get enough?',
          'جب مدد کی ضرورت تھی تو کتنی بار کافی مدد ملی؟'),
      tr('How much did pain, illness, or recovery after childbirth make daily care harder?',
          'درد، بیماری یا زچگی کے بعد صحت یابی کی وجہ سے روزمرہ دیکھ بھال کتنی مشکل ہوئی؟'),
    ];
    final strainChoices = [
      tr('None', 'بالکل نہیں'),
      tr('A little', 'تھوڑی'),
      tr('Quite a bit', 'کافی'),
      tr('A lot', 'بہت زیادہ'),
    ];
    final choices = [
      [
        tr('Not difficult', 'مشکل نہیں'),
        tr('A little difficult', 'تھوڑا مشکل'),
        tr('Quite difficult', 'کافی مشکل'),
        tr('Very difficult', 'بہت مشکل'),
      ],
      strainChoices,
      [
        tr('Always', 'ہمیشہ'),
        tr('Usually', 'اکثر'),
        tr('Sometimes', 'کبھی کبھی'),
        tr('Rarely or never', 'بہت کم یا کبھی نہیں'),
      ],
      strainChoices,
    ];
    final changed =
        _checkinKeys.any((key) => _answers[key] != widget.answers[key]);
    return Card(
      child: ExpansionTile(
        title: Text(tr('What changed this week?', 'اس ہفتے کیا بدلا؟')),
        subtitle: Text(tr('Optional • Past 7 days', 'اختیاری • پچھلے ۷ دن')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Check-in for ${widget.asOf}', '${widget.asOf} کا اندراج')),
          const SizedBox(height: 12),
          for (var index = 0; index < _checkinKeys.length; index++) ...[
            Text(questions[index],
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final value in <int?>[0, 1, 2, 3, null])
                  ChoiceChip(
                    key: ValueKey('m4-${_checkinKeys[index]}-$value'),
                    label: Text(value == null
                        ? index == 2
                            ? tr('Skip / no help needed',
                                'چھوڑیں / مدد درکار نہیں تھی')
                            : tr('Skip / not applicable', 'چھوڑیں / لاگو نہیں')
                        : choices[index][value]),
                    selected: _answers[_checkinKeys[index]] == value,
                    onSelected: busy
                        ? null
                        : (_) => setState(() {
                              _answers[_checkinKeys[index]] = value;
                            }),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          FilledButton(
            key: const ValueKey('m4-save-context'),
            onPressed: busy || !changed
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final saved = await widget.provider.saveM4Checkin(
                      Map.of(_answers),
                      date: widget.asOf,
                    );
                    if (!messenger.mounted) return;
                    messenger.showSnackBar(SnackBar(
                      content: Text(saved
                          ? tr('Check-in saved.', 'اندراج محفوظ ہو گیا۔')
                          : tr(
                              'Could not save. Review the check-in date and try again.',
                              'اندراج محفوظ نہیں ہوا۔ تاریخ دیکھ کر دوبارہ کوشش کریں۔')),
                    ));
                  },
            child: Text(tr('Save check-in', 'اندراج محفوظ کریں')),
          ),
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({
    required this.report,
    required this.asOf,
    required this.tr,
    required this.safetyPriority,
  });

  final Map report;
  final String? asOf;
  final _Translate tr;
  final bool safetyPriority;

  @override
  Widget build(BuildContext context) {
    final score = _number(report['score']);
    final coverage = _number(report['coverage']);
    final maxWithMissing = _number(report['score_max_with_missing']);
    final screenings = _map(report['screenings']);
    final level = safetyPriority ? 'safety_priority' : report['level'];
    final findingKeys = _list(report['findings']);
    final start = _day(report['start_date']);
    final end = _day(report['end_date']) ?? asOf;
    final label = switch (level) {
      'safety_priority' => tr('Immediate help', 'فوری مدد'),
      'screening_elevated' =>
        tr('Elevated screening result', 'اسکریننگ اسکور زیادہ ہے'),
      'early_warning' => tr('A change to check in on', 'توجہ طلب تبدیلی'),
      'monitor' when findingKeys.contains('supporting_changes') =>
        tr('Changes worth checking', 'توجہ طلب تبدیلیاں'),
      'monitor' => tr('Continue check-ins', 'اندراج جاری رکھیں'),
      _ => tr('More screening history needed', 'مزید اسکریننگ کی ضرورت ہے'),
    };
    final direction = switch (report['direction']) {
      'improving' => tr('Comparable screening scores decreased.',
          'قابلِ موازنہ اسکریننگ اسکور کم ہوئے۔'),
      'worsening' => tr('Comparable screening scores increased.',
          'قابلِ موازنہ اسکریننگ اسکور بڑھے۔'),
      'unchanged' => tr('Comparable screening scores were unchanged.',
          'قابلِ موازنہ اسکریننگ اسکور یکساں رہے۔'),
      'mixed' => tr('Screening scores moved in different directions.',
          'اسکریننگ اسکور مختلف سمتوں میں بدلے۔'),
      _ => tr('There are too few comparable screenings to describe a change.',
          'تبدیلی بتانے کے لیے قابلِ موازنہ اسکریننگ کافی نہیں۔'),
    };
    final groups = _list(report['groups']).whereType<Map>();
    final findings = findingKeys.map(_finding).whereType<String>();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (end != null)
          Text(start == null || start == end ? end : '$start – $end'),
        if (report['period'] == 'overall')
          Text(tr('Last 30 days and recent screening history',
              'گزشتہ ۳۰ دن اور حالیہ اسکریننگ')),
        const SizedBox(height: 6),
        Text(label,
            style: theme.textTheme.titleMedium?.copyWith(
                color: level == 'safety_priority'
                    ? theme.colorScheme.error
                    : null)),
        if (score != null && level != 'safety_priority') ...[
          const SizedBox(height: 8),
          Text(
              tr('${score.toStringAsFixed(1)} / 100 concern points',
                  'تشویش کے ${score.toStringAsFixed(1)} / 100 پوائنٹس'),
              style: theme.textTheme.titleLarge),
          Text(tr('Points summarize the available records.',
              'پوائنٹس دستیاب اندراجات کا خلاصہ ہیں۔')),
          if (maxWithMissing != null && maxWithMissing > score)
            Text(
              tr(
                'If every missing measure had its maximum value, the total would be ${maxWithMissing.toStringAsFixed(1)}.',
                'اگر ہر غیر دستیاب پیمانے کی زیادہ سے زیادہ قدر شامل ہو تو مجموعہ ${maxWithMissing.toStringAsFixed(1)} ہوگا۔',
              ),
              style: theme.textTheme.bodySmall,
            ),
        ],
        if (coverage != null)
          Text(tr('Data coverage ${coverage.toStringAsFixed(0)}%',
              'دستیاب معلومات ${coverage.toStringAsFixed(0)}%')),
        const SizedBox(height: 8),
        Text(direction),
        for (final instrument in ['epds', 'phq9'])
          _screening(instrument, _map(screenings[instrument])),
        if (findings.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final finding in findings)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text('• $finding'),
            ),
        ],
        const SizedBox(height: 12),
        _nextStep(
            context,
            level == 'safety_priority'
                ? 'immediate_help'
                : report['next_step']),
        if (groups.isNotEmpty)
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 8),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            title: Text(tr('Score details', 'اسکور کی تفصیل')),
            children: [
              for (final group in groups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_group(group)),
                ),
            ],
          ),
      ],
    );
  }

  Widget _screening(String instrument, Map data) {
    final label = instrument == 'epds' ? 'EPDS' : 'PHQ-9';
    final latest = _number(data['latest_score']);
    final previous =
        data['comparable'] == true ? _number(data['previous_score']) : null;
    final date = _day(data['latest_date']);
    if (latest == null || date == null) return const SizedBox.shrink();
    final values = previous == null
        ? latest.toStringAsFixed(0)
        : '${previous.toStringAsFixed(0)} → ${latest.toStringAsFixed(0)}';
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text('$label  $values  ($date)'),
    );
  }

  String _group(Map group) {
    final name = switch (group['key']) {
      'epds' => 'EPDS',
      'phq9' => 'PHQ-9',
      'mood_energy' => tr('Mood and energy', 'موڈ اور توانائی'),
      'sleep' => tr('Sleep', 'نیند'),
      'support' => tr('Social support', 'سماجی معاونت'),
      'weekly_context' => tr('Life circumstances', 'روزمرہ حالات'),
      'background' || 'profile_context' => tr('Background', 'پس منظر'),
      'text' => tr('Private text patterns', 'نجی تحریر کے اشارے'),
      'phone' => tr('Phone signals', 'فون کے اشارے'),
      _ => tr('Other records', 'دیگر اندراجات'),
    };
    final points = _number(group['points']);
    final weight = _number(group['weight']);
    final coverage = _number(group['coverage']);
    if (points == null || weight == null) {
      return '$name · ${tr('Unavailable', 'دستیاب نہیں')}';
    }
    final contribution =
        '${points.toStringAsFixed(1)} / ${weight.toStringAsFixed(0)}';
    return coverage == null
        ? '$name · $contribution'
        : '$name · $contribution · ${tr('${coverage.toStringAsFixed(0)}% coverage', '${coverage.toStringAsFixed(0)}% معلومات دستیاب')}';
  }

  String? _finding(Object? value) => switch (value) {
        'epds_rising' => tr('EPDS rose since the earlier screening.',
            'پچھلی اسکریننگ کے بعد EPDS بڑھا۔'),
        'epds_falling' => tr('EPDS fell since the earlier screening.',
            'پچھلی اسکریننگ کے بعد EPDS کم ہوا۔'),
        'epds_persistent_rise' => tr('EPDS rose across several screenings.',
            'کئی اسکریننگ میں EPDS مسلسل بڑھا۔'),
        'phq9_rising' => tr('PHQ-9 rose since the earlier screening.',
            'پچھلی اسکریننگ کے بعد PHQ-9 بڑھا۔'),
        'phq9_falling' => tr('PHQ-9 fell since the earlier screening.',
            'پچھلی اسکریننگ کے بعد PHQ-9 کم ہوا۔'),
        'screening_elevated' => tr(
            'A recent screening reached the follow-up threshold.',
            'حالیہ اسکریننگ فالو اپ کی حد تک پہنچی۔'),
        'mood_worsening' =>
          tr('Recorded mood was lower.', 'درج شدہ موڈ کم تھا۔'),
        'energy_worsening' =>
          tr('Recorded energy was lower.', 'درج شدہ توانائی کم تھی۔'),
        'sleep_worsening' => tr('Some recorded sleep measures worsened.',
            'نیند کے کچھ درج شدہ پیمانوں میں خرابی آئی۔'),
        'support_worsening' =>
          tr('Less social support was reported.', 'کم سماجی مدد درج ہوئی۔'),
        'financial_strain' => tr('You reported difficulty covering essentials.',
            'آپ نے بنیادی ضروریات پوری کرنے میں مشکل بتائی۔'),
        'relationship_strain' => tr(
            'You reported strain in home relationships.',
            'آپ نے گھر کے تعلقات میں پریشانی بتائی۔'),
        'support_gap' => tr('You reported getting less help than you needed.',
            'آپ نے بتایا کہ ضرورت کے مطابق مدد نہیں ملی۔'),
        'recovery_difficulty' => tr(
            'Recovery or health made daily care harder.',
            'صحت یابی یا بیماری نے روزمرہ دیکھ بھال مشکل بنائی۔'),
        'recurring_text_distress' => tr(
            'Your private entries showed recurring distress cues.',
            'آپ کے نجی اندراجات میں پریشانی کے اشارے بار بار ملے۔'),
        'phone_change' => tr('Some recent phone signals changed.',
            'فون کے کچھ حالیہ اشارے بدلے۔'),
        'supporting_changes' => tr('Several daily patterns worsened.',
            'روزمرہ کے کئی اشاروں میں خرابی آئی۔'),
        'insufficient_screening_history' => tr(
            'The score needs two recent, comparable EPDS screenings.',
            'اسکور کے لیے دو حالیہ، قابلِ موازنہ EPDS اسکریننگ درکار ہیں۔'),
        _ => null,
      };

  Widget _nextStep(BuildContext context, Object? step) {
    if (step == 'professional_support') {
      return OutlinedButton(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => CareDirectoryScreen(
            onUrgentHelp: () {
              if (context.mounted) context.push(AppRoutes.crisis);
            },
          ),
        )),
        child: Text(tr('Find professional support', 'ماہر سے مدد تلاش کریں')),
      );
    }
    final (label, route) = switch (step) {
      'immediate_help' => (
          tr('Open Immediate Help', 'فوری مدد کھولیں'),
          AppRoutes.crisis
        ),
      'screening_follow_up' => (
          tr('Open screening schedule', 'اسکریننگ کا شیڈول دیکھیں'),
          AppRoutes.tests
        ),
      'sleep_support' => (
          tr('Review sleep and rest', 'نیند اور آرام کا جائزہ لیں'),
          AppRoutes.digitalWellbeing
        ),
      'practical_support' => (
          tr('Explore practical support', 'عملی مدد دیکھیں'),
          '${AppRoutes.content}?category=psychoeducation'
        ),
      'mood_support' => (
          tr('Explore mood support', 'موڈ کے لیے مدد دیکھیں'),
          '${AppRoutes.content}?category=soothing'
        ),
      _ => (
          tr('Continue mood check-ins', 'موڈ کا اندراج جاری رکھیں'),
          AppRoutes.mood
        ),
    };
    return OutlinedButton(
      onPressed: () => context.push(route),
      child: Text(label),
    );
  }
}

Map _map(Object? value) => value is Map ? value : const {};
List _list(Object? value) => value is List ? value : const [];
num? _number(Object? value) => value is num && value.isFinite ? value : null;
String? _day(Object? value) =>
    value is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)
        ? value
        : null;
