import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/onboarding_model.dart';

/// Step 3: Family & Social Support
/// Collects: household type, monthly income range, primary support person.
///
/// Clinical basis: Sajjad et al. (2024) — 71% of PPD-positive women live in
/// joint families. 48% relied on husbands as primary informal support.
/// Income range (PKR 26k–50k) most common in PPD-positive cohort.
class FamilySupportStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final OnboardingData data;
  final bool isUrdu;

  const FamilySupportStep({
    super.key,
    required this.formKey,
    required this.data,
    required this.isUrdu,
  });

  @override
  State<FamilySupportStep> createState() => _FamilySupportStepState();
}

class _FamilySupportStepState extends State<FamilySupportStep> {
  // Income bracket options (PKR)
  static const List<String> _incomeOptionsEn = [
    'Under PKR 26,000',
    'PKR 26,000 – 50,000',
    'PKR 51,000 – 75,000',
    'PKR 76,000 – 100,000',
    'Above PKR 100,000',
    'Prefer not to say',
  ];

  static const List<String> _incomeOptionsUr = [
    '26,000 روپے سے کم',
    '26,000 – 50,000 روپے',
    '51,000 – 75,000 روپے',
    '76,000 – 100,000 روپے',
    '1,00,000 روپے سے زیادہ',
    'بتانا نہیں چاہتی',
  ];

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
            // ── Household Type ──────────────────────────────────────────
            _Label(
              en: 'Household Type',
              ur: 'گھرانے کی نوعیت',
              isUrdu: widget.isUrdu,
              footnote: widget.isUrdu
                  ? '71٪ PPD مثبت خواتین مشترکہ خاندانوں میں رہتی ہیں'
                  : '71% of PPD-positive women live in joint families',
            ),
            _TileSelector<HouseholdType>(
              isUrdu: widget.isUrdu,
              value: widget.data.householdType,
              options: [
                _TileOption(
                  value: HouseholdType.nuclear,
                  labelEn: 'Nuclear Family',
                  labelUr: 'علیحدہ خاندان',
                  descEn: 'You & your partner',
                  descUr: 'آپ اور آپ کے شوہر',
                  icon: Icons.home_outlined,
                ),
                _TileOption(
                  value: HouseholdType.joint,
                  labelEn: 'Joint Family',
                  labelUr: 'مشترکہ خاندان',
                  descEn: 'Living with in-laws or extended family',
                  descUr: 'سسرال یا بڑے خاندان کے ساتھ',
                  icon: Icons.groups_outlined,
                ),
              ],
              onChanged: (v) => setState(() => widget.data.householdType = v),
              validator: (_) => widget.data.householdType == null
                  ? (widget.isUrdu
                      ? 'خاندان کی نوعیت منتخب کریں'
                      : 'Select household type')
                  : null,
            ),

            const SizedBox(height: 20),

            // ── Monthly Income ───────────────────────────────────────────
            _Label(
              en: 'Monthly Household Income',
              ur: 'ماہانہ گھریلو آمدنی',
              isUrdu: widget.isUrdu,
            ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(),
              isExpanded: true,
              style: widget.isUrdu
                  ? AppTextStyles.urduBody.copyWith(
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    )
                  : AppTextStyles.bodyLarge
                      .copyWith(color: AppColors.textPrimary),
              hint: Text(
                widget.isUrdu ? 'آمدنی کی حد منتخب کریں' : 'Select range',
                textDirection: widget.isUrdu
                    ? TextDirection.rtl
                    : TextDirection.ltr,
              ),
              items: (widget.isUrdu ? _incomeOptionsUr : _incomeOptionsEn)
                  .map((e) => DropdownMenuItem(
                        value: e,
                        child: Text(
                          e,
                          textDirection: widget.isUrdu
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                        ),
                      ))
                  .toList(),
              onChanged: (v) => setState(() => widget.data.incomeRange = v),
              onSaved: (v) => widget.data.incomeRange = v,
              validator: (v) => v == null
                  ? (widget.isUrdu
                      ? 'آمدنی منتخب کریں'
                      : 'Select income range')
                  : null,
              autovalidateMode: AutovalidateMode.onUserInteraction,
            ),

            const SizedBox(height: 20),

            // ── Primary Support ──────────────────────────────────────────
            _Label(
              en: 'Primary Source of Support',
              ur: 'بنیادی مددگار',
              isUrdu: widget.isUrdu,
              footnote: widget.isUrdu
                  ? '48٪ نے شوہر کو بنیادی مدد کا ذریعہ بتایا'
                  : '48% of women cited husband as primary support',
            ),
            _SupportSelector(
              data: widget.data,
              isUrdu: widget.isUrdu,
              onChanged: () => setState(() {}),
            ),

            const SizedBox(height: 24),

            // Info card
            _SupportInfoCard(isUrdu: widget.isUrdu),
          ],
        ),
      ),
    );
  }
}

// ─── Reusable Widgets ─────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String en;
  final String ur;
  final bool isUrdu;
  final String? footnote;

  const _Label({
    required this.en,
    required this.ur,
    required this.isUrdu,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment:
            isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            isUrdu ? ur : en,
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
              style: AppTextStyles.bodySmall,
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
          ],
        ],
      ),
    );
  }
}

