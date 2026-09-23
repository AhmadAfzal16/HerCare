import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';

class CrisisSupportScreen extends StatelessWidget {
  const CrisisSupportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(title: const Text('Immediate support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Icon(Icons.health_and_safety_rounded,
                size: 68, color: AppColors.crisis),
            const SizedBox(height: 18),
            Text('You deserve immediate support',
                textAlign: TextAlign.center,
                style: AppTextStyles.headlineSmall),
            const SizedBox(height: 12),
            Text(
              'Please stay with someone you trust and do not remain alone. If you may act on these thoughts, go to the nearest emergency department or contact local emergency services now.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodyLarge,
            ),
            const SizedBox(height: 24),
            const _SafetyStep(
                number: '1',
                text:
                    'Move away from anything you could use to hurt yourself.'),
            const _SafetyStep(
                number: '2',
                text:
                    'Tell a trusted person clearly that you need them to stay with you.'),
            const _SafetyStep(
                number: '3',
                text: 'Seek urgent professional or emergency help now.'),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Return when I am with support'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SafetyStep extends StatelessWidget {
  const _SafetyStep({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.hcSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withValues(alpha: .3)),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.errorContainer,
              foregroundColor: AppColors.error,
              child: Text(number),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: AppTextStyles.bodyMedium)),
          ],
        ),
      );
}
