import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/therapy_models.dart';
import 'pulse_analysis.dart';
import 'pulse_check_screen.dart';

/// 0-10 tension rating. Unset until she moves the slider, so an untouched
/// default is never saved as an answer.
class TensionSlider extends StatelessWidget {
  const TensionSlider(
      {super.key,
      required this.label,
      required this.value,
      required this.isUrdu,
      required this.onChanged});
  final String label;
  final int? value;
  final bool isUrdu;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(label, style: AppTextStyles.labelLarge),
        Text(
            value == null
                ? (isUrdu ? 'ابھی نہیں چنا' : 'Not set')
                : '$value / 10',
            textAlign: TextAlign.center,
            style: AppTextStyles.labelLarge.copyWith(color: AppColors.primary)),
        Slider(
            value: (value ?? 5).toDouble(),
            min: 0,
            max: 10,
            divisions: 10,
            label: value == null ? null : '$value',
            semanticFormatterCallback: (v) => '${v.round()} / 10',
            onChanged: onChanged == null ? null : (v) => onChanged!(v.round())),
        // Two flexible halves wrap on narrow screens and large text.
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Text(isUrdu ? '0 = بالکل پرسکون' : '0 = completely calm',
                  style: AppTextStyles.bodySmall)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(isUrdu ? '10 = بہت تناؤ' : '10 = extremely tense',
                  textAlign: TextAlign.end, style: AppTextStyles.bodySmall)),
        ]),
      ]);
}

/// Optional "before you start" check: tension now, and a 30-second heart
/// reading (camera or band). Research basis: asking before practice, rather
/// than recalling afterwards, gives a fairer before/after comparison.
class PreSessionCheck extends StatelessWidget {
  const PreSessionCheck(
      {super.key,
      required this.isUrdu,
      required this.measures,
      required this.onChanged,
      this.enabled = true});
  final bool isUrdu, enabled;
  final TherapyMeasures measures;
  final ValueChanged<TherapyMeasures> onChanged;

  String _t(String en, String ur) => isUrdu ? ur : en;

  Future<void> _heart(BuildContext context) async {
    final reading = await showPulseCheck(context, isUrdu: isUrdu, after: false);
    if (reading != null) onChanged(withBeforeReading(measures, reading));
  }

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
            color: context.hcSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.hcOutline)),
        // Collapsed until she opens it, so it never pushes the Start button away.
        child: ExpansionTile(
            key: const Key('before-check'),
            tilePadding: EdgeInsets.zero,
            shape: const Border(),
            collapsedShape: const Border(),
            initiallyExpanded: !measures.isEmpty,
            leading: const Icon(Icons.monitor_heart_outlined,
                color: AppColors.primary),
            title: Text(
                _t('Before you start (optional)',
                    'شروع کرنے سے پہلے (اختیاری)'),
                style: AppTextStyles.titleSmall),
            subtitle: Text(
                _t('Tension and heart check', 'تناؤ اور دل کی پیمائش'),
                style: AppTextStyles.bodySmall),
            childrenPadding: const EdgeInsets.only(bottom: 14),
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                  _t('This helps you and your care team see whether practice helps you.',
                      'اس سے آپ اور آپ کی دیکھ بھال کرنے والی ٹیم دیکھ سکیں گے کہ مشق مدد کرتی ہے یا نہیں۔'),
                  style: AppTextStyles.bodySmall
                      .copyWith(color: context.hcTextSecondary)),
              const SizedBox(height: 8),
              TensionSlider(
                  key: const Key('tension-before'),
                  label: _t('How tense do you feel right now?',
                      'اس وقت آپ کتنا تناؤ محسوس کر رہی ہیں؟'),
                  value: measures.tensionBefore,
                  isUrdu: isUrdu,
                  onChanged: enabled
                      ? (v) => onChanged(measures.copyWith(tensionBefore: v))
                      : null),
              const SizedBox(height: 4),
              if (measures.hrBefore != null)
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        const Icon(Icons.favorite, color: AppColors.secondary),
                    title: Text(_t('${measures.hrBefore} beats per minute',
                        '${measures.hrBefore} دھڑکنیں فی منٹ')),
                    subtitle: measures.hrvBefore == null
                        ? null
                        : Text(_t('Variability ${measures.hrvBefore} ms',
                            'تغیر ${measures.hrvBefore} ملی سیکنڈ')),
                    trailing: TextButton(
                        onPressed: enabled ? () => _heart(context) : null,
                        child: Text(_t('Redo', 'دوبارہ'))))
              else
                OutlinedButton.icon(
                    key: const Key('heart-before'),
                    onPressed: enabled ? () => _heart(context) : null,
                    icon: const Icon(Icons.favorite_border),
                    label: Text(_t('Check my heart rate (30 s)',
                        'دل کی رفتار چیک کریں (30 سیکنڈ)'))),
            ]),
      );
}

TherapyMeasures withBeforeReading(
        TherapyMeasures measures, PulseReading reading) =>
    TherapyMeasures(
        tensionBefore: measures.tensionBefore,
        tensionAfter: measures.tensionAfter,
        distressReported: measures.distressReported,
        hrBefore: reading.bpm,
        hrvBefore: reading.rmssdMs,
        physioSource: reading.source);

/// Adds the after-reading. Before and after are only compared when both came
/// from the same source (camera vs band readings are not comparable).
TherapyMeasures withAfterReading(
    TherapyMeasures measures, PulseReading reading) {
  final sameSource = measures.physioSource == reading.source;
  return TherapyMeasures(
      tensionBefore: measures.tensionBefore,
      tensionAfter: measures.tensionAfter,
      distressReported: measures.distressReported,
      hrBefore: sameSource ? measures.hrBefore : null,
      hrvBefore: sameSource ? measures.hrvBefore : null,
      hrAfter: reading.bpm,
      hrvAfter: reading.rmssdMs,
      physioSource: reading.source);
}

/// Offers the after-reading only if she took a before-reading.
Future<TherapyMeasures> maybeAfterReading(
    BuildContext context, TherapyMeasures measures, bool isUrdu) async {
  if (measures.hrBefore == null) return measures;
  final again = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
              title: Text(isUrdu
                  ? 'دوبارہ دل کی رفتار دیکھیں؟'
                  : 'Check your heart again?'),
              content: Text(isUrdu
                  ? '30 سیکنڈ کی دوسری پیمائش سے پتا چلے گا کہ مشق کے دوران جسم کتنا پرسکون ہوا۔'
                  : 'A second 30-second reading shows how much your body settled during practice.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(isUrdu ? 'چھوڑ دیں' : 'Skip')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(isUrdu ? 'ہاں، چیک کریں' : 'Yes, check')),
              ]));
  if (again != true || !context.mounted) return measures;
  final reading = await showPulseCheck(context, isUrdu: isUrdu, after: true);
  return reading == null ? measures : withAfterReading(measures, reading);
}
