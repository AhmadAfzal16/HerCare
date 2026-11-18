import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../data/models/therapy_models.dart';
import '../../providers/therapy_provider.dart';
import '../../providers/language_provider.dart';
import '../../services/mood_service.dart';
import 'session_check_card.dart';

Future<TherapySession?> showTherapyCompletionSheet(
  BuildContext context, {
  required String type,
  required String activityId,
  required int durationSeconds,
  required bool isUrdu,
  bool completed = true,
  TherapyMeasures? measures,
}) async {
  final provider = context.read<TherapyProvider>();
  final session = await showModalBottomSheet<TherapySession>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _CompletionSheet(
      provider: provider,
      owner: provider.accountId,
      hostContext: context,
      type: type,
      activityId: activityId,
      durationSeconds: durationSeconds,
      isUrdu: isUrdu,
      completed: completed,
      measures: measures ?? const TherapyMeasures(),
    ),
  );
  if (session != null && needsSupport(session) && context.mounted) {
    await showPracticeSupport(context, isUrdu: isUrdu);
  }
  return session;
}

/// A practice may have made things worse: she said it was distressing, her
/// tension rose by 3+ points, or her mood dropped by 2+ points. Meditation
/// can occasionally increase anxiety or low mood (Farias et al. 2020).
bool needsSupport(TherapySession session) {
  final m = session.measures;
  final moodDrop = session.moodBefore != null &&
      session.moodAfter != null &&
      session.moodAfter! - session.moodBefore! <= -2;
  return m?.distressReported == true ||
      (m?.tensionChange ?? 0) >= 3 ||
      moodDrop;
}

Future<void> showPracticeSupport(BuildContext context, {required bool isUrdu}) {
  String t(String en, String ur) => isUrdu ? ur : en;
  return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => Directionality(
          textDirection: isUrdu ? TextDirection.rtl : TextDirection.ltr,
          // Scrollable: large text or a short screen must never hide the buttons.
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.volunteer_activism_outlined,
                        size: 36, color: AppColors.secondary),
                    const SizedBox(height: 8),
                    Text(t('Thank you for telling us', 'بتانے کا شکریہ'),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                        t('Sometimes a practice stirs up difficult feelings. That is not your fault. For now, try something with your eyes open, or talk to someone.',
                            'کبھی کبھی مشق مشکل احساسات جگا دیتی ہے۔ یہ آپ کی غلطی نہیں۔ ابھی آنکھیں کھلی رکھ کر کچھ آزمائیں، یا کسی سے بات کریں۔'),
                        textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          context.push('/therapy/cbt?id=grounding_54321');
                        },
                        icon: const Icon(Icons.visibility_outlined),
                        label: Text(t('5-4-3-2-1 grounding (eyes open)',
                            '5-4-3-2-1 گراؤنڈنگ (آنکھیں کھلی)'))),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          context.push('/crisis');
                        },
                        icon: const Icon(Icons.support_agent),
                        label: Text(t('Get support now', 'ابھی مدد لیں'))),
                    TextButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        child:
                            Text(t("I'm okay for now", 'ابھی میں ٹھیک ہوں'))),
                  ]))));
}

class _CompletionSheet extends StatefulWidget {
  const _CompletionSheet({
    required this.provider,
    required this.owner,
    required this.hostContext,
    required this.type,
    required this.activityId,
    required this.durationSeconds,
    required this.isUrdu,
    required this.completed,
    required this.measures,
  });
  final TherapyProvider provider;
  final String? owner;
  final BuildContext hostContext;
  final String type, activityId;
  final int durationSeconds;
  final bool isUrdu, completed;
  final TherapyMeasures measures;

