import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';

@immutable
class PendingRegistration {
  const PendingRegistration({
    required this.phone,
    required this.password,
    required this.language,
  });

  final String phone;
  final String password;
  final String language;
}

class AccountTypeScreen extends StatefulWidget {
  const AccountTypeScreen({super.key, required this.registration});

  final PendingRegistration registration;

  @override
  State<AccountTypeScreen> createState() => _AccountTypeScreenState();
}

class _AccountTypeScreenState extends State<AccountTypeScreen> {
  String? _selectedRole;

  Future<void> _continue() async {
    final role = _selectedRole;
    if (role == null) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.register(
      phone: widget.registration.phone,
      password: widget.registration.password,
      role: role,
      language: widget.registration.language,
    );
    if (!mounted || !success) return;

    if (role == 'guardian') {
      context.go(AppRoutes.guardianHome);
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed:
              auth.isLoading ? null : () => context.go(AppRoutes.register),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                gradient: AppColors.primaryGradient,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.people_alt_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isUrdu
                  ? 'آپ HerCare کیسے استعمال کریں گے؟'
                  : 'How will you use HerCare?',
              textAlign: TextAlign.center,
              style: AppTextStyles.headlineSmall,
            ),
            const SizedBox(height: 10),
            Text(
              isUrdu
                  ? 'صحیح تجربہ ترتیب دینے کے لیے اپنے اکاؤنٹ کی قسم منتخب کریں۔'
                  : 'Choose your account type so we can set up the right, privacy-safe experience.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyMedium,
            ),
            const SizedBox(height: 30),
            _AccountTypeCard(
              selected: _selectedRole == 'mother',
              icon: Icons.favorite_rounded,
              color: AppColors.secondary,
              title: isUrdu ? 'میں ماں ہوں' : 'I am a mother',
              subtitle: isUrdu
                  ? 'ذاتی اسکریننگ، موڈ، نیند، مدد اور رضامندی کی ترتیبات'
                  : 'Personal screening, mood, sleep, support, and consent settings',
              badge: isUrdu ? 'مریض کا تجربہ' : 'Mother experience',
              onTap: auth.isLoading
                  ? null
                  : () => setState(() => _selectedRole = 'mother'),
            ),
            const SizedBox(height: 16),
            _AccountTypeCard(
              selected: _selectedRole == 'guardian',
              icon: Icons.shield_rounded,
              color: AppColors.primary,
              title: isUrdu
                  ? 'میں سرپرست یا شریک حیات ہوں'
                  : 'I am a guardian or spouse',
              subtitle: isUrdu
                  ? 'دعوتی کوڈ کے ذریعے جڑیں اور صرف مجموعی صحت کی معلومات دیکھیں'
                  : 'Connect by invitation and view only aggregate health summaries',
              badge: isUrdu ? 'سپورٹ کا تجربہ' : 'Guardian experience',
              onTap: auth.isLoading
                  ? null
                  : () => setState(() => _selectedRole = 'guardian'),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_outline_rounded,
                    size: 18, color: AppColors.success),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isUrdu
                        ? 'سرپرست کبھی بھی ذاتی ڈائری یا نجی گفتگو نہیں دیکھ سکتے۔'
                        : 'Guardians can never access private journals or personal conversations.',
                    style: AppTextStyles.bodySmall,
                  ),
                ),
              ],
            ),
            if (auth.errorMessage != null) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.errorContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  auth.errorMessage!,
                  style:
                      AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                ),
              ),
            ],
            const SizedBox(height: 28),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed:
                    _selectedRole == null || auth.isLoading ? null : _continue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: context.hcOutline,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: auth.isLoading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.4,
                        ),
                      )
                    : Text(
                        isUrdu ? 'اکاؤنٹ مکمل کریں' : 'Complete account setup',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountTypeCard extends StatelessWidget {
  const _AccountTypeCard({
    required this.selected,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: context.hcSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? color : context.hcOutline,
              width: selected ? 2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withOpacity(0.14),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTextStyles.titleSmall),
                    const SizedBox(height: 5),
                    Text(subtitle, style: AppTextStyles.bodySmall),
                    const SizedBox(height: 10),
                    Text(
                      badge,
                      style: AppTextStyles.labelSmall.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                color: selected ? color : context.hcTextHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
