import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/onboarding_model.dart';

/// Step 2: Obstetric Information
/// Collects: delivery method, parity, complications, baby gender.
///
/// Clinical basis: PPD risk factors per Kamal et al. (2025) —
///   - Cesarean (OR = 1.60)
///   - Preeclampsia (aOR = 2.30)
///   - Postpartum hemorrhage (aOR = 2.10)
///   - Preterm birth (aOR = 1.85)
///   - Female baby (43% vs 14% PPD rate; Jadoon et al., 2020)
///
/// These fields are features for the ML risk prediction engine (Phase 1 M4).
class ObstetricInfoStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final OnboardingData data;
  final bool isUrdu;

  const ObstetricInfoStep({
    super.key,
    required this.formKey,
    required this.data,
    required this.isUrdu,
  });

  @override
  State<ObstetricInfoStep> createState() => _ObstetricInfoStepState();
}

class _ObstetricInfoStepState extends State<ObstetricInfoStep> {
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: widget.isUrdu
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // ── Mode of Delivery ────────────────────────────────────────
            _SectionLabel(
              label: widget.isUrdu ? 'ولادت کا طریقہ' : 'Mode of Delivery',
              isUrdu: widget.isUrdu,
            ),
            _RadioGroup<DeliveryMethod>(
              isUrdu: widget.isUrdu,
              value: widget.data.deliveryMethod,
              options: [
                _RadioOption(
                  value: DeliveryMethod.vaginal,
                  labelEn: 'Vaginal / Natural',
                  labelUr: 'قدرتی ولادت',
                  icon: Icons.child_friendly_rounded,
                ),
                _RadioOption(
                  value: DeliveryMethod.cesarean,
                  labelEn: 'Cesarean (C-Section)',
                  labelUr: 'آپریشن (سیزرین)',
                  icon: Icons.local_hospital_rounded,
                  riskNote: widget.isUrdu
                      ? 'خطرے کا عنصر (OR = 1.60)'
                      : 'Risk factor (OR = 1.60)',
                ),
              ],
              onChanged: (v) => setState(() => widget.data.deliveryMethod = v),
              validator: (_) => widget.data.deliveryMethod == null
                  ? (widget.isUrdu
                      ? 'ولادت کا طریقہ منتخب کریں'
                      : 'Select delivery method')
                  : null,
            ),

            const SizedBox(height: 20),

            // ── Parity ──────────────────────────────────────────────────
            _SectionLabel(
              label: widget.isUrdu
                  ? 'پچھلی ولادتوں کی تعداد'
                  : 'Number of Previous Deliveries',
              isUrdu: widget.isUrdu,
            ),
            _ParitySelector(
              value: widget.data.parity,
              onChanged: (v) => setState(() => widget.data.parity = v),
              isUrdu: widget.isUrdu,
            ),

            const SizedBox(height: 20),

            // ── Baby Gender ─────────────────────────────────────────────
            _SectionLabel(
              label: widget.isUrdu ? 'بچے کی جنس' : 'Baby\'s Gender',
              isUrdu: widget.isUrdu,
              footnote: widget.isUrdu
                  ? '(تحقیق میں خطرے کا عنصر — جادون ایٹ ال 2020)'
                  : '(Research-linked risk factor — Jadoon et al., 2020)',
            ),
            _RadioGroup<BabyGender>(
              isUrdu: widget.isUrdu,
              value: widget.data.babyGender,
              options: [
                _RadioOption(
                  value: BabyGender.male,
                  labelEn: 'Male',
                  labelUr: 'لڑکا',
                  icon: Icons.boy_rounded,
                ),
                _RadioOption(
                  value: BabyGender.female,
                  labelEn: 'Female',
                  labelUr: 'لڑکی',
                  icon: Icons.girl_rounded,
                  riskNote: widget.isUrdu
                      ? 'اعلیٰ خطرے کی جنس (43% PPD)'
                      : 'Higher-risk gender (43% PPD)',
                ),
              ],
              onChanged: (v) => setState(() => widget.data.babyGender = v),
              validator: (_) => widget.data.babyGender == null
                  ? (widget.isUrdu
                      ? 'بچے کی جنس منتخب کریں'
                      : 'Select baby\'s gender')
                  : null,
            ),

            const SizedBox(height: 20),

