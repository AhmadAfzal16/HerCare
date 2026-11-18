import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/sleep_models.dart';
import '../../providers/auth_provider.dart';
import '../../providers/language_provider.dart';
import '../../services/digital_wellbeing_service.dart';
import '../../core/theme/theme_ext.dart';
import 'sleep_cache.dart';
import 'sleep_account_guard.dart';
import 'sleep_insights_panel.dart';

String durationLabel(num minutes) =>
    '${minutes ~/ 60}h ${minutes.toInt() % 60}m';

class DigitalWellbeingScreen extends StatefulWidget {
  const DigitalWellbeingScreen(
      {super.key, this.service, this.accountId, this.cache});
  final DigitalWellbeingService? service;
  final String? accountId;
  final SleepCache? cache;
  @override
  State<DigitalWellbeingScreen> createState() => _DigitalWellbeingScreenState();
}

class _DigitalWellbeingScreenState extends State<DigitalWellbeingScreen>
    with WidgetsBindingObserver {
  late DigitalWellbeingService _service;
  late SleepCache _cache;
  Map<String, dynamic>? _usage;
  SleepDashboard? _sleep;
  String? _usageError, _sleepError;
  bool _loading = false;
  bool _denied = false;
  DateTime? _cachedAt;
  int _generation = 0;
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String urdu) => ur ? urdu : en;

  @override
  void initState() {
    super.initState();
    _configure();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  void _configure() {
    _service = widget.service ??
        DigitalWellbeingService(expectedAccountId: widget.accountId);
    _cache = widget.cache ?? SleepCache(apiOrigin: _service.apiOrigin);
  }

  @override
  void didUpdateWidget(covariant DigitalWellbeingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.service != widget.service) {
      _generation++;
      _sleep = null;
      _usage = null;
      _cachedAt = null;
      _denied = false;
      _loading = false;
      _configure();
      _refresh();
    }
  }

  bool _same(int generation) {
    if (!mounted || generation != _generation) return false;
    final auth = context.read<AuthProvider?>();
    return widget.accountId == null ||
        auth == null ||
        (auth.user?.id == widget.accountId && auth.user?.isMother == true);
  }

  Future<void> _deny(int generation, {String? owner, SleepCache? cache}) async {
    owner ??= widget.accountId;
    cache ??= _cache;
    if (owner != null) {
      try {
        await cache.clear(owner);
      } catch (_) {}
    }
    if (_same(generation)) {
      setState(() {
        _sleep = null;
        _usage = null;
        _cachedAt = null;
        _denied = true;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    final generation = _generation;
    final service = _service;
    final cache = _cache;
    final owner = widget.accountId;
    if (!_same(generation)) return;
    setState(() {
      _loading = true;
      _usageError = null;
      _sleepError = null;
      _usage = null;
    });
    await Future.wait([
      () async {
        try {
          final value = await service.usage();
          if (_same(generation)) setState(() => _usage = value);
        } catch (_) {
          if (_same(generation)) {
            setState(() => _usageError = tr(
                'Phone usage could not be read. Retry or check usage access.',
                'فون کا استعمال نہیں پڑھ سکے۔ رسائی چیک کریں۔'));
          }
        }
      }(),
      () async {
        try {
          final value = SleepDashboard.fromJson(await service.sleep());
          if (!_same(generation)) return;
          setState(() {
            _sleep = value;
            _cachedAt = null;
            _denied = false;
          });
          if (owner != null) {
            try {
              await cache.save(owner, value);
            } catch (_) {}
            if (!_same(generation)) {
              try {
                await cache.clear(owner);
              } catch (_) {}
            }
          }
        } on SleepAccessException {
          await _deny(generation, owner: owner, cache: cache);
        } on SleepAccountException {
          await _deny(generation, owner: owner, cache: cache);
        } on FormatException {
          if (_same(generation)) {
            setState(() {
              _sleep = null;
              _cachedAt = null;
              _sleepError = tr(
                  'Sleep response could not be read. Retry; no scores were invented.',
                  'نیند کا جواب نہیں پڑھ سکے۔ دوبارہ کوشش کریں؛ کوئی اعداد خود نہیں بنائے گئے۔');
            });
          }
        } catch (_) {
          CachedSleep? saved;
          if (owner != null) {
            try {
              saved = await cache.read(owner);
            } catch (_) {}
          }
          if (_same(generation)) {
            final snapshot = saved;
            if (snapshot != null) {
              setState(() {
                _sleep = snapshot.dashboard;
                _cachedAt = snapshot.savedAt;
              });
            } else {
              setState(() {
                _sleep = null;
                _cachedAt = null;
              });
            }
            setState(() => _sleepError = tr(
                saved == null
                    ? 'Sleep records could not be loaded. Check your connection and retry.'
                    : 'Offline: showing an encrypted saved copy, not live records or a current safety assessment.',
                saved == null
                    ? 'نیند کا ریکارڈ لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔'
                    : 'آف لائن: خفیہ محفوظ نقل، موجودہ ریکارڈ یا حفاظت کا جائزہ نہیں۔'));
          }
        }
      }(),
    ]);
    if (_same(generation)) setState(() => _loading = false);
  }

  Future<void> _permission() async {
    final generation = _generation;
    final urdu = ur;
    final owner = widget.accountId;
    String text(String en, String ur) => urdu ? ur : en;
    final allowed = await showDialog<bool>(
        context: context,
        builder: (dialog) => SleepAccountGuard(
            accountId: owner,
            child: AlertDialog(
              title: Text(text(
                  'Allow phone usage access?', 'فون کے استعمال کی رسائی؟')),
              content: SingleChildScrollView(
                  child: Text(text(
                      'Android will open Usage access settings. Select HerCare and enable Allow usage access. HerCare reads app usage times and screen on/off events on this phone. App names stay on your phone; notification contents are not needed. Screen-off intervals are only sleep suggestions, not measured sleep. You can revoke access in the same settings at any time.',
                      'اینڈرائیڈ کی سیٹنگ میں HerCare منتخب کر کے استعمال کی رسائی دیں۔ ایپ کے نام فون پر رہتے ہیں۔ اطلاعات کا متن نہیں پڑھا جاتا۔ اسکرین بند ہونے کا وقت نیند کا صرف اندازہ ہے۔ آپ رسائی کبھی بھی واپس لے سکتے ہیں۔'))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: Text(text('Cancel', 'منسوخ'))),
                FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: Text(text('Open settings', 'سیٹنگ کھولیں')))
              ],
            )));
    if (allowed != true || !_same(generation)) return;
    try {
      await _service.openAccess();
    } catch (_) {
      if (mounted && _same(generation)) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(
                'Open Android Settings → Special app access → Usage access → HerCare.',
                'اینڈرائیڈ سیٹنگ میں HerCare کی استعمال کی رسائی کھولیں۔'))));
      }
    }
  }

  Future<void> _edit({bool estimate = false, SleepRecord? record}) async {
    final generation = _generation;
    if (!_same(generation)) return;
    final owner = widget.accountId;
    final service = _service;
    final cache = _cache;
    final urdu = ur;
    final estimatedBed = estimate
        ? DateTime.fromMillisecondsSinceEpoch(
            (_usage!['estimated_bedtime'] as num).toInt())
        : null;
    final estimatedWake = estimate
        ? DateTime.fromMillisecondsSinceEpoch(
            (_usage!['estimated_wake'] as num).toInt())
        : null;
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => SleepAccountGuard(
            accountId: owner,
            child: _SleepEditor(
              service: service,
              isUrdu: urdu,
              accountId: owner,
              record: record,
              onDenied: () => _deny(generation, owner: owner, cache: cache),
              bedtime: estimatedBed,
              wake: estimatedWake,
            ))));
    if (result == true && _same(generation)) await _refresh();
  }

  Widget _card(String title, List<Widget> children) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children
          ])));

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final records = _sleep?.records ?? <SleepRecord>[];
    final usage = _usage;
    final apps = usage?['apps'] as List? ?? [];
    if (_denied) {
      return Scaffold(
          appBar: AppBar(title: Text(tr('Sleep', 'نیند'))),
          body: Center(
              child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(tr(
                      'Private sleep access is unavailable. Reopen the screen after checking your account and consent.',
                      'نجی نیند کی رسائی دستیاب نہیں۔ اکاؤنٹ اور رضامندی چیک کرکے اسکرین دوبارہ کھولیں۔')))));
    }
    return SleepAccountGuard(
        accountId: widget.accountId,
        child: Scaffold(
          backgroundColor: context.hcBg,
          appBar: AppBar(
              title:
                  Text(tr('Sleep & phone usage', 'نیند اور فون کا استعمال'))),
          body: RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loading) const LinearProgressIndicator(),
                  _card(tr('Phone usage today', 'آج فون کا استعمال'), [
                    Text(tr(
                        'Read from Android usage access, not a direct connection to the Digital Wellbeing app. Updates when you open or refresh this screen.',
                        'اینڈرائیڈ سے استعمال کا ڈیٹا۔ اسکرین کھولنے یا تازہ کرنے پر اپ ڈیٹ ہوتا ہے۔')),
                    const SizedBox(height: 12),
                    if (_usageError != null) Text(_usageError!),
                    if (usage?['supported'] == false)
                      Text(tr(
                          'Automatic phone usage is available on Android only.',
                          'خودکار فون استعمال صرف اینڈرائیڈ پر دستیاب ہے۔'))
                    else ...[
                      if (usage?['permission'] == true &&
                          usage?['available'] == true) ...[
                        Text(
                            '${tr('App screen time', 'ایپس کا وقت')}: ${durationLabel(usage!['screen_minutes'] as num)}'),
                        Text(
                            '${tr('Social apps', 'سوشل ایپس')}: ${durationLabel(usage['social_minutes'] as num)}'),
                        Text(
                            '${tr('Late-night use (12–5 am)', 'رات کا استعمال (۱۲ تا ۵)')}: ${durationLabel(usage['late_night_minutes'] as num)}'),
                        if ((usage['social_minutes'] as num) >= 300)
                          Text(tr(
                              'You have used social apps for 5+ hours today. Consider a screen break.',
                              'آج سوشل ایپس پر پانچ گھنٹے سے زیادہ استعمال۔ وقفہ لیں۔')),
                        if ((usage['late_night_minutes'] as num) >= 30)
                          Text(tr(
                              'A late-night wind-down or a short screen break may help. Usage is not a distress diagnosis.',
                              'رات میں آرام یا اسکرین کا مختصر وقفہ مفید ہو سکتا ہے۔ استعمال پریشانی کی تشخیص نہیں۔')),
                        const Divider(),
                        if (apps.isEmpty)
                          Text(tr('No recorded app activity yet.',
                              'ابھی کوئی استعمال درج نہیں۔')),
                        for (final app in apps)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(children: [
                                Expanded(child: Text(app['name'] as String)),
                                const SizedBox(width: 12),
                                Text(durationLabel(app['minutes'] as num)),
                              ])),
                      ] else if (usage?['permission'] == true)
                        Text(tr(
                            'Usage data is unavailable. Unlock the phone and retry.',
                            'فون کھول کر دوبارہ کوشش کریں۔')),
                      TextButton(
                          onPressed: _permission,
                          child: Text(tr(
                              usage?['permission'] == true
                                  ? 'Manage usage access'
                                  : 'Connect phone usage',
                              'فون کی رسائی کی سیٹنگ'))),
                    ],
                  ]),
                  if (usage?['estimated_bedtime'] != null &&
                      usage?['estimated_wake'] != null)
                    _card(
                        tr('Possible overnight rest', 'رات کے آرام کا اندازہ'),
                        [
                          Text(tr(
                              'The longest completed screen-off interval last night. It may include time awake and is not a sleep measurement.',
                              'گزشتہ رات اسکرین بند رہنے کا طویل وقفہ۔ یہ حقیقی نیند کی پیمائش نہیں۔')),
                          TextButton(
                              onPressed: () => _edit(estimate: true),
                              child: Text(tr('Review and correct times',
                                  'اوقات دیکھیں اور درست کریں'))),
                        ]),
                  _card(tr('Your saved sleep', 'آپ کی محفوظ نیند'), [
                    if (_sleepError != null) Text(_sleepError!),
                    if (_cachedAt != null)
                      Text(
                          '${tr('Saved copy from', 'محفوظ نقل کی تاریخ')}: ${_cachedAt!.toLocal()}'),
                    if (_sleep?.average != null)
                      Text(
                          '${tr('Average of recorded nights in 7 days', '۷ دن کی درج راتوں کی اوسط')}: ${durationLabel(_sleep!.average!)}'),
                    Text(tr(
                        'Your estimate, not measured sleep. Entered awake minutes are subtracted; quality and awakenings are optional. One main period per wake-up date.',
                        'آپ کا اندازہ، نیند کی پیمائش نہیں۔ درج جاگنے کے منٹ منہا ہوں گے؛ معیار اور بیداری اختیاری ہیں۔ ہر تاریخ کا ایک مرکزی دورانیہ۔')),
                    if (records.isEmpty && _sleepError == null && !_loading)
                      Text(tr('No sleep recorded yet.', 'ابھی نیند درج نہیں۔')),
                    FilledButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.bedtime_outlined),
                        label: Text(tr(
                            'Log / correct sleep', 'نیند درج یا درست کریں'))),
                    ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(tr('Saved nights', 'محفوظ راتیں')),
                        children: [
                          for (final record in records)
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 10),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          '${record.date} · ${durationLabel(record.minutes)}'),
                                      Text(
                                          '${tr('Bedtime', 'سونے کا وقت')}: ${_time(record.bedtime, record.timezoneOffset)}'),
                                      Text(
                                          '${tr('Wake time', 'جاگنے کا وقت')}: ${_time(record.wake, record.timezoneOffset)}'),
                                      Text(
                                          '${tr('Quality', 'معیار')}: ${record.quality == null ? '—' : '${record.quality}/5'} · ${tr('Awakenings', 'بیداری')}: ${record.awakenings ?? '—'}'),
                                      TextButton(
                                          onPressed: () =>
                                              _edit(record: record),
                                          child: Text(tr('Correct this night',
                                              'اس رات کی درستگی کریں'))),
                                    ])),
                        ]),
                  ]),
                  if (_sleep?.insights != null)
                    SleepInsightsPanel(
                        insights: _sleep!.insights!, cached: _cachedAt != null),
                  OutlinedButton(
                      onPressed: _loading ? null : _refresh,
                      child: Text(tr('Refresh', 'تازہ کریں'))),
                ],
              )),
        ));
  }

  String _time(DateTime value, int offset) {
    final date = value.toUtc().subtract(Duration(minutes: offset));
    return '${MaterialLocalizations.of(context).formatShortDate(date)} ${TimeOfDay.fromDateTime(date).format(context)}';
  }
}