class _TileOption<T> {
  final T value;
  final String labelEn;
  final String labelUr;
  final String descEn;
  final String descUr;
  final IconData icon;

  const _TileOption({
    required this.value,
    required this.labelEn,
    required this.labelUr,
    required this.descEn,
    required this.descUr,
    required this.icon,
  });
}

class _TileSelector<T> extends FormField<T> {
  _TileSelector({
    super.key,
    required bool isUrdu,
    required T? value,
    required List<_TileOption<T>> options,
    required void Function(T?) onChanged,
    super.validator,
  }) : super(
          initialValue: value,
          builder: (field) {
            return Column(
              children: [
                Row(
                  children: options.map((opt) {
                    final isSelected = value == opt.value;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          onChanged(opt.value);
                          field.didChange(opt.value);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(right: 8),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primaryContainer
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.outline.withOpacity(0.3),
                              width: isSelected ? 1.8 : 1,
                            ),
                          ),
                          child: Column(
                            children: [
                              Icon(
                                opt.icon,
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.textSecondary,
                                size: 28,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                isUrdu ? opt.labelUr : opt.labelEn,
                                textAlign: TextAlign.center,
                                style: isUrdu
                                    ? AppTextStyles.urduBody.copyWith(
                                        fontSize: 13,
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.textPrimary,
                                      )
                                    : AppTextStyles.labelMedium.copyWith(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                textDirection: isUrdu
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                isUrdu ? opt.descUr : opt.descEn,
                                textAlign: TextAlign.center,
                                style: isUrdu
                                    ? AppTextStyles.urduLabel.copyWith(
                                        fontSize: 10,
                                      )
                                    : AppTextStyles.bodySmall.copyWith(
                                        fontSize: 10,
                                      ),
                                textDirection: isUrdu
                                    ? TextDirection.rtl
                                    : TextDirection.ltr,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (field.hasError)
                  Align(
                    alignment: isUrdu
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        field.errorText!,
                        style: AppTextStyles.bodySmall
                            .copyWith(color: AppColors.error),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
}

class _SupportSelector extends StatelessWidget {
  final OnboardingData data;
  final bool isUrdu;
  final VoidCallback onChanged;

  const _SupportSelector({
    required this.data,
    required this.isUrdu,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final supports = [
      _SupportOpt(
        value: SupportSource.husband,
        en: 'Husband / Partner',
        ur: 'شوہر',
        icon: Icons.favorite_border_rounded,
      ),
      _SupportOpt(
        value: SupportSource.motherInLaw,
        en: 'Mother / In-law',
        ur: 'والدہ / ساس',
        icon: Icons.elderly_woman_rounded,
      ),
      _SupportOpt(
        value: SupportSource.siblings,
        en: 'Siblings',
        ur: 'بہن بھائی',
        icon: Icons.people_outline_rounded,
      ),
      _SupportOpt(
        value: SupportSource.none,
        en: 'No Support',
        ur: 'کوئی نہیں',
        icon: Icons.sentiment_dissatisfied_outlined,
        isCritical: true,
      ),
    ];

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: supports.map((s) {
        final isSelected = data.primarySupport == s.value;
        return GestureDetector(
          onTap: () {
            data.primarySupport = s.value;
            onChanged();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected
                  ? (s.isCritical
                      ? AppColors.errorContainer
                      : AppColors.secondaryContainer)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? (s.isCritical
                        ? AppColors.error
                        : AppColors.secondary)
                    : AppColors.outline.withOpacity(0.3),
                width: isSelected ? 1.8 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              textDirection:
                  isUrdu ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Icon(
                  s.icon,
                  size: 18,
                  color: isSelected
                      ? (s.isCritical
                          ? AppColors.error
                          : AppColors.secondary)
                      : AppColors.textSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  isUrdu ? s.ur : s.en,
                  style: isUrdu
                      ? AppTextStyles.urduLabel.copyWith(
                          color: isSelected
                              ? (s.isCritical
                                  ? AppColors.error
                                  : AppColors.secondary)
                              : AppColors.textPrimary,
                        )
                      : AppTextStyles.labelMedium.copyWith(
                          color: isSelected
                              ? (s.isCritical
                                  ? AppColors.error
                                  : AppColors.secondary)
                              : AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                  textDirection:
                      isUrdu ? TextDirection.rtl : TextDirection.ltr,
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SupportOpt {
  final SupportSource value;
  final String en;
  final String ur;
  final IconData icon;
  final bool isCritical;

  const _SupportOpt({
    required this.value,
    required this.en,
    required this.ur,
    required this.icon,
    this.isCritical = false,
  });
}

class _SupportInfoCard extends StatelessWidget {
  final bool isUrdu;

  const _SupportInfoCard({required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.hub_outlined,
              size: 18, color: AppColors.success),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isUrdu
                  ? 'آپ کے سپورٹ نیٹ ورک کو سمجھنا ہمیں سرپرست رپورٹس اور تجاویز کو ذاتی بنانے میں مدد کرتا ہے۔'
                  : 'Understanding your support network helps us personalize guardian reports and recommendations.',
              style: isUrdu
                  ? AppTextStyles.urduLabel.copyWith(
                      color: AppColors.textPrimary,
                    )
                  : AppTextStyles.bodySmall.copyWith(
                      color: AppColors.textPrimary,
                    ),
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}