            // ── Obstetric Complications ──────────────────────────────────
            _SectionLabel(
              label: widget.isUrdu
                  ? 'کوئی پیچیدگیاں؟'
                  : 'Obstetric Complications',
              isUrdu: widget.isUrdu,
              footnote: widget.isUrdu
                  ? '(سب جو قابل اطلاق ہوں منتخب کریں)'
                  : '(Select all that apply)',
            ),
            _ComplicationCheckboxes(
              data: widget.data,
              isUrdu: widget.isUrdu,
              onChanged: () => setState(() {}),
            ),

            const SizedBox(height: 24),

            // Clinical note
            _ClinicalNoteCard(isUrdu: widget.isUrdu),
          ],
        ),
      ),
    );
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final String? footnote;
  final bool isUrdu;

  const _SectionLabel({
    required this.label,
    required this.isUrdu,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: isUrdu
              ? AppTextStyles.urduLabel.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                )
              : AppTextStyles.labelLarge,
          textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
        ),
        if (footnote != null) ...[
          const SizedBox(height: 2),
          Text(
            footnote!,
            style: isUrdu
                ? AppTextStyles.urduLabel.copyWith(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  )
                : AppTextStyles.bodySmall,
            textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
          ),
        ],
        const SizedBox(height: 10),
      ],
    );
  }
}

class _RadioOption<T> {
  final T value;
  final String labelEn;
  final String labelUr;
  final IconData icon;
  final String? riskNote;

  const _RadioOption({
    required this.value,
    required this.labelEn,
    required this.labelUr,
    required this.icon,
    this.riskNote,
  });
}