class _SleepEditor extends StatefulWidget {
  const _SleepEditor(
      {required this.service,
      required this.isUrdu,
      this.bedtime,
      this.wake,
      this.accountId,
      this.record,
      required this.onDenied});
  final DigitalWellbeingService service;
  final bool isUrdu;
  final DateTime? bedtime, wake;
  final String? accountId;
  final SleepRecord? record;
  final Future<void> Function() onDenied;
  @override
  State<_SleepEditor> createState() => _SleepEditorState();
}

class _SleepEditorState extends State<_SleepEditor> {
  DateTime? _bed, _wake;
  int? _quality;
  int _awakeMinutes = 0;
  int? _awakenings;
  bool _saving = false;
  bool _denied = false;
  bool _bedChanged = false, _wakeChanged = false;
  String? _error;
  String tr(String en, String ur) =>
      (context.read<LanguageProvider?>()?.isUrdu ?? widget.isUrdu) ? ur : en;
  bool get _same {
    if (!mounted) return false;
    final auth = context.read<AuthProvider?>();
    return widget.accountId == null ||
        auth == null ||
        (auth.user?.id == widget.accountId && auth.user?.isMother == true);
  }

  DateTime _wall(DateTime instant, int offset) {
    final date = instant.toUtc().subtract(Duration(minutes: offset));
    return DateTime(date.year, date.month, date.day, date.hour, date.minute);
  }

