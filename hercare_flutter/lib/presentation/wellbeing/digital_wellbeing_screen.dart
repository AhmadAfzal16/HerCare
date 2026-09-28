import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../services/digital_wellbeing_service.dart';
import '../../core/theme/theme_ext.dart';

String durationLabel(num minutes) =>
    '${minutes ~/ 60}h ${minutes.toInt() % 60}m';

class DigitalWellbeingScreen extends StatefulWidget {
  const DigitalWellbeingScreen({super.key, this.service});
  final DigitalWellbeingService? service;
  @override
  State<DigitalWellbeingScreen> createState() => _DigitalWellbeingScreenState();
}

class _DigitalWellbeingScreenState extends State<DigitalWellbeingScreen>
    with WidgetsBindingObserver {
  late final DigitalWellbeingService _service =
      widget.service ?? DigitalWellbeingService();
  Map<String, dynamic>? _usage;
  Map<String, dynamic>? _sleep;
  String? _usageError, _sleepError;
  bool _loading = false;
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String urdu) => ur ? urdu : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
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
    setState(() {
      _loading = true;
      _usageError = null;
      _sleepError = null;
      _usage = null;
    });
    await Future.wait([
      () async {
        try {
          final value = await _service.usage();
          if (mounted) setState(() => _usage = value);
        } catch (_) {
          if (mounted) {
            setState(() => _usageError = tr(
                'Phone usage could not be read. Retry or check usage access.',
                'فون کا استعمال نہیں پڑھ سکے۔ رسائی چیک کریں۔'));
          }
        }
      }(),
      () async {
        try {
          final value = await _service.sleep();
          if (mounted) setState(() => _sleep = value);
        } catch (_) {
          if (mounted) {
            setState(() => _sleepError = tr(
                'Sleep records could not be loaded. Check your connection and retry.',
                'نیند کا ریکارڈ لوڈ نہیں ہو سکا۔ دوبارہ کوشش کریں۔'));
          }
        }
      }(),
    ]);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _permission() async {
    final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(
                  tr('Allow phone usage access?', 'فون کے استعمال کی رسائی؟')),
              content: SingleChildScrollView(
                  child: Text(tr(
                      'Android will open Usage access settings. Select HerCare and enable Allow usage access. HerCare reads app usage times and screen on/off events on this phone. App names stay on your phone; notification contents are not needed. Screen-off intervals are only sleep suggestions, not measured sleep. You can revoke access in the same settings at any time.',
                      'اینڈرائیڈ کی سیٹنگ میں HerCare منتخب کر کے استعمال کی رسائی دیں۔ ایپ کے نام فون پر رہتے ہیں۔ اطلاعات کا متن نہیں پڑھا جاتا۔ اسکرین بند ہونے کا وقت نیند کا صرف اندازہ ہے۔ آپ رسائی کبھی بھی واپس لے سکتے ہیں۔'))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(tr('Cancel', 'منسوخ'))),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(tr('Open settings', 'سیٹنگ کھولیں')))
              ],
            ));
    if (allowed != true || !mounted) return;
    try {
      await _service.openAccess();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(tr(
                'Open Android Settings → Special app access → Usage access → HerCare.',
                'اینڈرائیڈ سیٹنگ میں HerCare کی استعمال کی رسائی کھولیں۔'))));
      }
    }
  }

  Future<void> _edit({bool estimate = false}) async {
    final result = await Navigator.of(context).push<bool>(MaterialPageRoute(
        builder: (_) => _SleepEditor(
              service: _service,
              isUrdu: ur,
              bedtime: estimate
                  ? DateTime.fromMillisecondsSinceEpoch(
                      (_usage!['estimated_bedtime'] as num).toInt())
                  : null,
              wake: estimate
                  ? DateTime.fromMillisecondsSinceEpoch(
                      (_usage!['estimated_wake'] as num).toInt())
                  : null,
            )));
    if (result == true && mounted) await _refresh();
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
    final records = (_sleep?['records'] as List?) ?? [];
    final summary = _sleep?['summary'] as Map?;
    final usage = _usage;
    final apps = usage?['apps'] as List? ?? [];
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(
          title: Text(tr('Sleep & phone usage', 'نیند اور فون کا استعمال'))),
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
                  Text(tr('Automatic phone usage is available on Android only.',
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
                _card(tr('Possible overnight rest', 'رات کے آرام کا اندازہ'), [
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
                if (summary?['average_minutes'] != null)
                  Text(
                      '${tr('Average of last recorded nights', 'درج راتوں کی اوسط')}: ${durationLabel(summary!['average_minutes'] as num)}'),
                Text(tr(
                    'Self-reported sleep; time awake is subtracted. One main sleep record per wake-up date. New saves replace that date’s record.',
                    'آپ کی درج کردہ نیند؛ جاگنے کا وقت منہا ہوتا ہے۔ ہر تاریخ کا نیا اندراج پچھلے کی جگہ محفوظ ہوگا۔')),
                if (records.isEmpty && _sleepError == null && !_loading)
                  Text(tr('No sleep recorded yet.', 'ابھی نیند درج نہیں۔')),
                FilledButton.icon(
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.bedtime_outlined),
                    label: Text(
                        tr('Log / correct sleep', 'نیند درج یا درست کریں'))),
                for (final record in records)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '${record['sleep_date']} · ${durationLabel(num.parse(record['sleep_minutes'].toString()))}'),
                            Text(
                                '${tr('Bedtime', 'سونے کا وقت')}: ${_time(record['bedtime'] as String)}'),
                            Text(
                                '${tr('Wake time', 'جاگنے کا وقت')}: ${_time(record['wake_time'] as String)}'),
                            Text(
                                '${tr('Quality', 'معیار')}: ${record['quality']}/5 · ${tr('Awakenings', 'بیداری')}: ${record['awakenings']}'),
                          ])),
              ]),
              OutlinedButton(
                  onPressed: _loading ? null : _refresh,
                  child: Text(tr('Refresh', 'تازہ کریں'))),
            ],
          )),
    );
  }

  String _time(String value) {
    final date = DateTime.parse(value).toLocal();
    return '${MaterialLocalizations.of(context).formatShortDate(date)} ${TimeOfDay.fromDateTime(date).format(context)}';
  }
}

