import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/mood_models.dart';
import '../../providers/language_provider.dart';
import '../../providers/mood_provider.dart';

class MoodJournalScreen extends StatefulWidget {
  const MoodJournalScreen({
    super.key,
    this.initialTab = 0,
    this.initialMood,
  });

  final int initialTab;
  final int? initialMood;

  @override
  State<MoodJournalScreen> createState() => _MoodJournalScreenState();
}

class _MoodJournalScreenState extends State<MoodJournalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs =
        TabController(length: 2, vsync: this, initialIndex: widget.initialTab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MoodProvider>().load(includeJournals: true);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        surfaceTintColor: Colors.transparent,
        title: Text(
          isUrdu ? 'موڈ اور نجی جریدہ' : 'Mood & Private Journal',
          style: AppTextStyles.titleMedium,
        ),
        bottom: TabBar(
          controller: _tabs,
          tabs: [
            Tab(text: isUrdu ? 'روزانہ موڈ' : 'Daily mood'),
            Tab(text: isUrdu ? 'نجی جریدہ' : 'Private journal'),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: TabBarView(
          controller: _tabs,
          children: [
            _MoodTab(initialMood: widget.initialMood, isUrdu: isUrdu),
            _JournalTab(isUrdu: isUrdu),
          ],
        ),
      ),
    );
  }
}

class _MoodTab extends StatefulWidget {
  const _MoodTab({required this.initialMood, required this.isUrdu});

  final int? initialMood;
  final bool isUrdu;

  @override
  State<_MoodTab> createState() => _MoodTabState();
}

class _MoodTabState extends State<_MoodTab> {
  late int _mood;
  int _energy = 3;
  int _sleep = 3;
  int _support = 3;
  bool _hydrated = false;

  static const _emojis = ['😔', '😟', '😐', '🙂', '😊'];

  @override
  void initState() {
    super.initState();
    _mood = widget.initialMood?.clamp(1, 5) ?? 3;
  }

  void _hydrate(MoodCheckin? checkin) {
    if (_hydrated || checkin == null) return;
    _hydrated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _mood = checkin.moodRating;
        _energy = checkin.energyLevel;
        _sleep = checkin.sleepQuality;
        _support = checkin.socialSupport;
      });
    });
  }

  Future<void> _save() async {
    final provider = context.read<MoodProvider>();
    final ok = await provider.saveCheckin(
      moodRating: _mood,
      energyLevel: _energy,
      sleepQuality: _sleep,
      socialSupport: _support,
    );
    if (!mounted) return;
    final message = ok
        ? (provider.today?.isSynced == false
            ? (widget.isUrdu
                ? 'آف لائن محفوظ، بعد میں مطابقت ہو گی'
                : 'Saved offline and queued securely')
            : (widget.isUrdu
                ? 'آج کا موڈ محفوظ ہو گیا'
                : 'Today’s mood was saved'))
        : provider.error ?? 'Could not save mood';
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoodProvider>();
    _hydrate(provider.today);
    return RefreshIndicator(
      onRefresh: () => provider.load(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
        children: [
          Text(
            widget.isUrdu
                ? 'آج آپ کیسا محسوس کر رہی ہیں؟'
                : 'How are you feeling today?',
            style: AppTextStyles.headlineSmall,
            textAlign: widget.isUrdu ? TextAlign.right : TextAlign.left,
          ),
          const SizedBox(height: 8),
          Text(
            widget.isUrdu
                ? 'آپ کا روزانہ اندراج ذاتی ہے اور بہتر رجحانات بنانے میں مدد کرتا ہے۔'
                : 'Your daily check-in is private and helps build meaningful trends.',
            style: AppTextStyles.bodySmall,
            textAlign: widget.isUrdu ? TextAlign.right : TextAlign.left,
          ),
          const SizedBox(height: 20),
          _MoodSelector(
            value: _mood,
            emojis: _emojis,
            onChanged: (value) => setState(() => _mood = value),
          ),
          const SizedBox(height: 18),
          _MetricSlider(
            icon: Icons.bolt_rounded,
            label: widget.isUrdu ? 'توانائی' : 'Energy',
            value: _energy,
            color: AppColors.warning,
            onChanged: (value) => setState(() => _energy = value),
          ),
          _MetricSlider(
            icon: Icons.bedtime_rounded,
            label: widget.isUrdu ? 'نیند کا معیار' : 'Sleep quality',
            value: _sleep,
            color: AppColors.primary,
            onChanged: (value) => setState(() => _sleep = value),
          ),
          _MetricSlider(
            icon: Icons.people_alt_rounded,
            label: widget.isUrdu ? 'سماجی معاونت' : 'Social support',
            value: _support,
            color: AppColors.secondary,
            onChanged: (value) => setState(() => _support = value),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: provider.isLoading ? null : _save,
              icon: provider.isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(widget.isUrdu
                  ? 'آج کا موڈ محفوظ کریں'
                  : 'Save today’s check-in'),
            ),
          ),
          if (provider.today?.isSynced == false) ...[
            const SizedBox(height: 10),
            const _OfflineNotice(),
          ],
          const SizedBox(height: 26),
          _TrendCard(
              summary: provider.summary,
              history: provider.history,
              isUrdu: widget.isUrdu),
        ],
      ),
    );
  }
}

