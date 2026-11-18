import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
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
import '../../services/mood_service.dart';
import 'voice_transcript_screen.dart';

class MoodJournalScreen extends StatefulWidget {
  const MoodJournalScreen({
    super.key,
    this.initialTab = 0,
    this.initialMood,
    this.accountId,
  });

  final int initialTab;
  final int? initialMood;
  final String? accountId;

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
      if (!mounted) return;
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
            _JournalTab(isUrdu: isUrdu, accountId: widget.accountId),
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
  int? _mood;
  int? _energy;
  int? _sleep;
  int? _support;
  bool _hydrated = false;
  bool _moodTouched = false;

  static const _emojis = ['😔', '😟', '😐', '🙂', '😊'];

  @override
  void initState() {
    super.initState();
    _mood = widget.initialMood?.clamp(1, 5);
  }

  void _hydrate(MoodCheckin? checkin) {
    if (_hydrated || checkin == null) return;
    _hydrated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        if (!_moodTouched && widget.initialMood == null) {
          _mood = checkin.moodRating;
        }
        _energy = checkin.energyLevel;
        _sleep = checkin.sleepQuality;
        _support = checkin.socialSupport;
      });
    });
  }

  Future<void> _save() async {
    final mood = _mood;
    if (mood == null) return;
    final provider = context.read<MoodProvider>();
    final ok = await provider.saveCheckin(
      moodRating: mood,
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
            onChanged: (value) => setState(() {
              _mood = value;
              _moodTouched = true;
            }),
          ),
          const SizedBox(height: 18),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(widget.isUrdu
                ? 'مزید تفصیلات (اختیاری)'
                : 'More details (optional)'),
            children: [
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
              if (_energy != null || _sleep != null || _support != null)
                TextButton(
                  onPressed: () => setState(() {
                    _energy = null;
                    _sleep = null;
                    _support = null;
                  }),
                  child: Text(widget.isUrdu
                      ? 'اختیاری جوابات صاف کریں'
                      : 'Clear optional answers'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: FilledButton.icon(
              onPressed: provider.isLoading || _mood == null ? null : _save,
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

  final int? value;
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
  final int? value;
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
              Text(value == null ? '—/5' : '$value/5',
                  style: AppTextStyles.labelLarge.copyWith(color: color)),
            ],
          ),
          Slider(
            value: (value ?? 3).toDouble(),
            min: 1,
            max: 5,
            divisions: 4,
            activeColor: color,
            label: value?.toString(),
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
                              heightFactor: entry.moodRating / 5,
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
  const _JournalTab({required this.isUrdu, this.accountId});
  final String? accountId;

  final bool isUrdu;

  @override
  State<_JournalTab> createState() => _JournalTabState();
}

class _JournalTabState extends State<_JournalTab> {
  final _journalController = TextEditingController();
  final _searchController = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerSubscription;
  Timer? _timer;
  int _seconds = 0;
  bool _recording = false;
  bool _stopping = false;
  String? _recordingFilePath;
  String? _pendingVoicePath;
  String? _pendingVoiceRequestId;
  String? _pendingVoiceLanguage;
  String? _playingId;
  String? _loadingAudioId;

  @override
  void initState() {
    super.initState();
    _playerSubscription = _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed && mounted) {
        setState(() => _playingId = null);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _playerSubscription?.cancel();
    _player.dispose();
    if (_stopping) {
      // _finishRecording owns the recorder until stop has completed.
    } else if (_recording) {
      unawaited(_recorder.cancel().whenComplete(_recorder.dispose));
    } else {
      unawaited(_recorder.dispose());
    }
    final pending = _pendingVoicePath;
    if (pending != null) {
      File(pending).delete().catchError((_) => File(pending));
    }
    _journalController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _saveText() async {
    final content = _journalController.text.trim();
    if (content.isEmpty) return;
    final entry = await context.read<MoodProvider>().saveJournal(content);
    if (!mounted) return;
    if (entry == null) {
      _showMessage(context.read<MoodProvider>().error ??
          (widget.isUrdu
              ? 'جریدہ محفوظ نہیں ہو سکا'
              : 'Could not save journal'));
      return;
    }
    _journalController.clear();
    if (entry.containsDanger) {
      context.push(AppRoutes.crisis);
    } else {
      _showMessage(entry.isSynced
          ? (widget.isUrdu ? 'نجی جریدہ محفوظ ہو گیا' : 'Private journal saved')
          : (widget.isUrdu
              ? 'آف لائن اندراج محفوظ ہے'
              : 'Encrypted draft queued offline'));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importTextJournal() async {
    if (_journalController.text.trim().isNotEmpty) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
              widget.isUrdu ? 'موجودہ تحریر بدلیں؟' : 'Replace current draft?'),
          content: Text(widget.isUrdu
              ? 'فائل سے متن لانے سے موجودہ غیر محفوظ تحریر بدل جائے گی۔'
              : 'Importing a file will replace the unsaved text in this box.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(widget.isUrdu ? 'نہیں' : 'Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(widget.isUrdu ? 'بدلیں' : 'Replace')),
          ],
        ),
      );
      if (replace != true || !mounted) return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt', 'md'],
        withData: false,
      );
      if (!mounted || result == null) return;
      final selected = result.files.single;
      if (selected.size > 32 * 1024 || selected.path == null) {
        throw Exception('Choose a text file smaller than 32 KB.');
      }
      final bytes = await File(selected.path!).readAsBytes();
      final imported = utf8
          .decode(bytes, allowMalformed: false)
          .replaceFirst('\uFEFF', '')
          .trim();
      if (imported.isEmpty || imported.length > 5000) {
        throw Exception('Journal text must be 1–5000 characters.');
      }
      _journalController.text = imported;
      _showMessage(widget.isUrdu
          ? 'متن درآمد ہو گیا؛ جائزہ لے کر محفوظ کریں'
          : 'Text imported. Review it, then tap Save privately.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {
        // Picker cache cleanup is not implemented on every platform.
      }
    }
  }

  Future<void> _importVoiceJournal() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['wav', 'm4a', 'mp3'],
        withData: false,
      );
      if (!mounted || result == null) return;
      final selected = result.files.single;
      if (selected.path == null ||
          selected.size < 1 ||
          selected.size > 4 * 1024 * 1024) {
        throw Exception('Choose a WAV, M4A, or MP3 file smaller than 4 MB.');
      }
      final language = context.read<LanguageProvider>().isUrdu ? 'ur' : 'en';
      final extension = selected.extension?.toLowerCase();
      if (!['wav', 'm4a', 'mp3'].contains(extension)) {
        throw Exception('Choose a WAV, M4A, or MP3 voice note.');
      }
      final directory = await getTemporaryDirectory();
      final id = MoodService.requestId();
      final targetDirectory = directory.path;
      final copied = await File(selected.path!)
          .copy('$targetDirectory/journal-import-$id.$extension');
      if (!mounted) {
        await copied.delete();
        return;
      }
      _pendingVoicePath = copied.path;
      _pendingVoiceRequestId = id;
      _pendingVoiceLanguage = language;
      setState(() {});
      await _uploadPendingVoice();
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      try {
        await FilePicker.platform.clearTemporaryFiles();
      } catch (_) {
        // Picker cache cleanup is not implemented on every platform.
      }
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _finishRecording();
      return;
    }
    if (_pendingVoicePath != null) {
      _showMessage(widget.isUrdu
          ? 'پہلے موجودہ صوتی نوٹ دوبارہ محفوظ کریں یا حذف کریں'
          : 'Retry or discard the pending voice note first.');
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _showMessage(widget.isUrdu
            ? 'صوتی نوٹ کے لیے مائیکروفون کی اجازت درکار ہے'
            : 'Microphone permission is required for voice notes.');
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/journal-${DateTime.now().millisecondsSinceEpoch}.wav';
      _recordingFilePath = path;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
      if (!mounted) {
        await _recorder.cancel();
        _recordingFilePath = null;
        return;
      }
      setState(() {
        _recording = true;
        _seconds = 0;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted || _stopping) return;
        setState(() => _seconds++);
        if (_seconds >= 60) _finishRecording();
      });
    } catch (error) {
      final path = _recordingFilePath;
      _recordingFilePath = null;
      if (path != null) {
        await File(path).delete().catchError((_) => File(path));
      }
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _finishRecording() async {
    if (_stopping || !_recording) return;
    _stopping = true;
    _timer?.cancel();
    _timer = null;
    try {
      final path = await _recorder.stop();
      _recordingFilePath = null;
      if (!mounted) {
        if (path != null) {
          await File(path).delete().catchError((_) => File(path));
        }
        return;
      }
      setState(() => _recording = false);
      if (path == null) {
        throw Exception('Recording did not produce a voice note.');
      }
      _pendingVoicePath = path;
      _pendingVoiceRequestId = MoodService.requestId();
      await _uploadPendingVoice();
    } catch (error) {
      final path = _recordingFilePath;
      _recordingFilePath = null;
      if (path != null) {
        await File(path).delete().catchError((_) => File(path));
      }
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      _stopping = false;
      if (!mounted) unawaited(_recorder.dispose());
    }
  }

  Future<void> _uploadPendingVoice() async {
    final path = _pendingVoicePath;
    if (path == null) return;
    final language = _pendingVoiceLanguage ??
        (context.read<LanguageProvider>().isUrdu ? 'ur' : 'en');
    final entry = await context.read<MoodProvider>().saveVoiceJournal(
          path: path,
          language: language,
          clientRequestId: _pendingVoiceRequestId,
        );
    if (!mounted) return;
    if (entry == null) {
      _showMessage(context.read<MoodProvider>().error ??
          (widget.isUrdu
              ? 'صوتی نوٹ محفوظ نہیں ہو سکا؛ دوبارہ کوشش کریں'
              : 'Voice note was not saved. Please retry.'));
      setState(() {});
      return;
    }
    _pendingVoicePath = null;
    _pendingVoiceRequestId = null;
    await File(path).delete().catchError((_) => File(path));
    if (!mounted) return;
    setState(() {});
    _showMessage(widget.isUrdu
        ? 'نجی صوتی نوٹ محفوظ ہو گیا'
        : 'Private voice note saved.');
  }

  Future<void> _discardPendingVoice() async {
    final path = _pendingVoicePath;
    if (path == null) return;
    _pendingVoicePath = null;
    _pendingVoiceRequestId = null;
    await File(path).delete().catchError((_) => File(path));
    if (mounted) setState(() {});
  }

  Future<void> _playVoice(JournalEntry entry) async {
    if (_playingId == entry.id && _player.playing) {
      await _player.pause();
      if (mounted) setState(() => _playingId = null);
      return;
    }
    setState(() => _loadingAudioId = entry.id);
    try {
      final bytes = await context.read<MoodProvider>().loadVoiceAudio(entry.id);
      if (!mounted) return;
      await _player.stop();
      await _player.setAudioSource(_PrivateVoiceSource(
        bytes,
        entry.voiceContentType ?? 'audio/wav',
      ));
      if (!mounted) return;
      setState(() => _playingId = entry.id);
      unawaited(_player.play().catchError((Object error) {
        if (!mounted) return;
        setState(() => _playingId = null);
        _showMessage(error.toString().replaceFirst('Exception: ', ''));
      }));
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loadingAudioId = null);
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
                    ? (widget.isUrdu
                        ? 'ریکارڈنگ بند کریں'
                        : 'Stop voice recording')
                    : (widget.isUrdu
                        ? 'صوتی ریکارڈنگ شروع کریں'
                        : 'Start voice recording'),
                child: IconButton.filledTonal(
                  onPressed:
                      provider.isLoading || _stopping ? null : _toggleRecording,
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
            Text(
                widget.isUrdu
                    ? 'ریکارڈنگ $_seconds سیکنڈ / 60 سیکنڈ'
                    : 'Recording ${_seconds}s / 60s',
                textAlign: TextAlign.center),
          ],
          if (_pendingVoicePath != null && !_recording) ...[
            const SizedBox(height: 10),
            Text(
                widget.isUrdu
                    ? 'صوتی نوٹ ابھی اپ لوڈ نہیں ہوا۔ اس صفحے کو چھوڑنے سے پہلے دوبارہ کوشش کریں۔'
                    : 'Voice note not uploaded. Retry before leaving this page.',
                style: AppTextStyles.bodySmall),
            Wrap(spacing: 8, children: [
              TextButton.icon(
                onPressed: provider.isLoading ? null : _uploadPendingVoice,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(widget.isUrdu ? 'دوبارہ کوشش' : 'Retry upload'),
              ),
              TextButton(
                onPressed: provider.isLoading ? null : _discardPendingVoice,
                child: Text(widget.isUrdu ? 'حذف کریں' : 'Discard'),
              ),
            ]),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              TextButton.icon(
                onPressed: provider.isLoading || _recording
                    ? null
                    : _importTextJournal,
                icon: const Icon(Icons.upload_file_rounded),
                label: Text(widget.isUrdu
                    ? 'تحریری فائل لائیں'
                    : 'Import text journal'),
              ),
              TextButton.icon(
                onPressed: provider.isLoading ||
                        _recording ||
                        _pendingVoicePath != null
                    ? null
                    : _importVoiceJournal,
                icon: const Icon(Icons.audio_file_rounded),
                label: Text(
                    widget.isUrdu ? 'صوتی فائل لائیں' : 'Import voice note'),
              ),
            ],
          ),
          Text(
            widget.isUrdu
                ? 'تحریر: TXT/MD، ۵۰۰۰ حروف۔ آڈیو: WAV/M4A/MP3، 4 MB۔ اختیاری انگریزی/اردو نقل کے لیے ۶۰ سیکنڈ کی آڈیو؛ تجزیے سے پہلے الفاظ کی تصدیق کریں۔ فوری خطرے میں فوری مدد لیں۔'
                : 'Text: TXT/MD, up to 5000 characters. Audio: WAV/M4A/MP3, up to 4 MB. Optional English/Urdu transcripts support clips up to 60 seconds. Review your words before analysis; use Immediate Help for urgent danger.',
            style: AppTextStyles.bodySmall
                .copyWith(color: context.hcTextSecondary),
          ),
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
                  isUrdu: widget.isUrdu,
                  isPlaying: _playingId == entry.id,
                  isLoadingAudio: _loadingAudioId == entry.id,
                  onPlay: entry.hasAudio ? () => _playVoice(entry) : null,
                  onTranscribe: entry.hasAudio && entry.content == null
                      ? () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => VoiceTranscriptScreen(
                              journalId: entry.id,
                              accountId: widget.accountId,
                              onPlay: () => _playVoice(entry))))
                      : null,
                  onDelete: entry.isSynced
                      ? () async {
                          if (_playingId == entry.id) {
                            await _player.stop();
                            if (mounted) setState(() => _playingId = null);
                          }
                          await provider.deleteJournal(entry.id);
                        }
                      : null,
                )),
        ],
      ),
    );
  }
}

