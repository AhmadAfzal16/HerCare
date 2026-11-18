import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/screening_models.dart';
import '../../providers/language_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/push_notification_service.dart';
import '../../services/screening_service.dart';

/// Server-owned due dates; no clinical scores or answers cached in this view.
class TestsScreen extends StatefulWidget {
  const TestsScreen(
      {super.key, this.embedded = false, this.active = true, this.service});
  final bool embedded;
  final bool active;
  final ScreeningService? service;

  @override
  State<TestsScreen> createState() => _TestsScreenState();
}

class _TestsScreenState extends State<TestsScreen> with WidgetsBindingObserver {
  late final ScreeningService _service = widget.service ?? ScreeningService();
  List<ScheduledScreening> _tests = const [];
  bool _loading = false;
  String? _error;
  Timer? _dueTimer;
  ReceivedPush? _lastPush;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PushNotificationService.instance.addListener(_onPush);
    // Both the standalone route and home shell are keyed by account identity.
    _service.bindAccount(context.read<AuthProvider?>()?.user?.id);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant TestsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _refresh();
    if (!widget.active) _dueTimer?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.active) _refresh();
    if (state != AppLifecycleState.resumed) _dueTimer?.cancel();
  }

  void _onPush() {
    final messages = PushNotificationService.instance.messages;
    if (messages.isEmpty || identical(_lastPush, messages.first)) return;
    _lastPush = messages.first;
    if (widget.active && _lastPush!.data['type'] == 'screening_reminder') {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    if (_loading || !mounted) return;
    _dueTimer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tests = await _service.getSchedule();
      if (!mounted) return;
      setState(() => _tests = tests);
      final upcoming = tests.where((test) => !test.due).toList()
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
      if (upcoming.isNotEmpty && widget.active) {
        final delay = upcoming.first.dueAt.difference(DateTime.now());
        // A slightly wrong device clock must not create a tight request loop.
        _dueTimer = Timer(
            delay > const Duration(minutes: 1)
                ? delay + const Duration(seconds: 1)
                : const Duration(minutes: 1),
            _refresh);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'refresh_failed');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _open(ScheduledScreening test) async {
    final path =
        test.instrumentType == 'phq9' ? AppRoutes.phq9 : AppRoutes.epds;
    final route = Uri(
            path: path,
            queryParameters:
                test.draftId == null ? null : {'draft': test.draftId!})
        .toString();
    await context.push(route);
    if (mounted) await _refresh();
  }

  @override
  void dispose() {
    _dueTimer?.cancel();
    PushNotificationService.instance.removeListener(_onPush);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    final due = _tests.where((test) => test.due).toList();
    final upcoming = _tests.where((test) => !test.due).toList();
    return Directionality(
      textDirection: ur ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: context.hcBg,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: widget.embedded
              ? null
              : IconButton(
                  tooltip: ur ? 'واپس' : 'Back',
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.home),
                ),
          title: Text(ur ? 'جانچیں' : 'Tests'),
          actions: [
            IconButton(
              tooltip: ur ? 'پچھلی جانچیں' : 'Test history',
              icon: const Icon(Icons.history_rounded),
              onPressed: () => context.push(AppRoutes.screeningHistory),
            )
          ],
        ),
        body: SafeArea(
          top: false,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                        ur
                            ? 'اپنی رفتار سے اپنی صحت کا خیال رکھیں'
                            : 'A little time for your wellbeing',
                        style: Theme.of(context).textTheme.headlineSmall),
                    const SizedBox(height: 8),
                    Text(ur
                        ? 'روزانہ موڈ چیک اِن، ہر ۷ دن بعد EPDS اور ہر ۱۴ دن بعد PHQ-9۔ یہ جانچیں تشخیص نہیں ہیں۔'
                        : 'Daily mood check-ins, EPDS every 7 days, and PHQ-9 every 14 days. These are screening tools, not a diagnosis.'),
                    const SizedBox(height: 16),
                    if (_loading) const LinearProgressIndicator(),
                    if (_error != null) ...[
                      Text(ur
                          ? 'تازہ شیڈول حاصل نہیں ہوا۔ انٹرنیٹ کنکشن چیک کریں۔'
                          : 'Could not refresh the schedule. Check your connection; shown dates may be out of date.'),
                      Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: TextButton.icon(
                            onPressed: _loading ? null : _refresh,
                            icon: const Icon(Icons.refresh),
                            label: Text(ur ? 'دوبارہ کوشش' : 'Retry'),
                          )),
                    ],
                    if (!_loading && _error == null && due.isEmpty)
                      _notice(ur
                          ? 'ابھی کوئی جانچ باقی نہیں ہے۔ اگلی تاریخیں نیچے ہیں۔'
                          : 'You’re up to date. Your next tests are listed below.'),
                    if (due.isNotEmpty) ...[
                      _heading(ur ? 'باقی جانچیں' : 'Ready for you'),
                      for (final test in due) _testCard(test, ur),
                    ],
                    if (upcoming.isNotEmpty) ...[
                      _heading(ur ? 'آنے والی جانچیں' : 'Upcoming'),
                      for (final test in upcoming) _testCard(test, ur),
                    ],
                    const SizedBox(height: 12),
                    _heading(ur ? 'روزانہ موڈ' : 'Your daily mood'),
                    Text(ur
                        ? 'روزانہ احساسات درج کریں۔ PHQ-9 پھر بھی پچھلے دو ہفتوں کے بارے میں ہے۔'
                        : 'Record how you feel today. PHQ-9 still asks about the past two weeks.'),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.mood),
                      icon: const Icon(Icons.mood_rounded),
                      label: Text(ur
                          ? 'موڈ چیک اِن کھولیں'
                          : 'Open daily mood check-in'),
                    ),
                    const SizedBox(height: 16),
                    _notice(ur
                        ? 'یاد دہانی کے لیے فون کی سیٹنگز میں HerCare کی اطلاعات فعال رکھیں۔ خطرے کی صورت میں اگلی جانچ کا انتظار نہ کریں۔'
                        : 'Allow HerCare notifications in your phone settings for reminders. If you need urgent support, don’t wait for the next test.'),
                    TextButton.icon(
                      onPressed: () => context.push(AppRoutes.crisis),
                      icon: const Icon(Icons.support_agent_rounded),
                      label:
                          Text(ur ? 'ابھی مدد حاصل کریں' : 'Get support now'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heading(String title) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(title, style: Theme.of(context).textTheme.titleMedium),
      );

  Widget _notice(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(text),
      );

  Widget _testCard(ScheduledScreening test, bool ur) {
    final epds = test.instrumentType == 'epds';
    final local = test.dueAt.toLocal();
    final date = MaterialLocalizations.of(context).formatMediumDate(local);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(local));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: context.hcSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: test.due || test.draftId != null ? () => _open(test) : null,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(epds ? Icons.favorite_outline : Icons.assignment_outlined,
                color: AppColors.primary),
            const SizedBox(height: 8),
            Text(epds ? 'EPDS' : 'PHQ-9',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(epds
                ? (ur
                    ? '۱۰ سوالات · پچھلے ۷ دن'
                    : '10 questions · About the past 7 days')
                : (ur
                    ? '۹ سوالات · پچھلے ۱۴ دن'
                    : '9 questions · About the past 14 days')),
            const SizedBox(height: 8),
            Text(test.due
                ? (ur ? 'جانچ کا وقت ہو گیا ہے' : 'Due now')
                : (ur ? 'اگلی جانچ: $date · $time' : 'Next: $date · $time')),
            const SizedBox(height: 12),
            if (test.due || test.draftId != null)
              FilledButton.icon(
                key: ValueKey('start-${test.instrumentType}'),
                onPressed: () => _open(test),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text(test.draftId != null
                    ? (ur ? 'جانچ جاری رکھیں' : 'Continue test')
                    : (ur ? 'جانچ شروع کریں' : 'Start test')),
              )
            else
              Text(ur
                  ? 'مقررہ وقت پر یہاں کھل جائے گی۔'
                  : 'Available here when due.'),
          ]),
        ),
      ),
    );
  }
}
