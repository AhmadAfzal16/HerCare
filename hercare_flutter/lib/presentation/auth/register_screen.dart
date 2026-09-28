import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';
import 'account_type_screen.dart';

/// Registration Screen
/// Phone + password registration with bilingual validation.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtr = TextEditingController();
  final _passwordCtr = TextEditingController();
  final _confirmCtr = TextEditingController();
  bool _obscurePass = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _phoneCtr.dispose();
    _passwordCtr.dispose();
    _confirmCtr.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final isUrdu = context.read<LanguageProvider>().isUrdu;
    context.push(
      AppRoutes.accountType,
      extra: PendingRegistration(
        phone: '+92${_phoneCtr.text.trim()}',
        password: _passwordCtr.text,
        language: isUrdu ? 'ur' : 'en',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    return Scaffold(
      backgroundColor: context.hcBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment:
                  isUrdu ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                // ── Logo ──────────────────────────────────────────────────
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 20,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Title ─────────────────────────────────────────────────
                Center(
                  child: Text(
                    isUrdu ? 'اکاؤنٹ بنائیں' : 'Create Account',
                    style: AppTextStyles.headlineSmall,
                    textDirection:
                        isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    isUrdu ? 'HerCare میں خوش آمدید' : 'Welcome to HerCare',
                    style: AppTextStyles.bodyMedium,
                    textDirection:
                        isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  ),
                ),
                const SizedBox(height: 36),

                // ── Phone ─────────────────────────────────────────────────
                Text(
                  isUrdu ? 'فون نمبر' : 'Phone Number',
                  style: AppTextStyles.labelLarge,
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneCtr,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.phone_outlined),
                    prefixText: '+92 ',
                    hintText: '3XX XXXXXXX',
                  ),
                  validator: (v) {
                    final val = v?.trim() ?? '';
                    if (val.isEmpty)
                      return isUrdu ? 'فون نمبر ضروری ہے' : 'Phone required';
                    if (!RegExp(r'^[0-9]{10}$').hasMatch(val)) {
                      return isUrdu
                          ? '10 ہندسے درج کریں'
                          : 'Enter 10 digits after +92';
                    }
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 18),

                // ── Password ──────────────────────────────────────────────
                Text(
                  isUrdu ? 'پاس ورڈ' : 'Password',
                  style: AppTextStyles.labelLarge,
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordCtr,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                    hintText: isUrdu ? '8+ حروف' : 'Min 8 characters',
                  ),
                  validator: (v) {
                    final val = v ?? '';
                    if (val.length < 8) {
                      return isUrdu
                          ? 'کم از کم 8 حروف'
                          : 'Minimum 8 characters';
                    }
                    if (!RegExp(r'[A-Z]').hasMatch(val)) {
                      return isUrdu
                          ? 'ایک بڑا حرف ضروری ہے'
                          : 'Need at least one uppercase letter';
                    }
                    if (!RegExp(r'[0-9]').hasMatch(val)) {
                      return isUrdu
                          ? 'ایک نمبر ضروری ہے'
                          : 'Need at least one number';
                    }
                    if (!RegExp(r'[^A-Za-z0-9]').hasMatch(val)) {
                      return isUrdu
                          ? 'ایک خاص علامت ضروری ہے'
                          : 'Need at least one special character';
                    }
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 18),

                // ── Confirm Password ──────────────────────────────────────
                Text(
                  isUrdu ? 'پاس ورڈ کی تصدیق کریں' : 'Confirm Password',
                  style: AppTextStyles.labelLarge,
                  textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _confirmCtr,
                  obscureText: _obscureConfirm,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    hintText: isUrdu
                        ? 'پاس ورڈ دوبارہ درج کریں'
                        : 'Re-enter password',
                  ),
                  validator: (v) {
                    if (v != _passwordCtr.text) {
                      return isUrdu
                          ? 'پاس ورڈ مختلف ہیں'
                          : 'Passwords do not match';
                    }
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),

                const SizedBox(height: 12),

                const SizedBox(height: 28),

                // ── Submit ────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.35),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: Text(
                        isUrdu ? 'جاری رکھیں' : 'Continue',
                        style: AppTextStyles.labelLarge
                            .copyWith(color: Colors.white),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Login redirect ────────────────────────────────────────
                Center(
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.login),
                    child: Text(
                      isUrdu
                          ? 'پہلے سے اکاؤنٹ ہے؟ لاگ ان کریں'
                          : 'Already have an account? Log in',
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