class _MoodSelector extends StatelessWidget {
  const _MoodSelector(
      {required this.value, required this.emojis, required this.onChanged});

  final int value;
  final List<String> emojis;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hcOutline),
      ),
      child: Row(
        children: List.generate(emojis.length, (index) {
          final rating = index + 1;
          final selected = rating == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              label: 'Mood $rating of 5',
              child: InkWell(
                onTap: () => onChanged(rating),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border:
                        selected ? Border.all(color: AppColors.primary) : null,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(emojis[index],
                        style: const TextStyle(fontSize: 27)),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _MetricSlider extends StatelessWidget {
  const _MetricSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final int value;
  final Color color;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hcOutline),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 9),
              Expanded(child: Text(label, style: AppTextStyles.labelLarge)),
              Text('$value/5',
                  style: AppTextStyles.labelLarge.copyWith(color: color)),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: color,
            label: '$value',
            onChanged: (next) => onChanged(next.round()),
          ),
        ],
      ),
    );
  }
}

class _TrendCard extends StatelessWidget {
  const _TrendCard(
      {required this.summary, required this.history, required this.isUrdu});

  final MoodSummary? summary;
  final List<MoodCheckin> history;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    final recent = history.take(7).toList().reversed.toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.hcOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isUrdu ? 'ہفتہ وار رجحان' : 'Weekly trend',
              style: AppTextStyles.titleSmall),
          const SizedBox(height: 4),
          Text(
            summary?.average == null
                ? (isUrdu
                    ? 'رجحان کے لیے روزانہ اندراج کریں'
                    : 'Check in daily to build your trend')
                : '${isUrdu ? "اوسط" : "Average"}: ${summary!.average!.toStringAsFixed(1)}/5',
            style: AppTextStyles.bodySmall,
          ),
          const SizedBox(height: 16),
          if (recent.isEmpty)
            const SizedBox(height: 64, child: Center(child: Text('—')))
          else
            SizedBox(
              height: 96,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: recent.map((entry) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Flexible(
                            child: FractionallySizedBox(
                              heightFactor: entry.compositeScore / 5,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(7),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 5),
                          FittedBox(
                            child: Text(
                                '${entry.entryDate.day}/${entry.entryDate.month}',
                                style: AppTextStyles.labelSmall),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

class _JournalTab extends StatefulWidget {
  const _JournalTab({required this.isUrdu});

  final bool isUrdu;

  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  final _journalController = TextEditingController();
  final _searchController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    _journalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveText() async {
    final content = _journalController.text.trim();
    if (content.isEmpty) return;
    final entry = await context.read<MoodProvider>().saveJournal(content);
    if (!mounted || entry == null) return;
    _journalController.clear();
    if (entry.containsDanger) {
      context.push(AppRoutes.crisis);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(entry.isSynced
                ? 'Private journal saved'
                : 'Encrypted draft queued offline')),
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _finishRecording();
      return;
    }
    if (!await _recorder.hasPermission()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Microphone permission is required for voice journals.')),
      );
      return;
    }
    final directory = await getTemporaryDirectory();
    final path =
        '${directory.path}/journal-${DateTime.now().millisecondsSinceEpoch}.wav';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
    setState(() {
      _recording = true;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= 60) _finishRecording();
    });
  }

  Future<void> _finishRecording() async {
    _timer?.cancel();
    final path = await _recorder.stop();
    if (mounted) setState(() => _recording = false);
    if (path == null || !mounted) return;
    final language = context.read<LanguageProvider>().isUrdu ? 'ur' : 'en';
    final entry = await context.read<MoodProvider>().saveVoiceJournal(
          path: path,
          language: language,
        );
    await File(path).delete().catchError((_) => File(path));
    if (!mounted) return;
    if (entry?.containsDanger == true) {
      context.push(AppRoutes.crisis);
    } else if (entry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                context.read<MoodProvider>().error ?? 'Voice journal failed')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Voice journal transcribed and saved privately.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MoodProvider>();
    return RefreshIndicator(
      onRefresh: () => provider.load(includeJournals: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.successContainer
                  .withValues(alpha: context.isDark ? .12 : .65),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.lock_rounded, color: AppColors.success),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.isUrdu
                        ? 'آپ کے الفاظ خفیہ ہیں۔ سرپرست صرف مجموعی رجحانات دیکھتا ہے، جریدہ کبھی نہیں۔'
                        : 'Your words are encrypted. Guardians see aggregate trends only—never journal content.',
                    style: AppTextStyles.bodySmall,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _journalController,
            minLines: 5,
            maxLines: 10,
            maxLength: 5000,
            textDirection:
                widget.isUrdu ? TextDirection.rtl : TextDirection.ltr,
            decoration: InputDecoration(
              hintText: widget.isUrdu
                  ? 'آج آپ کے دل میں کیا ہے؟'
                  : 'What is on your mind today?',
              alignLabelWithHint: true,
              filled: true,
              fillColor: context.hcSurface,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      provider.isLoading || _recording ? null : _saveText,
                  icon: const Icon(Icons.lock_outline_rounded),
                  label: Text(widget.isUrdu
                      ? 'نجی طور پر محفوظ کریں'
                      : 'Save privately'),
                ),
              ),
              const SizedBox(width: 10),
              Semantics(
                button: true,
                label: _recording
                    ? 'Stop voice recording'
                    : 'Start voice recording',
                child: IconButton.filledTonal(
                  onPressed: provider.isLoading ? null : _toggleRecording,
                  icon:
                      Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                  color: _recording ? AppColors.error : AppColors.primary,
                ),
              ),
            ],
          ),
          if (_recording) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: _seconds / 60),
            const SizedBox(height: 4),
            Text('Recording ${_seconds}s / 60s', textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _searchController,
            onSubmitted: provider.isLoading ? null : provider.searchJournals,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: widget.isUrdu
                  ? 'اپنے جریدے تلاش کریں'
                  : 'Search your private journals',
              suffixIcon: IconButton(
                onPressed: () {
                  _searchController.clear();
                  provider.searchJournals('');
                },
                icon: const Icon(Icons.clear_rounded),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (provider.isLoading && provider.journals.isEmpty)
            const Center(
                child: Padding(
              padding: EdgeInsets.all(28),
              child: CircularProgressIndicator(),
            ))
          else if (provider.journals.isEmpty)
            _EmptyJournal(isUrdu: widget.isUrdu)
          else
            ...provider.journals.map((entry) => _JournalCard(
                  entry: entry,
                  onDelete: entry.isSynced
                      ? () => provider.deleteJournal(entry.id)
                      : null,
                )),
        ],
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  const _JournalCard({required this.entry, required this.onDelete});

  final JournalEntry entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.hcSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.hcOutline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                  entry.entryType == 'voice'
                      ? Icons.mic_rounded
                      : Icons.notes_rounded,
                  size: 18,
                  color: AppColors.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  '${entry.createdAt.toLocal().day}/${entry.createdAt.toLocal().month}/${entry.createdAt.toLocal().year}',
                  style: AppTextStyles.labelSmall,
                ),
              ),
              if (!entry.isSynced)
                const Icon(Icons.cloud_off_rounded,
                    size: 17, color: AppColors.warning),
              if (onDelete != null)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 19),
                ),
            ],
          ),
          if (entry.content != null) ...[
            const SizedBox(height: 6),
            Text(entry.content!, style: AppTextStyles.bodyMedium),
          ],
          if (entry.sentimentLabel != null) ...[
            const SizedBox(height: 10),
            Text(
              'Private reflection: ${entry.sentimentLabel}',
              style: AppTextStyles.labelSmall
                  .copyWith(color: context.hcTextSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal({required this.isUrdu});
  final bool isUrdu;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.menu_book_outlined, size: 48, color: context.hcTextHint),
            const SizedBox(height: 10),
            Text(isUrdu ? 'ابھی کوئی جریدہ نہیں' : 'No journal entries yet'),
          ],
        ),
      );
}

class _OfflineNotice extends StatelessWidget {
  const _OfflineNotice();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.warningContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_off_rounded, color: AppColors.warning),
            SizedBox(width: 8),
            Expanded(
                child: Text(
                    'Stored securely on this device until HerCare reconnects.')),
          ],
        ),
      );
}
