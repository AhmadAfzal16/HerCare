import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_ext.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/onboarding_model.dart';

/// Step 4: Informed Consent
/// Implements the 3-tiered consent model defined in the scope document.
///
/// Tier 1 — Basic monitoring (REQUIRED): EPDS, mood logs, sleep data.
/// Tier 2 — Guardian reports (RECOMMENDED): aggregated clinical summaries.
/// Tier 3 — Notification & usage analysis (OPTIONAL): passive telemetry.
///
/// Legal/ethical: Users can revoke any consent at any time from Settings.
/// Tier 1 is required to use the app (enforced in [OnboardingWizard]).
class ConsentStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final OnboardingData data;
  final bool isUrdu;
  final VoidCallback onChanged;

  const ConsentStep({
    super.key,
    required this.formKey,
    required this.data,
    required this.isUrdu,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment:
              isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // ── Intro ────────────────────────────────────────────────────
            Text(
              isUrdu
                  ? 'ہرکیئر ذاتی مدد فراہم کرنے کے لیے ڈیٹا اکٹھا کرتا ہے۔ براہ کرم ہر اجازت کا جائزہ لیں۔'
                  : 'HerCare collects data to provide personalized support. Review each permission carefully.',
              style: isUrdu
                  ? AppTextStyles.urduBody.copyWith(fontSize: 15)
                  : AppTextStyles.bodyMedium,
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
            const SizedBox(height: 20),

            // ── Tier 1 (Required) ─────────────────────────────────────
            _ConsentTile(
              tier: 1,
              isUrdu: isUrdu,
              labelEn: 'Basic Monitoring',
              labelUr: 'بنیادی نگرانی',
              badgeEn: 'REQUIRED',
              badgeUr: 'ضروری',
              badgeColor: AppColors.error,
              descEn:
                  'EPDS screening scores, daily mood logs, sleep data, and app usage — '
                  'used to personalize your experience and generate clinical reports.',
              descUr: 'EPDS اسکریننگ سکورز، روزانہ کا موڈ، نیند کا ڈیٹا — '
                  'آپ کے تجربے کو ذاتی بنانے اور طبی رپورٹس بنانے کے لیے۔',
              isChecked: data.consentTier1,
              isDisabled: true, // Tier 1 cannot be unchecked
              onChanged: (_) {}, // always true
              icon: Icons.monitor_heart_outlined,
            ),

            // ── Tier 2 (Recommended) ───────────────────────────────────
            _ConsentTile(
              tier: 2,
              isUrdu: isUrdu,
              labelEn: 'Guardian Reports',
              labelUr: 'سرپرست رپورٹس',
              badgeEn: 'RECOMMENDED',
              badgeUr: 'تجویز کردہ',
              badgeColor: AppColors.warning,
              descEn:
                  'Aggregated mood scores and risk level summaries shared with your '
                  'linked guardian — never raw journal entries or private chats.',
              descUr:
                  'مجموعی موڈ سکورز اور خطرے کی سطح آپ کے سرپرست کے ساتھ شیئر کی جاتی ہے — '
                  'ڈائری کے اندراجات یا نجی چیٹ کبھی نہیں۔',
              isChecked: data.consentTier2,
              isDisabled: false,
              onChanged: (v) {
                data.consentTier2 = v;
                onChanged();
              },
              icon: Icons.supervisor_account_outlined,
            ),

            // ── Tier 3 (Optional) ──────────────────────────────────────
            _ConsentTile(
              tier: 3,
              isUrdu: isUrdu,
              labelEn: 'Notification & Usage Analysis',
              labelUr: 'اطلاع و استعمال کا تجزیہ',
              badgeEn: 'OPTIONAL',
              badgeUr: 'اختیاری',
              badgeColor: AppColors.accent,
              descEn:
                  'Passively analyzes message notification previews (~100 chars) '
                  'and screen time to detect early distress signals. Android only.',
              descUr: 'اطلاع کے پیش نظارے (~100 حروف) اور اسکرین ٹائم تجزیہ '
                  'تناؤ کی ابتدائی علامات کا پتہ لگانے کے لیے۔ صرف اینڈرائیڈ۔',
              isChecked: data.consentTier3,
              isDisabled: false,
              onChanged: (v) {
                data.consentTier3 = v;
                onChanged();
              },
              icon: Icons.notifications_none_outlined,
            ),

            const SizedBox(height: 20),

            // ── Privacy Note ──────────────────────────────────────────
            _PrivacyNote(isUrdu: isUrdu),

            const SizedBox(height: 16),

            // ── Data Deletion Rights ──────────────────────────────────
            _DataRightsCard(isUrdu: isUrdu),
          ],
        ),
      ),
    );
  }
}

// ─── Consent Tile ────────────────────────────────────────────────────────────

