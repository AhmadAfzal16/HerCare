import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});

  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  // Dummy state for toggles until connected to backend
  bool consentTier1 = true;
  bool consentTier2 = true;
  bool consentTier3 = false;

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isUrdu ? 'میرا ڈیٹا اور پرائیویسی' : 'My Data & Privacy',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: context.hcTextPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          physics: const BouncingScrollPhysics(),
          children: [
            Text(
              isUrdu ? 'رضامندی کی ترتیبات' : 'Consent Settings',
              style: AppTextStyles.titleMedium.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            
            _buildSwitchTile(
              title: isUrdu ? 'بنیادی ایپ کا استعمال (درکار)' : 'Basic App Usage (Required)',
              subtitle: isUrdu 
                  ? 'ایپ کے کام کرنے کے لیے آپ کا ڈیٹا درکار ہے۔' 
                  : 'Required data for the app to function.',
              value: consentTier1,
              onChanged: (val) {
                // Tier 1 is usually required, so maybe we don't let them turn it off easily,
                // but for demo purposes:
                setState(() => consentTier1 = val);
              },
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              title: isUrdu ? 'تحقیق کے لیے ڈیٹا شیئرنگ' : 'Data Sharing for Research',
              subtitle: isUrdu 
                  ? 'اپنے گمنام ڈیٹا کو ریسرچ کے مقاصد کے لیے شیئر کریں۔' 
                  : 'Share your anonymized data for research purposes.',
              value: consentTier2,
              onChanged: (val) {
                setState(() => consentTier2 = val);
              },
            ),
            const SizedBox(height: 12),
            _buildSwitchTile(
              title: isUrdu ? 'مارکیٹنگ اور پروموشنز' : 'Marketing & Promotions',
              subtitle: isUrdu 
                  ? 'صحت سے متعلق پروموشنز وصول کریں۔' 
                  : 'Receive health-related promotions.',
              value: consentTier3,
              onChanged: (val) {
                setState(() => consentTier3 = val);
              },
            ),

            const SizedBox(height: 32),
            Text(
              isUrdu ? 'ڈیٹا مینجمنٹ' : 'Data Management',
              style: AppTextStyles.titleMedium.copyWith(color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            
            _buildActionTile(
              icon: Icons.download_rounded,
              title: isUrdu ? 'میرا ڈیٹا ڈاؤن لوڈ کریں' : 'Download My Data',
              onTap: () {
                // Implement Data Export
              },
            ),
            const SizedBox(height: 12),
            _buildActionTile(
              icon: Icons.delete_forever_rounded,
              title: isUrdu ? 'اکاؤنٹ حذف کریں' : 'Delete Account',
              iconColor: AppColors.error,
              textColor: AppColors.error,
              onTap: () {
                // Implement Account Deletion
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.titleSmall),
                const SizedBox(height: 4),
                Text(
                  subtitle, 
                  style: AppTextStyles.bodySmall.copyWith(color: context.hcTextSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    Color? iconColor,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: context.hcSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor ?? AppColors.primary),
            const SizedBox(width: 16),
            Text(
              title,
              style: AppTextStyles.titleSmall.copyWith(color: textColor ?? AppColors.textPrimary),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right_rounded, 
              color: AppColors.textSecondary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
