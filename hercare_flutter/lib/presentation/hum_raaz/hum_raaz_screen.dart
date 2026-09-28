import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../providers/language_provider.dart';

class HumRaazScreen extends StatelessWidget {
  const HumRaazScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          isUrdu ? 'ہم راز' : 'Hum-Raaz',
          style: AppTextStyles.titleMedium,
        ),
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              isUrdu ? 'ہم راز جلد آ رہا ہے' : 'Hum-Raaz is coming soon',
              style: AppTextStyles.titleMedium,
            ),
            const SizedBox(height: 12),
            Text(
              isUrdu
                  ? 'یہ فیچر فیز 3 کا حصہ ہے۔'
                  : 'This feature is part of Phase 3.',
              style: AppTextStyles.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