class _ConsentTile extends StatelessWidget {
  final int tier;
  final bool isUrdu;
  final String labelEn;
  final String labelUr;
  final String badgeEn;
  final String badgeUr;
  final Color badgeColor;
  final String descEn;
  final String descUr;
  final bool isChecked;
  final bool isDisabled;
  final void Function(bool) onChanged;
  final IconData icon;

  const _ConsentTile({
    required this.tier,
    required this.isUrdu,
    required this.labelEn,
    required this.labelUr,
    required this.badgeEn,
    required this.badgeUr,
    required this.badgeColor,
    required this.descEn,
    required this.descUr,
    required this.isChecked,
    required this.isDisabled,
    required this.onChanged,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isChecked
            ? AppColors.primaryContainer.withValues(alpha: 0.5)
            : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isChecked
              ? AppColors.primary.withValues(alpha: 0.4)
              : AppColors.outline.withValues(alpha: 0.3),
          width: isChecked ? 1.5 : 1,
        ),
        boxShadow: isChecked
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [],
      ),
      child: Column(
        children: [
          // Header row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (isChecked
                            ? AppColors.primary
                            : AppColors.textSecondary)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color:
                        isChecked ? AppColors.primary : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: isUrdu
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isUrdu ? labelUr : labelEn,
                            style: isUrdu
                                ? AppTextStyles.urduBody.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: context.hcTextPrimary,
                                  )
                                : AppTextStyles.titleSmall,
                            textDirection:
                                isUrdu ? TextDirection.rtl : TextDirection.ltr,
                          ),
                          const SizedBox(height: 8),
                          _Badge(
                            label: isUrdu ? badgeUr : badgeEn,
                            color: badgeColor,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Toggle
                Switch(
                  value: isChecked,
                  onChanged: isDisabled ? null : (v) => onChanged(v),
                  activeThumbColor: AppColors.primary,
                  thumbColor: WidgetStateProperty.all(Colors.white),
                  trackColor: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.selected)) {
                      return AppColors.primary;
                    }
                    return AppColors.outline.withValues(alpha: 0.4);
                  }),
                ),
              ],
            ),
          ),

          // Description
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Text(
              isUrdu ? descUr : descEn,
              style: isUrdu
                  ? AppTextStyles.urduLabel.copyWith(height: 1.8)
                  : AppTextStyles.bodySmall.copyWith(height: 1.6),
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),

          if (isDisabled)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(18),
                  bottomRight: Radius.circular(18),
                ),
              ),
              child: Text(
                isUrdu
                    ? 'یہ اجازت HerCare استعمال کرنے کے لیے ضروری ہے'
                    : 'This permission is required to use HerCare',
                style: AppTextStyles.labelSmall.copyWith(
                  color: AppColors.error,
                ),
                textAlign: isUrdu ? TextAlign.right : TextAlign.left,
                textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
              ),
            ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTextStyles.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 9,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PrivacyNote extends StatelessWidget {
  final bool isUrdu;

  const _PrivacyNote({required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.hcSurfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded,
              size: 18, color: context.hcTextSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isUrdu
                  ? 'آپ کسی بھی اجازت کو کسی بھی وقت ترتیبات → رازداری سے واپس لے سکتی ہیں۔'
                  : 'You may withdraw any permission at any time from Settings → Privacy.',
              style: isUrdu ? AppTextStyles.urduLabel : AppTextStyles.bodySmall,
              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
        ],
      ),
    );
  }
}

class _DataRightsCard extends StatelessWidget {
  final bool isUrdu;

  const _DataRightsCard({required this.isUrdu});

  @override
  Widget build(BuildContext context) {
    final rights = isUrdu
        ? [
            'اپنا ڈیٹا ڈاؤن لوڈ کریں',
            'اپنا اکاؤنٹ حذف کریں',
            'کسی بھی وقت اجازت واپس لیں',
          ]
        : [
            'Download your data',
            'Delete your account',
            'Revoke any permission at any time',
          ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.successContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 18, color: AppColors.success),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                isUrdu ? 'آپ کے ڈیٹا کے حقوق' : 'Your Data Rights',
                style: isUrdu
                    ? AppTextStyles.urduLabel.copyWith(
                        color: context.hcTextPrimary,
                        fontWeight: FontWeight.w600,
                      )
                    : AppTextStyles.labelMedium.copyWith(
                        color: context.hcTextPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
              )),
            ],
          ),
          const SizedBox(height: 10),
          ...rights.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 14, color: AppColors.success),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                    r,
                    style: isUrdu
                        ? AppTextStyles.urduLabel
                        : AppTextStyles.bodySmall.copyWith(
                            color: context.hcTextPrimary,
                          ),
                    textDirection:
                        isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