  @override
  State<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<_CompletionSheet> {
  final _requestId = MoodService.requestId();
  int? _before, _after, _submittedBefore, _submittedAfter;
  bool _saving = false, _attempted = false;
  bool _liveUrdu = false;
  String? _error;
  DateTime? _submittedAt;
  String? _participation, _submittedParticipation;
  int? _tensionAfter;
  bool? _distress;
  TherapyMeasures? _submittedMeasures;
  bool get _monitored =>
      widget.type == 'breathing' || widget.type == 'meditation';

  bool get _sameAccount =>
      widget.provider.canUseAccount &&
      widget.provider.accountId == widget.owner;
  String _text(String en, String ur) => _liveUrdu ? ur : en;
  String get _errorText => _error == 'full'
      ? _text('Offline storage is full. Reconnect, then retry this save.',
          'آف لائن جگہ بھر گئی ہے۔ انٹرنیٹ بحال کر کے دوبارہ محفوظ کریں۔')
      : _error == 'access'
          ? _text('Please sign in and review your consent before saving.',
              'محفوظ کرنے کے لیے سائن اِن کریں اور اپنی رضامندی کا جائزہ لیں۔')
          : _text('Could not save. Retry keeps the same save ID and ratings.',
              'محفوظ نہیں ہوا۔ دوبارہ کوشش میں یہی ریکارڈ اور موڈ برقرار رہیں گے۔');

  Future<void> _save() async {
    if (_saving || !_sameAccount) return;
    if (!_attempted) {
      _submittedBefore = _before;
      _submittedAfter = _after;
      _submittedParticipation = _participation;
      _submittedAt = DateTime.now();
      _submittedMeasures = _monitored
          ? widget.measures.copyWith(
              tensionAfter: _tensionAfter, distressReported: _distress)
          : null;
    }
    setState(() {
      _saving = true;
      _attempted = true;
      _error = null;
    });
    final session = await widget.provider.complete(
      type: widget.type,
      activityId: widget.activityId,
      durationSeconds: widget.durationSeconds.clamp(1, 7200),
      moodBefore: _submittedBefore,
      moodAfter: _submittedAfter,
      breathingParticipation: _submittedParticipation,
      completed: widget.completed,
      clientRequestId: _requestId,
      clientCompletedAt: _submittedAt,
      measures: _submittedMeasures == null || _submittedMeasures!.isEmpty
          ? null
          : _submittedMeasures,
    );
    if (!mounted) return;
    if (!_sameAccount) {
      setState(() => _saving = false);
      return;
    }
    if (session != null) {
      if (!session.isSynced && widget.hostContext.mounted) {
        ScaffoldMessenger.maybeOf(widget.hostContext)?.showSnackBar(SnackBar(
          content: Text(_text(
            'Saved securely on this phone. Reopen or refresh Activities after reconnecting to sync.',
            'اس فون پر محفوظ ہے۔ انٹرنیٹ بحال ہونے پر مشقیں دوبارہ کھولیں یا تازہ کریں۔',
          )),
        ));
      }
      Navigator.pop(context, session);
      return;
    }
    setState(() {
      _saving = false;
      final error = widget.provider.error ?? '';
      _error = error.contains('full')
          ? 'full'
          : error.contains('sign in')
              ? 'access'
              : 'retry';
    });
  }

  @override
  Widget build(BuildContext context) {
    _liveUrdu = context.watch<LanguageProvider?>()?.isUrdu ?? widget.isUrdu;
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) => PopScope(
        canPop: !_saving || !_sameAccount,
        child: Directionality(
          textDirection: _liveUrdu ? TextDirection.rtl : TextDirection.ltr,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .9),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  20, 22, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.favorite_rounded,
                      color: AppColors.secondary, size: 38),
                  const SizedBox(height: 8),
                  Text(
                    _text(
                        widget.completed
                            ? 'Save your activity'
                            : 'Save partial practice',
                        widget.completed
                            ? 'اپنی مشق محفوظ کریں'
                            : 'نامکمل مشق محفوظ کریں'),
                    textAlign: TextAlign.center,
                    style: AppTextStyles.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (!_sameAccount)
                    Text(
                        _text(
                          'Your account changed. Close this page and reopen the activity.',
                          'اکاؤنٹ بدل گیا ہے۔ یہ صفحہ بند کر کے مشق دوبارہ کھولیں۔',
                        ),
                        textAlign: TextAlign.center)
                  else ...[
                    if (widget.type == 'breathing') ...[
                      Text(_text('How much did you follow? (Optional)',
                          'آپ نے کتنی ہدایات پر عمل کیا؟ (اختیاری)')),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          for (final (value, en, ur) in const [
                            ('most_cues', 'Most cues', 'زیادہ تر ہدایات'),
                            ('some_cues', 'Some cues', 'کچھ ہدایات'),
                            ('stopped_early', 'Stopped early', 'جلد رک گئیں'),
                          ])
                            ChoiceChip(
                              label: Text(_text(en, ur)),
                              selected: _participation == value,
                              onSelected: _attempted
                                  ? null
                                  : (selected) => setState(() =>
                                      _participation = selected ? value : null),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_monitored) ...[
                      _Comparison(
                          measures: widget.measures
                              .copyWith(tensionAfter: _tensionAfter),
                          isUrdu: _liveUrdu),
                      // Opens automatically when she did a before-check, so
                      // the "after" questions pair with what she recorded.
                      ExpansionTile(
                        key: const Key('after-check'),
                        tilePadding: EdgeInsets.zero,
                        initiallyExpanded: !widget.measures.isEmpty,
                        title: Text(
                            _text('How do you feel now? (optional)',
                                'اب آپ کیسا محسوس کر رہی ہیں؟ (اختیاری)'),
                            style: AppTextStyles.labelLarge),
                        children: [
                          TensionSlider(
                              key: const Key('tension-after'),
                              label: _text(
                                  'How tense do you feel now? (Optional)',
                                  'اب آپ کتنا تناؤ محسوس کر رہی ہیں؟ (اختیاری)'),
                              value: _tensionAfter,
                              isUrdu: _liveUrdu,
                              onChanged: _attempted
                                  ? null
                                  : (value) =>
                                      setState(() => _tensionAfter = value)),
                          const SizedBox(height: 8),
                          Text(
                              _text(
                                  'Did anything during this practice feel distressing or uncomfortable? (Optional)',
                                  'کیا اس مشق کے دوران کچھ پریشان کن یا تکلیف دہ محسوس ہوا؟ (اختیاری)'),
                              textAlign: TextAlign.center),
                          Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              children: [
                                for (final (value, en, ur) in const [
                                  (false, 'No', 'نہیں'),
                                  (true, 'Yes', 'ہاں'),
                                ])
                                  ChoiceChip(
                                      key: Key('distress-$value'),
                                      label: Text(_text(en, ur)),
                                      selected: _distress == value,
                                      onSelected: _attempted
                                          ? null
                                          : (selected) => setState(() =>
                                              _distress =
                                                  selected ? value : null)),
                              ]),
                          const SizedBox(height: 8),
                        ],
                      ),
                    ],
                    Text(
                        _text(
                          'Mood ratings are optional. You can save with no extra answers.',
                          'موڈ بتانا اختیاری ہے۔ بغیر مزید جواب دیے محفوظ کر سکتی ہیں۔',
                        ),
                        textAlign: TextAlign.center,
                        style: AppTextStyles.bodyMedium),
                    const SizedBox(height: 8),
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                          _text(
                            'Add mood ratings (optional)',
                            'موڈ کی کیفیت شامل کریں (اختیاری)',
                          ),
                          style: AppTextStyles.labelLarge),
                      children: [
                        Text(
                            _text(
                              '“Before” is how you remember feeling just before practice. It is not a measured baseline or a depression score.',
                              '“پہلے” سے مراد مشق سے پہلے کی یاد کی گئی کیفیت ہے، ناپی ہوئی ابتدائی کیفیت یا ڈپریشن اسکور نہیں۔',
                            ),
                            style: AppTextStyles.bodySmall),
                        const SizedBox(height: 12),
                        _MoodRow(
                          label: _text(
                              'Before — recalled', 'پہلے — یاد کی گئی کیفیت'),
                          value: _before,
                          isUrdu: _liveUrdu,
                          onChanged: _attempted
                              ? null
                              : (value) => setState(() => _before = value),
                        ),
                        const SizedBox(height: 14),
                        _MoodRow(
                          label: _text('Now', 'اب'),
                          value: _after,
                          isUrdu: _liveUrdu,
                          onChanged: _attempted
                              ? null
                              : (value) => setState(() => _after = value),
                        ),
                        const SizedBox(height: 8),
                        if (!_attempted && (_before != null || _after != null))
                          TextButton(
                            onPressed: () => setState(() {
                              _before = null;
                              _after = null;
                            }),
                            child: Text(_text('Clear optional ratings',
                                'اختیاری موڈ صاف کریں')),
                          ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(_errorText,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.bodyMedium
                              .copyWith(color: AppColors.error)),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Text(_text(
                                _attempted
                                    ? 'Retry save'
                                    : widget.completed
                                        ? 'Save completion'
                                        : 'Save partial',
                                _attempted
                                    ? 'دوبارہ محفوظ کریں'
                                    : widget.completed
                                        ? 'مشق محفوظ کریں'
                                        : 'نامکمل محفوظ کریں')),
                      ),
                    ),
                  ],
                  TextButton(
                    onPressed: _saving && _sameAccount
                        ? null
                        : () => Navigator.pop(context),
                    child: Text(_text(
                        'Close without saving', 'محفوظ کیے بغیر بند کریں')),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Before → after summary, shown only for values she actually recorded.
class _Comparison extends StatelessWidget {
  const _Comparison({required this.measures, required this.isUrdu});
  final TherapyMeasures measures;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    final rows = <String>[
      if (measures.tensionBefore != null && measures.tensionAfter != null)
        isUrdu
            ? 'تناؤ: ${measures.tensionBefore} ← ${measures.tensionAfter}'
            : 'Tension: ${measures.tensionBefore} → ${measures.tensionAfter}',
      if (measures.hrBefore != null && measures.hrAfter != null)
        isUrdu
            ? 'دل کی رفتار: ${measures.hrBefore} ← ${measures.hrAfter}'
            : 'Heart rate: ${measures.hrBefore} → ${measures.hrAfter} bpm',
      if (measures.hrvBefore != null && measures.hrvAfter != null)
        isUrdu
            ? 'تغیر: ${measures.hrvBefore} ← ${measures.hrvAfter} ملی سیکنڈ'
            : 'Variability: ${measures.hrvBefore} → ${measures.hrvAfter} ms',
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: AppColors.primaryContainer.withValues(alpha: .5),
            borderRadius: BorderRadius.circular(14)),
        child: Column(children: [
          for (final row in rows) Text(row, style: AppTextStyles.labelLarge),
          if (measures.physioSource == 'camera')
            Text(
                isUrdu
                    ? 'کیمرے کی پیمائش تخمینی ہے۔'
                    : 'Camera readings are approximate.',
                style: AppTextStyles.bodySmall),
        ]));
  }
}

class _MoodRow extends StatelessWidget {
  const _MoodRow({
    required this.label,
    required this.value,
    required this.isUrdu,
    required this.onChanged,
  });
  final String label;
  final int? value;
  final bool isUrdu;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(label,
            style: AppTextStyles.labelLarge, textAlign: TextAlign.center),
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
              selected: value == rating,
              label: isUrdu
                  ? '$label، موڈ $rating از 5'
                  : '$label mood $rating of 5',
              child: InkWell(
                onTap: onChanged == null ? null : () => onChanged!(rating),
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