class _SleepEditor extends StatefulWidget {
  const _SleepEditor(
      {required this.service, required this.isUrdu, this.bedtime, this.wake});
  final DigitalWellbeingService service;
  final bool isUrdu;
  final DateTime? bedtime, wake;
  @override
  State<_SleepEditor> createState() => _SleepEditorState();
}

class _SleepEditorState extends State<_SleepEditor> {
  DateTime? _bed, _wake;
  int _quality = 3;
  int _awakeMinutes = 0;
  int _awakenings = 0;
  bool _saving = false;
  String? _error;
  String tr(String en, String ur) => widget.isUrdu ? ur : en;
  @override
  void initState() {
    super.initState();
    _bed = widget.bedtime;
    _wake = widget.wake;
  }

  Future<void> _pick(bool bedtime) async {
    final now = DateTime.now();
    final selected = bedtime ? _bed : _wake;
    final day = await showDatePicker(
        context: context,
        initialDate: selected ?? now,
        firstDate: now.subtract(const Duration(days: 365)),
        lastDate: now);
    if (day == null || !mounted) return;
    final time = await showTimePicker(
        context: context, initialTime: TimeOfDay.fromDateTime(selected ?? now));
    if (time == null || !mounted) return;
    final date = DateTime(day.year, day.month, day.day, time.hour, time.minute);
    setState(() {
      if (bedtime) {
        _bed = date;
      } else {
        _wake = date;
      }
    });
  }

  Future<void> _save() async {
    final duration =
        _bed == null || _wake == null ? 0 : _wake!.difference(_bed!).inMinutes;
    if (duration <= 0 ||
        duration > 1440 ||
        _wake!.isAfter(DateTime.now()) ||
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
          bedtime: _bed!,
          wake: _wake!,
          awakeMinutes: _awakeMinutes,
          quality: _quality,
          awakenings: _awakenings);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr(
            'Not saved. Check your connection and retry. Your inputs are still here.',
            'محفوظ نہیں ہوا۔ کنکشن چیک کریں۔ اندراج یہاں موجود ہے۔'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
      required int value,
      required int step,
      required int maximum,
      required ValueChanged<int> onChanged}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(hint, style: Theme.of(context).textTheme.bodySmall),
      ])),
      const SizedBox(width: 10),
      IconButton.filledTonal(
        tooltip: tr('Decrease', 'کم کریں'),
        onPressed: _saving || value <= 0
            ? null
            : () => onChanged((value - step).clamp(0, maximum)),
        icon: const Icon(Icons.remove_rounded),
      ),
      SizedBox(
          width: 42,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium)),
      IconButton.filledTonal(
        tooltip: tr('Increase', 'بڑھائیں'),
        onPressed: _saving || value >= maximum
            ? null
            : () => onChanged((value + step).clamp(0, maximum)),
        icon: const Icon(Icons.add_rounded),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
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
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(tr(
                        'Confirm your actual sleep. Phone inactivity is only a suggestion.',
                        'اپنی حقیقی نیند درج کریں۔ فون بند ہونا صرف ایک اندازہ ہے۔',
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
                  if (_bed != null &&
                      _wake != null &&
                      _wake!.isAfter(_bed!)) ...[
                    const SizedBox(height: 10),
                    Text(
                        '${tr('Time in bed', 'بستر میں وقت')}: ${durationLabel(_wake!.difference(_bed!).inMinutes)}'),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              _section(
                title: tr('During the night', 'رات کے دوران'),
                icon: Icons.dark_mode_outlined,
                child: Column(children: [
                  _stepper(
                    label: tr('Minutes awake', 'جاگنے کے منٹ'),
                    hint: tr('Total time awake', 'جاگنے کا کل وقت'),
                    value: _awakeMinutes,
                    step: 5,
                    maximum: 300,
                    onChanged: (value) => setState(() => _awakeMinutes = value),
                  ),
                  const Divider(height: 24),
                  _stepper(
                    label: tr('Awakenings', 'بیداری'),
                    hint: tr('Times you woke up', 'کتنی بار جاگیں'),
                    value: _awakenings,
                    step: 1,
                    maximum: 20,
                    onChanged: (value) => setState(() => _awakenings = value),
                  ),
                ]),
              ),
              const SizedBox(height: 14),
              _section(
                title: tr('How was your sleep?', 'آپ کی نیند کیسی تھی؟'),
                icon: Icons.sentiment_satisfied_alt_rounded,
                child: Column(children: [
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(tr('Poor', 'کم')),
                        Text(tr('Good', 'اچھی')),
                      ]),
                  Slider(
                    value: _quality.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$_quality / 5',
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _quality = value.round()),
                  ),
                  Text('$_quality / 5',
                      style: Theme.of(context).textTheme.titleMedium),
                ]),
              ),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
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