  DateTime _actual(DateTime wall, bool bed) {
    final record = widget.record;
    if (record == null) return wall.toUtc();
    if (bed ? !_bedChanged : !_wakeChanged) {
      return bed ? record.bedtime : record.wake;
    }
    return DateTime.utc(wall.year, wall.month, wall.day, wall.hour, wall.minute)
        .add(Duration(minutes: record.timezoneOffset));
  }

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _bed = record == null
        ? widget.bedtime
        : _wall(record.bedtime, record.timezoneOffset);
    _wake = record == null
        ? widget.wake
        : _wall(record.wake, record.timezoneOffset);
    _quality = record?.quality;
    _awakeMinutes = record?.awakeMinutes ?? 0;
    _awakenings = record?.awakenings;
  }

  Future<void> _pick(bool bedtime) async {
    final now = DateTime.now();
    final selected = bedtime ? _bed : _wake;
    final day = await showDatePicker(
        context: context,
        initialDate: selected ?? now,
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now,
        builder: (_, child) =>
            SleepAccountGuard(accountId: widget.accountId, child: child!));
    if (!mounted || day == null || !_same) return;
    final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(selected ?? now),
        builder: (_, child) =>
            SleepAccountGuard(accountId: widget.accountId, child: child!));
    if (time == null || !_same) return;
    final date = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    setState(() {
      if (bedtime) {
        _bed = date;
        _bedChanged = true;
      } else {
        _wake = date;
        _wakeChanged = true;
      }
    });
  }

  Future<void> _save() async {
    if (!_same || _saving || _denied) return;
    final bed = _bed == null ? null : _actual(_bed!, true);
    final wake = _wake == null ? null : _actual(_wake!, false);
    final duration =
        bed == null || wake == null ? 0 : wake.difference(bed).inMinutes;
    if (duration <= 0 ||
        duration > 1440 ||
        wake!.isAfter(DateTime.now()) ||
        _awakeMinutes >= duration) {
      setState(() => _error = tr(
          'Choose past bedtime and wake time (within 24 hours), and valid awake minutes / awakenings.',
          'درست گزشتہ اوقات، جاگنے کے منٹ اور بیداری کی تعداد منتخب کریں۔'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.saveSleep(
          bedtime: bed!,
          wake: wake,
          awakeMinutes: _awakeMinutes,
          quality: _quality,
          awakenings: _awakenings,
          timezoneOffsetMinutes: widget.record?.timezoneOffset ??
              -_wake!.timeZoneOffset.inMinutes);
      if (mounted && _same) Navigator.pop(context, true);
    } on SleepAccessException {
      await widget.onDenied();
      if (_same) {
        setState(() {
          _denied = true;
          _bed = null;
          _wake = null;
        });
      }
    } on SleepAccountException {
      await widget.onDenied();
      if (_same) {
        setState(() {
          _denied = true;
          _bed = null;
          _wake = null;
        });
      }
    } catch (_) {
      if (_same) {
        setState(() => _error = tr(
            'Not saved. Check your connection and retry. Your inputs are still here.',
            'محفوظ نہیں ہوا۔ کنکشن چیک کریں۔ اندراج یہاں موجود ہے۔'));
      }
    } finally {
      if (_same) setState(() => _saving = false);
    }
  }

  Widget _section(
      {required String title, required IconData icon, required Widget child}) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icon, size: 20, color: colors.primary),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(title, style: Theme.of(context).textTheme.titleSmall)),
        ]),
        const SizedBox(height: 14),
        child,
      ]),
    );
  }

  Widget _timeTile(bool bedtime) {
    final value = bedtime ? _bed : _wake;
    final label = bedtime
        ? tr('Bedtime', 'سونے کا وقت')
        : tr('Wake time', 'جاگنے کا وقت');
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading:
            Icon(bedtime ? Icons.bedtime_outlined : Icons.wb_sunny_outlined),
        title: Text(label),
        subtitle: Text(value == null
            ? tr('Tap to choose', 'منتخب کرنے کے لیے دبائیں')
            : '${MaterialLocalizations.of(context).formatMediumDate(value)} · ${TimeOfDay.fromDateTime(value).format(context)}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: _saving ? null : () => _pick(bedtime),
      ),
    );
  }

  Widget _stepper(
      {required String label,
      required String hint,
      required int? value,
      required int step,
      required int maximum,
      required ValueChanged<int> onChanged}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(hint, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        IconButton.filledTonal(
          tooltip: tr('Decrease', 'کم کریں'),
          onPressed: _saving || value == null || value <= 0
              ? null
              : () => onChanged((value - step).clamp(0, maximum)),
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
            width: 80,
            child: Text(value?.toString() ?? '—',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium)),
        IconButton.filledTonal(
          tooltip: tr('Increase', 'بڑھائیں'),
          onPressed: _saving || (value != null && value >= maximum)
              ? null
              : () => onChanged(((value ?? 0) + step).clamp(0, maximum)),
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider?>();
    if (_denied) {
      return Scaffold(
          appBar: AppBar(title: Text(tr('Sleep', 'نیند'))),
          body: Center(
              child: Text(tr('Access is unavailable. Reopen sleep.',
                  'رسائی دستیاب نہیں۔ نیند کی اسکرین دوبارہ کھولیں۔'))));
    }
    return Scaffold(
      appBar: AppBar(title: Text(tr('Record sleep', 'نیند درج کریں'))),
      body: SafeArea(
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: .45),
                borderRadius: BorderRadius.circular(16),
              ),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(tr(
                  'Choose bedtime and wake time. Other details are optional. Phone inactivity is only a suggestion.',
                  'سونے اور جاگنے کے اوقات چنیں۔ باقی تفصیل اختیاری ہے۔ فون بند ہونا صرف اندازہ ہے۔',
                ))),
              ]),
            ),
            const SizedBox(height: 16),
            _section(
              title: tr('Sleep window', 'نیند کا دورانیہ'),
              icon: Icons.schedule_rounded,
              child: Column(children: [
                _timeTile(true),
                const SizedBox(height: 8),
                _timeTile(false),
                if (_bed != null && _wake != null && _wake!.isAfter(_bed!)) ...[
                  const SizedBox(height: 10),
                  Text(
                      '${tr('Time in bed', 'بستر میں وقت')}: ${durationLabel(_wake!.difference(_bed!).inMinutes)}'),
                ],
              ]),
            ),
            const SizedBox(height: 14),
            ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title:
                    Text(tr('Optional sleep details', 'نیند کی اختیاری تفصیل')),
                initiallyExpanded: widget.record != null,
                children: [
                  _section(
                    title: tr('During the night', 'رات کے دوران'),
                    icon: Icons.dark_mode_outlined,
                    child: Column(children: [
                      _stepper(
                        label: tr('Minutes awake', 'جاگنے کے منٹ'),
                        hint: tr('0 means no awake time is subtracted',
                            '۰ کا مطلب جاگنے کا وقت منہا نہیں ہوگا'),
                        value: _awakeMinutes,
                        step: 5,
                        maximum: 1435,
                        onChanged: (value) =>
                            setState(() => _awakeMinutes = value),
                      ),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() => _awakenings = 0),
                            child:
                                Text(tr('No awakenings', 'کوئی بیداری نہیں'))),
                        TextButton(
                            onPressed: _saving
                                ? null
                                : () => setState(() => _awakenings = null),
                            child: Text(tr('Not recorded', 'درج نہیں')))
                      ]),
                      const Divider(height: 24),
                      _stepper(
                        label: tr('Awakenings', 'بیداری'),
                        hint: tr('Times you woke up', 'کتنی بار جاگیں'),
                        value: _awakenings,
                        step: 1,
                        maximum: 20,
                        onChanged: (value) =>
                            setState(() => _awakenings = value),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  _section(
                    title: tr('How was your sleep?', 'آپ کی نیند کیسی تھی؟'),
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      ChoiceChip(
                          label: Text(tr('Not recorded', 'درج نہیں')),
                          selected: _quality == null,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() => _quality = null)),
                      for (final value in [1, 2, 3, 4, 5])
                        ChoiceChip(
                            label: Text('$value / 5'),
                            selected: _quality == value,
                            onSelected: _saving
                                ? null
                                : (_) => setState(() => _quality = value)),
                      Text(tr(
                          '1 = poor, 5 = good. Leaving it blank means unknown, not average quality.',
                          '۱ = کم، ۵ = اچھا۔ خالی کا مطلب معلوم نہیں، اوسط معیار نہیں۔')),
                    ]),
                  ),
                ]),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Text(tr(_saving ? 'Saving…' : 'Save sleep',
                _saving ? 'محفوظ ہو رہا ہے' : 'نیند محفوظ کریں')),
          ),
        ),
      ),
    );
  }
}
