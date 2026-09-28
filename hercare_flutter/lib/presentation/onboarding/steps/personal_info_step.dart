import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/onboarding_model.dart';

/// Step 1: Personal Information
/// Collects: full name, age, education, city, months since birth.
/// All fields feed into [OnboardingData] and later into the ML risk model.
class PersonalInfoStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final OnboardingData data;
  final bool isUrdu;

  const PersonalInfoStep({
    super.key,
    required this.formKey,
    required this.data,
    required this.isUrdu,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: isUrdu
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            // Full Name
            _OnboardingField(
              label: isUrdu ? 'پورا نام' : 'Full Name',
              hint: isUrdu ? 'جیسے: سارہ خان' : 'e.g. Sara Khan',
              isUrdu: isUrdu,
              keyboardType: TextInputType.name,
              textCapitalization: TextCapitalization.words,
              onSaved: (v) => data.fullName = v?.trim(),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return isUrdu
                      ? 'نام درج کریں'
                      : 'Please enter your name';
                }
                if (v.trim().length < 2) {
                  return isUrdu
                      ? 'نام بہت چھوٹا ہے'
                      : 'Name is too short';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),

            // Age
            _OnboardingField(
              label: isUrdu ? 'عمر (سال)' : 'Age (years)',
              hint: isUrdu ? 'جیسے: 26' : 'e.g. 26',
              isUrdu: isUrdu,
              keyboardType: TextInputType.number,
              onSaved: (v) => data.age = int.tryParse(v ?? ''),
              validator: (v) {
                final age = int.tryParse(v ?? '');
                if (age == null) {
                  return isUrdu ? 'عمر درج کریں' : 'Enter a valid age';
                }
                if (age < 15 || age > 55) {
                  return isUrdu
                      ? 'عمر 15 سے 55 کے درمیان ہونی چاہیے'
                      : 'Age must be between 15 and 55';
                }
                return null;
              },
            ),
            const SizedBox(height: 18),

            // Education
            _OnboardingDropdown(
              label: isUrdu ? 'اعلیٰ تعلیم' : 'Highest Education',
              isUrdu: isUrdu,
              items: isUrdu
                  ? [
                      'کوئی رسمی تعلیم نہیں',
                      'پرائمری (1-5)',
                      'مڈل (6-8)',
                      'میٹرک',
                      'انٹرمیڈیٹ',
                      'گریجویشن',
                      'ماسٹرز یا اس سے اوپر',
                    ]
                  : [
                      'No Formal Education',
                      'Primary (Grade 1–5)',
                      'Middle (Grade 6–8)',
                      'Matric (Grade 9–10)',
                      'Intermediate (Grade 11–12)',
                      'Graduation (Bachelor\'s)',
                      'Masters or above',
                    ],
              onSaved: (v) => data.educationLevel = v,
              validator: (v) => v == null
                  ? (isUrdu ? 'تعلیم منتخب کریں' : 'Select education level')
                  : null,
            ),
            const SizedBox(height: 18),

            // City
            _OnboardingField(
              label: isUrdu ? 'شہر' : 'City',
              hint: isUrdu ? 'جیسے: لاہور' : 'e.g. Lahore',
              isUrdu: isUrdu,
              keyboardType: TextInputType.text,
              textCapitalization: TextCapitalization.words,
              onSaved: (v) => data.city = v?.trim(),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? (isUrdu ? 'شہر درج کریں' : 'Enter your city')
                  : null,
            ),
            const SizedBox(height: 18),

            // Months since birth
            _OnboardingField(
              label: isUrdu ? 'پیدائش کے بعد مہینے' : 'Months since birth',
              hint: isUrdu ? 'جیسے: 3' : 'e.g. 3',
              isUrdu: isUrdu,
              keyboardType: TextInputType.number,
              onSaved: (v) => data.monthsSinceBirth = int.tryParse(v ?? ''),
              validator: (v) {
                final months = int.tryParse(v ?? '');
                if (months == null) {
                  return isUrdu
                      ? 'درست تعداد درج کریں'
                      : 'Enter a valid number';
                }
                if (months < 0 || months > 12) {
                  return isUrdu
                      ? 'HerCare 0-12 ماہ پوسٹ پارٹم کے لیے ہے'
                      : 'HerCare is for 0–12 months postpartum';
                }
                return null;
              },
            ),

            const SizedBox(height: 24),

            // Info card
            _InfoCard(
              isUrdu: isUrdu,
              text: isUrdu
                  ? 'آپ کی معلومات صرف آپ کے تجربے کو بہتر بنانے کے لیے استعمال ہوتی ہیں اور کبھی فروخت نہیں کی جائیں گی۔'
                  : 'Your information is only used to personalize your experience and will never be sold.',
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Shared Form Widgets ─────────────────────────────────────────────────────

class _OnboardingField extends StatelessWidget {
  final String label;
  final String hint;
  final bool isUrdu;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final void Function(String?)? onSaved;
  final String? Function(String?)? validator;

  const _OnboardingField({
    required this.label,
    required this.hint,
    required this.isUrdu,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.onSaved,
    this.validator,
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
        const SizedBox(height: 8),
        TextFormField(
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
          style: isUrdu
              ? AppTextStyles.urduBody.copyWith(fontSize: 16)
              : AppTextStyles.bodyLarge,
          decoration: InputDecoration(hintText: hint),
          onSaved: onSaved,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
      ],
    );
  }
}

class _OnboardingDropdown extends StatelessWidget {
  final String label;
  final bool isUrdu;
  final List<String> items;
  final void Function(String?)? onSaved;
  final String? Function(String?)? validator;

  const _OnboardingDropdown({
    required this.label,
    required this.isUrdu,
    required this.items,
    this.onSaved,
    this.validator,
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
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(),
          isExpanded: true,
          style: isUrdu
              ? AppTextStyles.urduBody.copyWith(
                  fontSize: 15,
                  color: context.hcTextPrimary,
                )
              : AppTextStyles.bodyLarge.copyWith(
                  color: context.hcTextPrimary,
                ),
          items: items
              .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(
                      e,
                      textDirection:
                          isUrdu ? TextDirection.rtl : TextDirection.ltr,
                    ),
                  ))
              .toList(),
          onChanged: (_) {},
          onSaved: onSaved,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  final bool isUrdu;

  const _InfoCard({required this.text, required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
        children: [
          Icon(Icons.lock_outline_rounded,
              size: 18, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: isUrdu
                  ? AppTextStyles.urduLabel.copyWith(
                      color: AppColors.onPrimaryContainer,
                    )
                  : AppTextStyles.bodySmall.copyWith(
                      color: AppColors.onPrimaryContainer,
                    ),
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}