class _RadioGroup<T> extends FormField<T> {
  _RadioGroup({
    super.key,
    required bool isUrdu,
    required T? value,
    required List<_RadioOption<T>> options,
    required void Function(T?) onChanged,
    super.validator,
  }) : super(
          initialValue: value,
          builder: (field) {
            return Column(
              children: [
                ...options.map(
                  (opt) => GestureDetector(
                    onTap: () {
                      onChanged(opt.value);
                      field.didChange(opt.value);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: value == opt.value
                            ? AppColors.primaryContainer
                            : AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: value == opt.value
                              ? AppColors.primary
                              : AppColors.outline.withOpacity(0.4),
                          width: value == opt.value ? 1.8 : 1,
                        ),
                      ),
                      child: Row(
                        textDirection:
                            isUrdu ? TextDirection.rtl : TextDirection.ltr,
                        children: [
                          Icon(
                            opt.icon,
                            color: value == opt.value
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: isUrdu
                                  ? CrossAxisAlignment.end
                                  : CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isUrdu ? opt.labelUr : opt.labelEn,
                                  style: isUrdu
                                      ? AppTextStyles.urduBody.copyWith(
                                          fontSize: 15,
                                          color: AppColors.textPrimary,
                                        )
                                      : AppTextStyles.bodyLarge.copyWith(
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textPrimary,
                                        ),
                                  textDirection: isUrdu
                                      ? TextDirection.rtl
                                      : TextDirection.ltr,
                                ),
                                if (opt.riskNote != null)
                                  Text(
                                    opt.riskNote!,
                                    style:
                                        AppTextStyles.labelSmall.copyWith(
                                      color: AppColors.warning,
                                    ),
                                    textDirection: isUrdu
                                        ? TextDirection.rtl
                                        : TextDirection.ltr,
                                  ),
                              ],
                            ),
                          ),
                          Radio<T>(
                            value: opt.value,
                            groupValue: value,
                            onChanged: (v) {
                              onChanged(v);
                              field.didChange(v);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                if (field.hasError)
                  Align(
                    alignment: isUrdu
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Text(
                      field.errorText!,
                      style: AppTextStyles.bodySmall
                          .copyWith(color: AppColors.error),
                    ),
                  ),
              ],
            );
          },
        );
}

class _ParitySelector extends StatelessWidget {
  final int value;
  final void Function(int) onChanged;
  final bool isUrdu;

  const _ParitySelector({
    required this.value,
    required this.onChanged,
    required this.isUrdu,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(5, (i) {
        final isSelected = value == i;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.secondary
                  : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.secondary
                    : AppColors.outline.withOpacity(0.3),
              ),
            ),
            child: Center(
              child: Text(
                '$i',
                style: AppTextStyles.titleMedium.copyWith(
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

class _ComplicationCheckboxes extends StatelessWidget {
  final OnboardingData data;
  final bool isUrdu;
  final VoidCallback onChanged;

  const _ComplicationCheckboxes({
    required this.data,
    required this.isUrdu,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final complications = [
      _Complication(
        labelEn: 'Preeclampsia / Eclampsia',
        labelUr: 'پری ایکلامپسیا / ایکلامپسیا',
        riskEn: 'aOR = 2.30',
        riskUr: 'aOR = 2.30',
        getter: () => data.hasPreeclampsia,
        setter: (v) => data.hasPreeclampsia = v,
      ),
      _Complication(
        labelEn: 'Postpartum Hemorrhage',
        labelUr: 'زچگی کے بعد خون آنا',
        riskEn: 'aOR = 2.10',
        riskUr: 'aOR = 2.10',
        getter: () => data.hasPostpartumHemorrhage,
        setter: (v) => data.hasPostpartumHemorrhage = v,
      ),
      _Complication(
        labelEn: 'Preterm Birth (< 37 weeks)',
        labelUr: 'وقت سے پہلے پیدائش (37 ہفتوں سے کم)',
        riskEn: 'aOR = 1.85',
        riskUr: 'aOR = 1.85',
        getter: () => data.hasPretermBirth,
        setter: (v) => data.hasPretermBirth = v,
      ),
      _Complication(
        labelEn: 'Gestational Diabetes (GDM)',
        labelUr: 'حمل کی ذیابیطس',
        riskEn: '',
        riskUr: '',
        getter: () => data.hasGestationalDiabetes,
        setter: (v) => data.hasGestationalDiabetes = v,
      ),
    ];

    return Column(
      children: complications.map((c) {
        return _ComplicationTile(
          complication: c,
          isUrdu: isUrdu,
          onChanged: onChanged,
        );
      }).toList(),
    );
  }
}

class _Complication {
  final String labelEn;
  final String labelUr;
  final String riskEn;
  final String riskUr;
  final bool Function() getter;
  final void Function(bool) setter;

  const _Complication({
    required this.labelEn,
    required this.labelUr,
    required this.riskEn,
    required this.riskUr,
    required this.getter,
    required this.setter,
  });
}

class _ComplicationTile extends StatelessWidget {
  final _Complication complication;
  final bool isUrdu;
  final VoidCallback onChanged;

  const _ComplicationTile({
    required this.complication,
    required this.isUrdu,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isChecked = complication.getter();
    return GestureDetector(
      onTap: () {
        complication.setter(!isChecked);
        onChanged();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isChecked
              ? AppColors.warningContainer
              : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isChecked
                ? AppColors.warning
                : AppColors.outline.withOpacity(0.3),
          ),
        ),
        child: Row(
          textDirection:
              isUrdu ? TextDirection.rtl : TextDirection.ltr,
          children: [
            Checkbox(
              value: isChecked,
              onChanged: (v) {
                complication.setter(v ?? false);
                onChanged();
              },
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: isUrdu
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    isUrdu ? complication.labelUr : complication.labelEn,
                    style: isUrdu
                        ? AppTextStyles.urduBody.copyWith(
                            fontSize: 14,
                            color: AppColors.textPrimary,
                          )
                        : AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                          ),
                    textDirection:
                        isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  ),
                  if ((isUrdu ? complication.riskUr : complication.riskEn)
                      .isNotEmpty)
                    Text(
                      isUrdu ? complication.riskUr : complication.riskEn,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: AppColors.warning,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClinicalNoteCard extends StatelessWidget {
  final bool isUrdu;

  const _ClinicalNoteCard({required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
        children: [
          const Icon(Icons.science_outlined,
              size: 18, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isUrdu
                  ? 'یہ معلومات ایک کلینیکل طور پر تصدیق شدہ ML ماڈل کو بہتر بنانے کے لیے استعمال کی جاتی ہیں۔'
                  : 'This data improves a clinically validated ML model trained on Pakistani maternal cohorts.',
              style: isUrdu
                  ? AppTextStyles.urduLabel.copyWith(
                      color: AppColors.onSecondaryContainer,
                    )
                  : AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSecondaryContainer,
                    ),
              textDirection:
                  isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}
