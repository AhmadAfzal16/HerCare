import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';

/// Login Screen
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _phoneCtr    = TextEditingController();
  final _passwordCtr = TextEditingController();
  bool _obscure      = true;

  @override
  void dispose() {
    _phoneCtr.dispose();
    _passwordCtr.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      phone:    '+92${_phoneCtr.text.trim()}',
      password: _passwordCtr.text,
    );
    if (success && mounted) context.go(AppRoutes.home);
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    final auth   = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: context.hcBg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: isUrdu
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withOpacity(0.3),
                          blurRadius: 20, offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(Icons.favorite_rounded,
                        color: Colors.white, size: 36),
                  ),
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    isUrdu ? 'واپس خوش آمدید' : 'Welcome Back',
                    style: AppTextStyles.headlineSmall,
                    textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  ),
                ),
                Center(
                  child: Text(
                    isUrdu ? 'اپنے اکاؤنٹ میں داخل ہوں' : 'Log in to your account',
                    style: AppTextStyles.bodyMedium,
                    textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                  ),
                ),
                const SizedBox(height: 40),

                // Phone
                Text(isUrdu ? 'فون نمبر' : 'Phone Number',
                    style: AppTextStyles.labelLarge,
                    textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phoneCtr,
                  keyboardType: TextInputType.phone,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.phone_outlined),
                    prefixText: '+92 ',
                    hintText: '3XX XXXXXXX',
                  ),
                  validator: (v) {
                    final val = v?.trim() ?? '';
                    if (val.isEmpty) return isUrdu ? 'فون نمبر ضروری ہے' : 'Required';
                    if (!RegExp(r'^[0-9]{10}$').hasMatch(val)) {
                      return isUrdu ? '10 ہندسے' : '10 digits';
                    }
                    return null;
                  },
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),
                const SizedBox(height: 18),

                // Password
                Text(isUrdu ? 'پاس ورڈ' : 'Password',
                    style: AppTextStyles.labelLarge,
                    textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _passwordCtr,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      icon: Icon(_obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) =>
                      (v?.isEmpty ?? true) ? (isUrdu ? 'پاس ورڈ ضروری ہے' : 'Required') : null,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                ),

                const SizedBox(height: 12),

                if (auth.errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(auth.errorMessage!,
                              style: AppTextStyles.bodySmall.copyWith(color: AppColors.error),
                              textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 28),

                SizedBox(
                  width: double.infinity, height: 54,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: AppColors.primary.withOpacity(0.35),
                            blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: auth.isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: auth.isLoading
                          ? const SizedBox(width: 22, height: 22,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                          : Text(isUrdu ? 'لاگ ان کریں' : 'Log In',
                              style: AppTextStyles.labelLarge.copyWith(color: Colors.white)),
                    ),
                  ),
                ),

                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: () => context.go(AppRoutes.register),
                    child: Text(
                      isUrdu ? 'اکاؤنٹ نہیں ہے؟ بنائیں' : 'Don\'t have an account? Register',
                      style: AppTextStyles.bodyMedium.copyWith(color: AppColors.primary),
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