class _JournalCard extends StatelessWidget {
  const _JournalCard(
      {required this.entry,
      required this.onDelete,
      required this.isUrdu,
      required this.isPlaying,
      required this.isLoadingAudio,
      this.onTranscribe,
      required this.onPlay});

  final JournalEntry entry;
  final VoidCallback? onDelete;
  final bool isUrdu;
  final bool isPlaying;
  final bool isLoadingAudio;
  final VoidCallback? onPlay;
  final VoidCallback? onTranscribe;

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
          if (entry.entryType == 'voice') ...[
            const SizedBox(height: 6),
            Text(
                isUrdu
                    ? (entry.content == null
                        ? 'نجی صوتی نوٹ — اختیاری نقل دستیاب'
                        : 'نجی صوتی نوٹ — تصدیق شدہ نقل')
                    : entry.content == null
                        ? 'Private voice note — optional transcript available'
                        : 'Private voice note — confirmed transcript',
                style: AppTextStyles.bodySmall),
            if (onPlay != null)
              TextButton.icon(
                onPressed: isLoadingAudio ? null : onPlay,
                icon: isLoadingAudio
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded),
                label: Text(isUrdu
                    ? (isPlaying ? 'روکیں' : 'سنیں')
                    : (isPlaying ? 'Pause' : 'Play voice note')),
              ),
            if (onTranscribe != null)
              TextButton.icon(
                  onPressed: onTranscribe,
                  icon: const Icon(Icons.record_voice_over_outlined),
                  label: Text(isUrdu
                      ? 'صوتی نقل بنائیں / دیکھیں'
                      : 'Transcribe / review')),
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

// Pinned just_audio version; this source keeps decrypted audio in memory.
// ignore: experimental_member_use
class _PrivateVoiceSource extends StreamAudioSource {
  _PrivateVoiceSource(this.bytes, this.mimeType);

  final Uint8List bytes;
  final String mimeType;

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    final from = (start ?? 0).clamp(0, bytes.length);
    final to = (end ?? bytes.length).clamp(from, bytes.length);
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: bytes.length,
      contentLength: to - from,
      offset: from,
      stream: Stream.value(bytes.sublist(from, to)),
      contentType: mimeType,
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
