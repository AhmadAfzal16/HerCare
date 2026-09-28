import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../providers/auth_provider.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/language_provider.dart';

class GuardianLinkScreen extends StatefulWidget {
  const GuardianLinkScreen({super.key});

  @override
  State<GuardianLinkScreen> createState() => _GuardianLinkScreenState();
}

class _GuardianLinkScreenState extends State<GuardianLinkScreen> {
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  String _relationship = 'husband';
  bool _codeCopied = false;

  static const _relationships = [
    'husband',
    'mother',
    'sister',
    'brother',
    'father',
    'friend',
    'other'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final role = context.read<AuthProvider>().user?.role;
      final guardian = context.read<GuardianProvider>();
      guardian.loadLink();
      if (role == 'mother') guardian.loadOrGenerateInvite();
    });
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _copyCode(String code) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    setState(() => _codeCopied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _codeCopied = false);
  }

  Future<void> _acceptInvite() async {
    if (_codeCtrl.text.trim().length != 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code must be exactly 12 characters')),
      );
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your name')),
      );
      return;
    }
    final ok = await context.read<GuardianProvider>().acceptInvite(
          code: _codeCtrl.text.trim(),
          name: _nameCtrl.text.trim(),
          relationship: _relationship,
        );
    if (mounted) {
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Successfully linked!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        final err = context.read<GuardianProvider>().error ?? 'Failed to link';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(err), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _revokeLink() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.hcSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Revoke Guardian Access', style: AppTextStyles.titleMedium),
        content: Text(
          'Your guardian will no longer receive reports or alerts.',
          style: AppTextStyles.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: TextStyle(color: context.hcTextSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke',
                style: TextStyle(
                    color: AppColors.error, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await context.read<GuardianProvider>().revokeLink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final provider = context.watch<GuardianProvider>();
    final role = context.watch<AuthProvider>().user?.role;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.hcTextPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          isUrdu ? 'سرپرست ربط' : 'Guardian Link',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
      ),
      body: role == 'guardian'
          ? _buildEnterCodeTab(context, provider, isUrdu)
          : _buildShareCodeTab(context, provider, isUrdu),
    );
  }

  // ─── Tab 1: Share Code ──────────────────────────────────────────────────────

  Widget _buildShareCodeTab(
      BuildContext context, GuardianProvider provider, bool isUrdu) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Active link banner
        if (provider.hasActiveLink) ...[
          _ActiveLinkCard(
            link: provider.link!,
            isUrdu: isUrdu,
            onRevoke: _revokeLink,
          ),
          const SizedBox(height: 20),
        ],

        // Invite code card
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.link_rounded,
                  color: Colors.white.withValues(alpha: 0.8), size: 32),
              const SizedBox(height: 12),
              Text(
                isUrdu
                    ? 'یہ کوڈ اپنے سرپرست کے ساتھ شیئر کریں'
                    : 'Share this code with your guardian',
                style: AppTextStyles.bodySmall
                    .copyWith(color: Colors.white.withValues(alpha: 0.85)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Code display
              if (provider.isLoading)
                const CircularProgressIndicator(color: Colors.white)
              else if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    provider.error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: AppColors.error, fontWeight: FontWeight.w600),
                  ),
                )
              else if (provider.inviteCode != null) ...[
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.center,
                          child: Text(
                            provider.inviteCode!,
                            maxLines: 1,
                            style: AppTextStyles.headlineMedium.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        tooltip: isUrdu ? 'کوڈ کاپی کریں' : 'Copy code',
                        onPressed: () => _copyCode(provider.inviteCode!),
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 300),
                          child: Icon(
                            _codeCopied
                                ? Icons.check_circle_rounded
                                : Icons.copy_rounded,
                            key: ValueKey(_codeCopied),
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isUrdu
                      ? 'یہ کوڈ 24 گھنٹے یا استعمال تک درست ہے'
                      : 'Valid for 24 hours or until used',
                  style: AppTextStyles.labelSmall
                      .copyWith(color: Colors.white.withValues(alpha: 0.7)),
                ),
              ],
              const SizedBox(height: 20),

              // Refresh button
              TextButton.icon(
                onPressed:
                    provider.isLoading ? null : () => provider.refreshInvite(),
                icon: const Icon(Icons.refresh_rounded,
                    color: Colors.white, size: 18),
                label: Text(
                  isUrdu ? 'نیا کوڈ بنائیں' : 'Generate new code',
                  style:
                      AppTextStyles.labelMedium.copyWith(color: Colors.white),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // How it works card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: context.hcSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: context.hcOutline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isUrdu ? 'یہ کیسے کام کرتا ہے؟' : 'How it works',
                style: AppTextStyles.titleSmall,
              ),
              const SizedBox(height: 12),
              _HowItWorksStep(
                step: '1',
                text: isUrdu ? 'اوپر کوڈ کاپی کریں' : 'Copy the code above',
                icon: Icons.copy_rounded,
              ),
              _HowItWorksStep(
                step: '2',
                text: isUrdu
                    ? 'اپنے شوہر/سرپرست کے ساتھ شیئر کریں'
                    : 'Share it with your husband/guardian',
                icon: Icons.share_rounded,
              ),
              _HowItWorksStep(
                step: '3',
                text: isUrdu
                    ? 'وہ HerCare کھولیں اور "کوڈ درج کریں" ٹیب میں جائیں'
                    : 'They open HerCare and tap "Enter Code"',
                icon: Icons.phone_android_rounded,
              ),
              _HowItWorksStep(
                step: '4',
                text: isUrdu
                    ? 'وہ آپ کی صحت کی رپورٹیں دیکھ سکیں گے'
                    : 'They will see your health summaries',
                icon: Icons.favorite_rounded,
                isLast: true,
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Tab 2: Enter Code ──────────────────────────────────────────────────────

  Widget _buildEnterCodeTab(
      BuildContext context, GuardianProvider provider, bool isUrdu) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Active link banner
        if (provider.hasActiveLink) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.successContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.success),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    isUrdu
                        ? 'آپ پہلے سے ایک اکاؤنٹ سے جڑے ہوئے ہیں'
                        : 'You are already linked to an account',
                    style: AppTextStyles.bodySmall
                        .copyWith(color: AppColors.success),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Enter code section
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: context.hcSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: context.hcOutline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.vpn_key_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(isUrdu ? 'کوڈ درج کریں' : 'Enter Invite Code',
                            style: AppTextStyles.titleSmall),
                        Text(
                            isUrdu
                                ? 'ماں سے کوڈ لیں'
                                : 'Get the code from the mother',
                            style:
                                AppTextStyles.bodySmall.copyWith(fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Invite code field
              TextField(
                controller: _codeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 12,
                style: AppTextStyles.titleMedium.copyWith(
                  letterSpacing: 4,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  labelText: isUrdu ? '12 حروف کا کوڈ' : '12-character code',
                  filled: true,
                  fillColor: context.hcBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.hcOutline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 2),
                  ),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),

              // Name field
              TextField(
                controller: _nameCtrl,
                style: AppTextStyles.bodyMedium,
                decoration: InputDecoration(
                  labelText: isUrdu ? 'آپ کا نام' : 'Your Name',
                  filled: true,
                  fillColor: context.hcBg,
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.hcOutline),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppColors.primary, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Relationship dropdown
              DropdownButtonFormField<String>(
                initialValue: _relationship,
                dropdownColor: context.hcSurface,
                decoration: InputDecoration(
                  labelText: isUrdu ? 'رشتہ' : 'Relationship',
                  filled: true,
                  fillColor: context.hcBg,
                  prefixIcon: const Icon(Icons.people_outline_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: context.hcOutline),
                  ),
                ),
                items: _relationships
                    .map((r) => DropdownMenuItem(
                          value: r,
                          child: Text(r[0].toUpperCase() + r.substring(1)),
                        ))
                    .toList(),
                onChanged: (val) =>
                    setState(() => _relationship = val ?? 'husband'),
              ),
              const SizedBox(height: 24),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: provider.isLoading || provider.hasActiveLink
                      ? null
                      : _acceptInvite,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: provider.isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isUrdu ? 'ربط قائم کریں' : 'Link Account',
                          style: AppTextStyles.labelLarge
                              .copyWith(color: Colors.white),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _ActiveLinkCard extends StatelessWidget {
  final Map<String, dynamic> link;
  final bool isUrdu;
  final VoidCallback onRevoke;
  const _ActiveLinkCard(
      {required this.link, required this.isUrdu, required this.onRevoke});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.shield_rounded, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isUrdu ? '✅ سرپرست فعال ہے' : '✅ Guardian Active',
                  style: AppTextStyles.titleSmall
                      .copyWith(color: AppColors.primary),
                ),
                Text(
                  isUrdu
                      ? 'آپ کی رپورٹیں شیئر ہو رہی ہیں'
                      : 'Reports are being shared',
                  style: AppTextStyles.bodySmall.copyWith(fontSize: 11),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRevoke,
            child: Text(
              isUrdu ? 'منسوخ' : 'Revoke',
              style: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String step;
  final String text;
  final IconData icon;
  final bool isLast;
  const _HowItWorksStep({
    required this.step,
    required this.text,
    required this.icon,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(step,
                  style: AppTextStyles.labelSmall.copyWith(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text,
                style: AppTextStyles.bodySmall.copyWith(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
