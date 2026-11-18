import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/onboarding_model.dart';

/// Step 2: Obstetric Information
/// Collects: delivery method, parity, complications, baby gender.
///
/// Optional profile details, not an individual clinical risk assessment.
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
          crossAxisAlignment:
              widget.isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // ── Mode of Delivery ────────────────────────────────────────
            _SectionLabel(
              label: widget.isUrdu ? 'ولادت کا طریقہ' : 'Mode of Delivery',
              isUrdu: widget.isUrdu,
            ),
            _RadioGroup<DeliveryMethod>(
              isUrdu: widget.isUrdu,
              value: widget.data.deliveryMethod,
              options: const [
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
                ),
              ],
              onChanged: (v) => setState(() => widget.data.deliveryMethod = v),
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
            ),
            _RadioGroup<BabyGender>(
              isUrdu: widget.isUrdu,
              value: widget.data.babyGender,
              options: const [
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
                ),
              ],
              onChanged: (v) => setState(() => widget.data.babyGender = v),
            ),

            const SizedBox(height: 20),

            // ── Obstetric Complications ──────────────────────────────────
            _SectionLabel(
              label:
                  widget.isUrdu ? 'کوئی پیچیدگیاں؟' : 'Obstetric Complications',
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

            _OptionalDetailsNote(isUrdu: widget.isUrdu),
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
                  color: context.hcTextPrimary,
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
                    color: context.hcTextSecondary,
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

  const _RadioOption({
    required this.value,
    required this.labelEn,
    required this.labelUr,
    required this.icon,
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
            return RadioGroup<T>(
              groupValue: value,
              onChanged: (v) {
                onChanged(v);
                field.didChange(v);
              },
              child: Column(
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
                                : AppColors.outline.withValues(alpha: 0.4),
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
                                            color: field.context.hcTextPrimary,
                                          )
                                        : AppTextStyles.bodyLarge.copyWith(
                                            fontWeight: FontWeight.w500,
                                            color: field.context.hcTextPrimary,
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
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (field.hasError)
                    Align(
                      alignment:
                          isUrdu ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(
                        field.errorText!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.error),
                      ),
                    ),
                ],
              ),
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
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(5, (i) {
        final isSelected = value == i;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color:
                  isSelected ? AppColors.secondary : AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? AppColors.secondary
                    : AppColors.outline.withValues(alpha: 0.3),
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
        getter: () => data.hasPreeclampsia,
        setter: (v) => data.hasPreeclampsia = v,
      ),
      _Complication(
        labelEn: 'Postpartum Hemorrhage',
        labelUr: 'زچگی کے بعد خون آنا',
        getter: () => data.hasPostpartumHemorrhage,
        setter: (v) => data.hasPostpartumHemorrhage = v,
      ),
      _Complication(
        labelEn: 'Preterm Birth (< 37 weeks)',
        labelUr: 'وقت سے پہلے پیدائش (37 ہفتوں سے کم)',
        getter: () => data.hasPretermBirth,
        setter: (v) => data.hasPretermBirth = v,
      ),
      _Complication(
        labelEn: 'Gestational Diabetes (GDM)',
        labelUr: 'حمل کی ذیابیطس',
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
  final bool Function() getter;
  final void Function(bool) setter;

  const _Complication({
    required this.labelEn,
    required this.labelUr,
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isChecked ? AppColors.warningContainer : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isChecked
                ? AppColors.warning
                : AppColors.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
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
                crossAxisAlignment:
                    isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  Text(
                    isUrdu ? complication.labelUr : complication.labelEn,
                    style: isUrdu
                        ? AppTextStyles.urduBody.copyWith(
                            fontSize: 14,
                            color: context.hcTextPrimary,
                          )
                        : AppTextStyles.bodyMedium.copyWith(
                            color: context.hcTextPrimary,
                          ),
                    textDirection:
                        isUrdu ? TextDirection.rtl : TextDirection.ltr,
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

class _OptionalDetailsNote extends StatelessWidget {
  final bool isUrdu;

  const _OptionalDetailsNote({required this.isUrdu});

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
          const Icon(Icons.info_outline_rounded,
              size: 18, color: AppColors.secondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isUrdu
                  ? 'یہ معلومات اختیاری ہیں۔ اگر آپ کو یقین نہ ہو تو یہ حصہ چھوڑ سکتی ہیں۔'
                  : 'These details are optional. You can skip this section if you are unsure.',
              style: isUrdu
                  ? AppTextStyles.urduLabel.copyWith(
                      color: AppColors.onSecondaryContainer,
                    )
                  : AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onSecondaryContainer,
                    ),
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}
