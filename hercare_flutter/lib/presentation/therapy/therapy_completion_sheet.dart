import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/therapy_provider.dart';

Future<TherapySession?> showTherapyCompletionSheet(
  BuildContext context, {
  required String type,
  required String activityId,
  required int durationSeconds,
  required bool isUrdu,
}) async {
  int? before;
  int? after;
  return showModalBottomSheet<TherapySession>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.fromLTRB(
            20, 22, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.favorite_rounded,
                color: AppColors.secondary, size: 38),
            const SizedBox(height: 8),
            Text(isUrdu ? 'آپ کیسا محسوس کر رہی ہیں؟' : 'How do you feel?',
                textAlign: TextAlign.center, style: AppTextStyles.titleLarge),
            const SizedBox(height: 18),
            _MoodRow(
              label: isUrdu ? 'مشق سے پہلے' : 'Before',
              value: before,
              onChanged: (value) => setState(() => before = value),
            ),
            const SizedBox(height: 14),
            _MoodRow(
              label: isUrdu ? 'اب' : 'Now',
              value: after,
              onChanged: (value) => setState(() => after = value),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: before == null || after == null
                    ? null
                    : () async {
                        final session = await sheetContext
                            .read<TherapyProvider>()
                            .complete(
                              type: type,
                              activityId: activityId,
                              durationSeconds: durationSeconds.clamp(1, 7200),
                              moodBefore: before,
                              moodAfter: after,
                            );
                        if (sheetContext.mounted && session != null) {
                          Navigator.pop(sheetContext, session);
                        }
                      },
                child: Text(isUrdu ? 'مکمل کریں' : 'Save completion'),
              ),
            ),
            TextButton(
              onPressed: () async {
                final session =
                    await sheetContext.read<TherapyProvider>().complete(
                          type: type,
                          activityId: activityId,
                          durationSeconds: durationSeconds.clamp(1, 7200),
                        );
                if (sheetContext.mounted && session != null) {
                  Navigator.pop(sheetContext, session);
                }
              },
              child: Text(
                  isUrdu ? 'موڈ بتائے بغیر محفوظ کریں' : 'Save without mood'),
            ),
          ]),
        ),
      ),
    ),
  );
}

class _MoodRow extends StatelessWidget {
  const _MoodRow(
      {required this.label, required this.value, required this.onChanged});
  final String label;
  final int? value;
  final ValueChanged<int> onChanged;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label, style: AppTextStyles.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: List.generate(5, (index) {
            const faces = ['😞', '😕', '😐', '🙂', '😊'];
            final rating = index + 1;
            return Semantics(
              button: true,
              label: '$label mood $rating of 5',
              child: InkWell(
                onTap: () => onChanged(rating),
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: value == rating
                        ? AppColors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: value == rating
                            ? AppColors.primary
                            : AppColors.outline),
                  ),
                  child:
                      Text(faces[index], style: const TextStyle(fontSize: 23)),
                ),
              ),
            );
          }),
        ),
      ]);
}
