import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/crisis_models.dart';
import '../../providers/language_provider.dart';
import '../../services/crisis_service.dart';
import '../../services/care_directory_service.dart';
import 'crisis_grounding.dart';
import 'crisis_alarm.dart';
import 'care_directory_screen.dart';
import 'crisis_account_guard.dart';
import 'crisis_links.dart';
import 'crisis_plan_cache.dart';
import 'crisis_plan_editor.dart';

/// Urgent help never depends on login, a form, network or a calming timer.
class CrisisSupportScreen extends StatefulWidget {
  const CrisisSupportScreen(
      {super.key,
      this.accountId,
      this.isGuardian = false,
      this.service,
      this.careDirectory,
      this.cache,
      this.links});
  final String? accountId;
  final bool isGuardian;
  final CrisisService? service;
  final CareDirectoryService? careDirectory;
  final CrisisPlanCache? cache;
  final CrisisLinks? links;
  @override
  State<CrisisSupportScreen> createState() => _CrisisSupportScreenState();
}

class _CrisisSupportScreenState extends State<CrisisSupportScreen> {
  late CrisisService _service;
  late final _cache = widget.cache ?? CrisisPlanCache();
  late final _links = widget.links ?? CrisisLinks();
  final _scroll = ScrollController();
  CrisisCatalog? _catalog;
  String _regionId = 'unspecified';
  CrisisPlan _plan = const CrisisPlan();
  CrisisGuardian? _guardian;
  CrisisEvent? _event;
  CachedCrisisPlan? _download;
  bool _loading = true, _online = false, _busy = false, _notify = false;
  String? _requestId, _requestLink;
  bool _requestNotify = false;
  bool _alarmExpanded = false;
  DateTime? _requestedAt;
  int _generation = 0;

  bool get _private => widget.accountId != null && !widget.isGuardian;
  bool get _ur => context.read<LanguageProvider>().isUrdu;
  String _t(String en, String ur) => _ur ? ur : en;
  @override
  void initState() {
    super.initState();
    _service =
        widget.service ?? CrisisService(expectedAccountId: widget.accountId);
    _loadCatalog();
    _loadPrivate();
  }

  @override
  void didUpdateWidget(CrisisSupportScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.isGuardian != widget.isGuardian) {
      _generation++;
      _plan = const CrisisPlan();
      _download = null;
      _guardian = null;
      _event = null;
      _requestId = null;
      _online = false;
      _busy = false;
      _notify = false;
      _alarmExpanded = false;
      _service =
          widget.service ?? CrisisService(expectedAccountId: widget.accountId);
      _loadPrivate();
    }
  }

  @override
  void dispose() {
    _generation++;
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    try {
      final raw = await rootBundle.loadString('assets/crisis_contacts.json',
          cache: false);
      final catalog = CrisisCatalog.fromJson(jsonDecode(raw));
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _regionId = prefs.getString('m10_help_region') ?? 'unspecified';
      });
    } catch (_) {
      /* Generic help remains usable if a public asset is invalid. */
    }
    try {
      final catalog = await _service.contacts();
      if (mounted) setState(() => _catalog = catalog);
    } catch (_) {/* Versioned public catalog works offline without an API. */}
  }

  Future<void> _loadPrivate() async {
    final generation = ++_generation, accountId = widget.accountId;
    if (!_private || accountId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _loading = true;
        _online = false;
        _guardian = null;
      });
    }
    CachedCrisisPlan? download;
    try {
      download = await _cache.read(accountId);
    } catch (_) {}
    if (!mounted || generation != _generation) return;
    setState(() {
      _download = download;
      _plan = download?.plan ?? const CrisisPlan();
    });
    try {
      final support = await _service.support();
      if (!mounted || generation != _generation) return;
      var refreshed = false;
      if (download != null) {
        try {
          if (support.plan.isEmpty) {
            await _cache.clear(accountId);
          } else {
            await _cache.save(accountId, support.plan);
            refreshed = true;
          }
        } catch (_) {
          // A stale download must not masquerade as a refreshed copy.
          try {
            await _cache.clear(accountId);
          } catch (_) {}
        }
      }
      if (!mounted || generation != _generation) {
        if (refreshed) {
          try {
            await _cache.clear(accountId);
          } catch (_) {}
        }
        return;
      }
      setState(() {
        _plan = support.plan;
        _guardian = support.guardian;
        _event = support.openEvent;
        _online = true;
        _loading = false;
        _download = refreshed
            ? CachedCrisisPlan(plan: support.plan, savedAt: DateTime.now())
            : null;
      });
    } on CrisisAccessException {
      try {
        await _cache.clear(accountId);
      } catch (_) {}
      if (!mounted || generation != _generation) return;
      setState(() {
        _plan = const CrisisPlan();
        _guardian = null;
        _event = null;
        _download = null;
        _online = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _guardian = null;
        _event = null;
        _online = false;
        _loading = false;
      });
    }
  }

  void _notice(String en, String ur) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_t(en, ur)), duration: const Duration(seconds: 6)));
    }
  }

  Future<bool> _confirm(
      String en, String ur, String bodyEn, String bodyUr) async {
    final accountId = _private ? widget.accountId : null;
    // The source route may be disposed while this modal remains in Navigator.
    final urdu = _ur;
    final title = urdu ? ur : en;
    final body = urdu ? bodyUr : bodyEn;
    final cancel = urdu ? 'ابھی نہیں' : 'Not now';
    final proceed = urdu ? 'جاری رکھیں' : 'Continue';
    return await showDialog<bool>(
            context: context,
            builder: (dialog) {
              final confirmation = AlertDialog(
                scrollable: true,
                title: Text(title),
                content: Text(body),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialog).pop(false),
                      child: Text(cancel)),
                  FilledButton(
                      onPressed: () => Navigator.of(dialog).pop(true),
                      child: Text(proceed)),
                ],
              );
              return accountId == null
                  ? confirmation
                  : CrisisAccountGuard(
                      accountId: accountId, child: confirmation);
            }) ??
        false;
  }

  Future<void> _call(String phone) async {
    var opened = false;
    try {
      opened = await _links.call(phone);
    } catch (_) {}
    _notice(
        opened
            ? 'Dialer opened. Please place the call; HerCare cannot confirm connection.'
            : 'Could not open the dialer. Dial $phone manually or seek in-person help.',
        opened
            ? 'ڈائلر کھل گیا۔ خود کال کریں؛ ہر کیئر رابطہ ہونے کی تصدیق نہیں کر سکتا۔'
            : 'ڈائلر نہیں کھل سکا۔ $phone خود ڈائل کریں یا بالمشافہ مدد لیں۔');
  }

  CrisisRegion? get _region {
    for (final region in _catalog?.regions ?? <CrisisRegion>[]) {
      if (region.id == _regionId) return region;
    }
    return null;
  }

  Future<void> _chooseRegion({bool thenCall = false}) async {
    final catalog = _catalog;
    final urdu = _ur;
    String text(String en, String ur) => urdu ? ur : en;
    if (catalog == null) {
      await _genericDialer();
      return;
    }
    final selected = await showModalBottomSheet<CrisisRegion>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => FractionallySizedBox(
            heightFactor: .8,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(
                  text('Where are you right now?',
                      'اس وقت آپ کس علاقے میں ہیں؟'),
                  style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(text(
                  'One optional choice. This area choice does not request location. For other areas, use your local emergency number.',
                  'ایک اختیاری انتخاب۔ علاقے کے اس انتخاب سے مقام کی اجازت نہیں مانگی جاتی۔ دوسرے علاقوں میں اپنا مقامی ہنگامی نمبر استعمال کریں۔')),
              for (final region
                  in catalog.regions.where((r) => r.id != 'unspecified'))
                ListTile(
                    title: Text(region.name(urdu)),
                    subtitle: Text(
                        urdu ? region.coverageNoticeUr : region.coverageNotice),
                    onTap: () => Navigator.of(sheet).pop(region)),
            ])));
    if (!mounted || selected == null) return;
    setState(() => _regionId = selected.id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('m10_help_region', selected.id);
    if (!mounted || !thenCall) return;
    if (selected.emergencyNumber != null) {
      await _call(selected.emergencyNumber!);
    } else {
      await _genericDialer();
    }
  }

  Future<void> _genericDialer() async {
    try {
      await _links.openDialer();
    } catch (_) {}
    _notice(
        'Use the local emergency number or go to an emergency department now. Do not wait for HerCare.',
        'مقامی ہنگامی نمبر استعمال کریں یا ابھی ہسپتال کی ایمرجنسی جائیں۔ ہر کیئر کا انتظار نہ کریں۔');
  }

  Future<void> _emergency() async {
    if (_region == null || _region!.id == 'unspecified') {
      await _chooseRegion(thenCall: true);
    } else if (_region!.emergencyNumber != null) {
      await _call(_region!.emergencyNumber!);
    } else {
      await _genericDialer();
    }
  }

  Future<void> _map({bool mentalHealth = false}) async {
    if (!await _confirm(
        'Open Maps?',
        'نقشہ کھولیں؟',
        'Maps opens outside HerCare and may ask for location or use its own history. This action does not request location in HerCare. The optional directory location is separate and stays on this phone. Results are not verified providers or guaranteed open. In immediate danger, call emergency services first.',
        'نقشہ ہر کیئر سے باہر کھلے گا اور مقام مانگ سکتا ہے یا اپنی ہسٹری استعمال کر سکتا ہے۔ اس عمل میں ہر کیئر مقام نہیں مانگتا۔ فہرست کا اختیاری مقام الگ ہے اور صرف فون پر رہتا ہے۔ نتائج تصدیق شدہ یا کھلے ہونے کی ضمانت نہیں۔ فوری خطرے میں پہلے ہنگامی کال کریں۔')) {
      return;
    }
    if (!mounted) return;
    var opened = false;
    try {
      opened = await _links.map(mentalHealth: mentalHealth);
    } catch (_) {}
    if (!opened) {
      _notice(
          'Maps could not open. Ask a trusted person to help you reach an emergency department.',
          'نقشہ نہیں کھل سکا۔ قابل اعتماد شخص سے ہسپتال کی ایمرجنسی تک پہنچنے میں مدد لیں۔');
    }
  }

  Future<void> _guardianSafety(bool confirmed) async {
    final generation = _generation;
    final guardian = _guardian;
    if (guardian == null || !_online || _busy) return;
    if (confirmed &&
        !await _confirm(
            'Is this guardian safe to contact?',
            'کیا اس سرپرست سے رابطہ محفوظ ہے؟',
            'Only confirm if contacting ${guardian.name} is safe for you. This permits future urgent safety alerts while sharing consent and this link remain active. Your private plan, journals and conversations are never shared. Push delivery is not guaranteed. You can turn this off here.',
            'صرف تب تصدیق کریں جب ${guardian.name} سے رابطہ محفوظ ہو۔ فعال رضامندی اور اس لنک کے ساتھ آئندہ فوری حفاظتی اطلاعات کی اجازت ہوگی۔ نجی منصوبہ، جریدہ اور گفتگو نہیں بھیجی جاتی۔ اطلاع پہنچنے کی ضمانت نہیں۔ آپ یہاں اجازت بند کر سکتی ہیں۔')) {
      return;
    }
    if (!mounted || generation != _generation) return;
    setState(() => _busy = true);
    try {
      final updated = await _service.guardianSafety(guardian.linkId, confirmed);
      if (!mounted || generation != _generation) return;
      setState(() {
        _guardian = updated;
        if (!confirmed) _notify = false;
      });
    } on CrisisAccessException {
      await _denyPrivate(generation);
    } catch (_) {
      _notice('Permission could not update. Refresh before trying again.',
          'اجازت نہیں بدلی۔ دوبارہ کوشش سے پہلے تازہ کریں۔');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<bool> _savePlan(
    CrisisPlan plan, {
    required int expectedGeneration,
    required String expectedAccountId,
  }) async {
    final accountId = widget.accountId, generation = _generation;
    if (!_private ||
        accountId == null ||
        !_online ||
        generation != expectedGeneration ||
        accountId != expectedAccountId) {
      return false;
    }
    try {
      final saved = await _service.savePlan(plan);
      if (!mounted || generation != _generation) return false;
      var downloaded = _download != null;
      if (downloaded) {
        try {
          if (saved.isEmpty) {
            await _cache.clear(accountId);
            downloaded = false;
          } else {
            await _cache.save(accountId, saved);
          }
        } catch (_) {
          downloaded = false;
          try {
            await _cache.clear(accountId);
          } catch (_) {}
          _notice(
              'Server plan saved; the offline copy could not update. Download it again.',
              'منصوبہ سرور پر محفوظ ہے؛ آف لائن نقل تازہ نہیں ہوئی۔ دوبارہ ڈاؤن لوڈ کریں۔');
        }
      }
      if (!mounted || generation != _generation) {
        if (downloaded) {
          try {
            await _cache.clear(accountId);
          } catch (_) {}
        }
        return false;
      }
      setState(() {
        _plan = saved;
        _download = downloaded
            ? CachedCrisisPlan(plan: saved, savedAt: DateTime.now())
            : null;
      });
      return true;
    } on CrisisAccessException {
      await _denyPrivate(generation);
      return false;
    } on CrisisConflictException {
      _notice(
          'The plan changed on another device. Refresh, then edit the current version. Nothing was overwritten.',
          'دوسرے آلے پر منصوبہ بدل گیا۔ تازہ کریں، پھر موجودہ منصوبہ بدلیں۔ کچھ تبدیل نہیں کیا گیا۔');
      return false;
    } catch (_) {
      _notice(
          'The plan was not saved. Direct help still works. No upload is queued.',
          'منصوبہ محفوظ نہیں ہوا۔ براہ راست مدد دستیاب ہے۔ خودکار اپ لوڈ نہیں ہوگا۔');
      return false;
    }
  }

  Future<void> _downloadPlan(bool enabled) async {
    final accountId = widget.accountId;
    final generation = _generation;
    if (!_private || accountId == null || !_cache.available || _busy) return;
    if (enabled &&
        !await _confirm(
            'Keep a private offline copy?',
            'نجی آف لائن نقل رکھیں؟',
            'An encrypted copy of your plan and contact stays on this phone for up to 30 days. Someone using your unlocked app may see it. Contacts can change offline; this copy cannot check revoked relationships. Remove it here or logout to clear it. Nothing sends automatically.',
            'منصوبے اور رابطے کی رمز شدہ نقل اس فون پر ۳۰ دن تک رہے گی۔ کھلی ایپ استعمال کرنے والا اسے دیکھ سکتا ہے۔ آف لائن رابطے بدل سکتے ہیں؛ یہ نقل ختم شدہ رشتے کی تصدیق نہیں کرتی۔ یہاں ہٹائیں یا لاگ آؤٹ کریں۔ خودکار طور پر کچھ نہیں بھیجا جاتا۔')) {
      return;
    }
    if (!mounted || generation != _generation) return;
    setState(() => _busy = true);
    try {
      if (enabled) {
        await _cache.save(accountId, _plan);
      } else {
        await _cache.clear(accountId);
      }
      if (!mounted || generation != _generation) {
        if (enabled) {
          try {
            await _cache.clear(accountId);
          } catch (_) {}
        }
        return;
      }
      setState(() => _download = enabled
          ? CachedCrisisPlan(plan: _plan, savedAt: DateTime.now())
          : null);
    } catch (_) {
      _notice('The offline copy could not change. Server plan is unchanged.',
          'آف لائن نقل نہیں بدلی۔ سرور منصوبہ نہیں بدلا۔');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _deletePlan() async {
    final generation = _generation, accountId = widget.accountId;
    if (!_online ||
        _busy ||
        !await _confirm(
            'Delete my private plan?',
            'نجی منصوبہ مٹائیں؟',
            'Deletes the server plan and this phone’s download. It does not delete crisis events or disable guardian alert permission.',
            'سرور منصوبہ اور اس فون کی نقل مٹ جائے گی۔ حفاظتی واقعات یا سرپرست کی اطلاع کی اجازت نہیں مٹے گی۔')) {
      return;
    }
    if (!mounted || generation != _generation || accountId == null) return;
    setState(() => _busy = true);
    try {
      final plan = await _service.deletePlan(_plan.version);
      if (!mounted || generation != _generation) return;
      await _cache.clear(accountId);
      if (!mounted || generation != _generation) return;
      setState(() {
        _plan = plan;
        _download = null;
      });
    } on CrisisAccessException {
      await _denyPrivate(generation);
    } catch (_) {
      _notice('Could not delete the plan. Refresh before retrying.',
          'منصوبہ نہیں مٹا۔ دوبارہ کوشش سے پہلے تازہ کریں۔');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _requestHelp() async {
    final generation = _generation;
    if (!_private || !_online || _busy) return;
    if (_requestId != null &&
        DateTime.now().difference(_requestedAt!) > const Duration(minutes: 2)) {
      _notice(
          'Retry expired. Use direct calls now; discard the retry before making a new request.',
          'دوبارہ کوشش کا وقت ختم ہوا۔ ابھی براہ راست کال کریں؛ نئی درخواست سے پہلے کوشش ہٹائیں۔');
      return;
    }
    if (_requestId == null) {
      final notify = _notify && _guardian?.safeToContactConfirmed == true;
      if (!await _confirm(
          notify
              ? 'Send a limited guardian notice?'
              : 'Record a private request?',
          notify ? 'سرپرست کو مختصر اطلاع بھیجیں؟' : 'نجی درخواست درج کریں؟',
          notify
              ? 'A limited urgent notice will be queued to your confirmed safe guardian. This does not call an ambulance or guarantee delivery. Use direct help now if needed.'
              : 'This only records a private request in HerCare. It does not call emergency services, contact a professional or alert anyone.',
          notify
              ? 'محفوظ سرپرست کے لیے مختصر فوری پیغام بھیجا جائے گا۔ یہ ایمبولینس نہیں بلاتا اور اطلاع پہنچنے کی ضمانت نہیں۔ ضرورت ہو تو براہ راست مدد لیں۔'
              : 'یہ صرف ہر کیئر میں نجی درخواست درج کرتا ہے۔ ہنگامی خدمات، پیشہ ور یا کسی اور سے رابطہ نہیں کرتا۔')) {
        return;
      }
      if (!mounted || generation != _generation) return;
      _requestId = CrisisService.requestId();
      _requestNotify = notify;
      _requestLink = notify ? _guardian?.linkId : null;
      _requestedAt = DateTime.now();
    }
    if (!mounted || generation != _generation) return;
    setState(() => _busy = true);
    try {
      final event = await _service.requestHelp(
          requestId: _requestId!,
          notifyGuardian: _requestNotify,
          guardianLinkId: _requestLink);
      if (!mounted || generation != _generation) return;
      setState(() {
        _event = event;
        _requestId = null;
      });
      _notice(
          event.guardianNotification == 'queued'
              ? 'Notice queued—not guaranteed delivered. Use direct help if needed.'
              : 'Request recorded. No confirmed guardian delivery. Use direct help if needed.',
          event.guardianNotification == 'queued'
              ? 'اطلاع بھیجنے کی فہرست میں ہے، پہنچنے کی ضمانت نہیں۔ ضرورت ہو تو براہ راست مدد لیں۔'
              : 'درخواست درج ہے۔ سرپرست تک پہنچنے کی تصدیق نہیں۔ ضرورت ہو تو براہ راست مدد لیں۔');
    } on CrisisAccessException {
      await _denyPrivate(generation);
    } catch (_) {
      _notice(
          'Could not confirm the request. It may have reached the server. No automatic retry; use direct calls now.',
          'درخواست کی تصدیق نہیں؛ ممکن ہے سرور تک پہنچی ہو۔ خودکار دوبارہ کوشش نہیں ہوگی؛ ابھی براہ راست کال کریں۔');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _updateEvent(String status, {String? outcome}) async {
    final event = _event;
    if (event == null || !_online || _busy) return;
    final generation = _generation;
    setState(() => _busy = true);
    try {
      final updated = await _service.updateEvent(event.id,
          status: status, outcome: outcome);
      if (!mounted || generation != _generation) return;
      setState(() => _event = updated.isClosed ? null : updated);
      if (updated.isClosed) {
        _notice('Record closed by you—not confirmation of safety or recovery.',
            'آپ نے ریکارڈ بند کیا — حفاظت یا صحت یابی کی تصدیق نہیں۔');
      }
    } on CrisisAccessException {
      await _denyPrivate(generation);
    } catch (_) {
      _notice('Record did not update. No safety status changed.',
          'ریکارڈ نہیں بدلا۔ حفاظت کی کیفیت نہیں بدلی۔');
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _closeEvent() async {
    final generation = _generation;
    final eventId = _event?.id;
    final urdu = _ur;
    String text(String en, String ur) => urdu ? ur : en;
    final outcome = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (sheet) => FractionallySizedBox(
            heightFactor: .8,
            child: ListView(padding: const EdgeInsets.all(20), children: [
              Text(
                  text('Close this record—not a safety assessment',
                      'ریکارڈ بند کریں — حفاظتی جانچ نہیں'),
                  style: Theme.of(sheet).textTheme.titleLarge),
              const SizedBox(height: 12),
              Text(text(
                  'Choose a reason. This does not show danger has passed. Keep using urgent help if needed.',
                  'وجہ منتخب کریں۔ اس سے خطرہ ختم ہونے کی تصدیق نہیں ہوتی۔ ضرورت ہو تو فوری مدد لیتے رہیں۔')),
              for (final item in {
                'support_contacted': text('I contacted a trusted person',
                    'قابل اعتماد شخص سے رابطہ کیا'),
                'professional_help_contacted': text(
                    'I contacted professional help',
                    'پیشہ ورانہ مدد سے رابطہ کیا'),
                'accidental_activation':
                    text('Opened accidentally', 'غلطی سے کھلا تھا'),
                'other': text('Another reason / prefer not to say',
                    'دوسری وجہ / بتانا نہیں چاہتی'),
              }.entries)
                ListTile(
                    title: Text(item.value),
                    onTap: () => Navigator.of(sheet).pop(item.key)),
            ])));
    if (outcome != null &&
        mounted &&
        generation == _generation &&
        _event?.id == eventId) {
      await _updateEvent('resolved', outcome: outcome);
    }
  }

  Future<void> _denyPrivate(int generation) async {
    final accountId = widget.accountId;
    if (!mounted || generation != _generation || accountId == null) return;
    _generation++;
    final deniedGeneration = _generation;
    try {
      await _cache.clear(accountId);
    } catch (_) {}
    if (!mounted ||
        accountId != widget.accountId ||
        deniedGeneration != _generation) {
      return;
    }
    setState(() {
      _plan = const CrisisPlan();
      _download = null;
      _guardian = null;
      _event = null;
      _requestId = null;
      _notify = false;
      _online = false;
      _loading = false;
      _busy = false;
    });
    _notice(
        'Private access could not be confirmed; downloaded plan cleared. Direct emergency help remains available.',
        'نجی رسائی کی تصدیق نہیں ہوئی؛ ڈاؤن لوڈ منصوبہ مٹا دیا گیا۔ براہ راست ہنگامی مدد دستیاب ہے۔');
  }

  Widget _action(String label, IconData icon, VoidCallback? onPressed,
          {bool urgent = false, Key? key}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FilledButton(
            key: key,
            onPressed: onPressed,
            style: urgent
                ? FilledButton.styleFrom(
                    backgroundColor: AppColors.crisis,
                    foregroundColor: Colors.white)
                : null,
            child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(children: [
                  Icon(icon),
                  const SizedBox(width: 12),
                  Expanded(child: Text(label)),
                ])),
          ));
  Widget _card(List<Widget> children) => Card(
      color: context.hcSurface,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children)));
  String _delivery(CrisisEvent event) {
    return switch (event.notificationDelivery) {
      'cancelled' =>
        _t('Guardian notice cancelled.', 'سرپرست کی اطلاع منسوخ ہے۔'),
      'failed' => _t('Guardian notice failed. Use direct help.',
          'سرپرست کی اطلاع ناکام۔ براہ راست مدد لیں۔'),
      'no_device' => _t('No registered guardian device. Use a direct call.',
          'سرپرست کا آلہ درج نہیں۔ براہ راست کال کریں۔'),
      'sent' => _t(
          'Push provider accepted the notice—not proof it was read or help arrived.',
          'اطلاع سروس نے پیغام قبول کیا؛ پڑھنے یا مدد آنے کی تصدیق نہیں۔'),
      'pending' || 'sending' || 'retry' => _t(
          'Guardian notice pending—not guaranteed delivered.',
          'سرپرست کا پیغام زیرِ عمل؛ پہنچنے کی ضمانت نہیں۔'),
      _ => event.guardianNotification == 'queued'
          ? _t('Notice was queued; delivery is unconfirmed.',
              'اطلاع فہرست میں تھی؛ پہنچنے کی تصدیق نہیں۔')
          : _t('No guardian notice requested for this record.',
              'اس ریکارڈ کے لیے سرپرست کی اطلاع کی درخواست نہیں۔'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu, region = _region;
    return Scaffold(
      backgroundColor: context.hcBg,
      appBar: AppBar(title: Text(ur ? 'فوری مدد' : 'Immediate help')),
      body: SafeArea(
          child: ListView(
              key: const ValueKey('crisis-help-list'),
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
            Text(_t('You are not alone', 'آپ اکیلی نہیں ہیں'),
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            // Action buttons precede lengthy guidance and optional account controls.
            _action(
                _t('Call emergency${region?.emergencyNumber == null ? '' : ' · ${region!.emergencyNumber}'}',
                    'ہنگامی کال${region?.emergencyNumber == null ? '' : ' · ${region!.emergencyNumber}'}'),
                Icons.phone_in_talk,
                _emergency,
                urgent: true,
                key: const ValueKey('crisis-emergency-call')),
            if (_plan.supportPhone.isNotEmpty)
              _action(
                  _t('Call ${_plan.supportPersonName.isEmpty ? 'my trusted person' : _plan.supportPersonName}',
                      '${_plan.supportPersonName.isEmpty ? 'قابل اعتماد شخص' : _plan.supportPersonName} کو کال کریں'),
                  Icons.support_agent,
                  () => _call(_plan.supportPhone),
                  key: const ValueKey('crisis-trusted-call')),
            if (_guardian?.safeToContactConfirmed == true &&
                _plan.supportPhone != _guardian?.phone)
              _action(_t('Call safe guardian', 'محفوظ سرپرست کو کال کریں'),
                  Icons.person, () => _call(_guardian!.phone)),
            OutlinedButton.icon(
                key: const ValueKey('crisis-map-emergency'),
                onPressed: _map,
                icon: const Icon(Icons.local_hospital_outlined),
                label: Text(_t('Find an emergency department',
                    'ہسپتال کی ایمرجنسی تلاش کریں'))),
            OutlinedButton.icon(
                key: const ValueKey('crisis-care-directory'),
                onPressed: () {
                  final navigator = Navigator.of(context);
                  navigator.push(MaterialPageRoute<void>(
                      builder: (_) => CareDirectoryScreen(
                          service: widget.careDirectory,
                          calls: _links,
                          onUrgentHelp: () {
                            navigator.pop();
                            if (mounted && _scroll.hasClients) {
                              _scroll.jumpTo(0);
                            }
                          })));
                },
                icon: const Icon(Icons.location_city_outlined),
                label: Text(_t('Source-checked hospitals · optional location',
                    'سرکاری ذرائع سے جانچے ہسپتال · مقام اختیاری'))),
            const SizedBox(height: 12),
            Text(_t(
                'If you may hurt yourself or your baby, took an overdose, are very confused, hear voices, have heavy bleeding or cannot breathe: seek emergency help now. Do not wait for the app.',
                'اگر خود کو یا بچے کو نقصان کا خطرہ ہو، زیادہ دوا لی ہو، شدید الجھن یا آوازیں ہوں، بہت خون بہے یا سانس نہ آئے: ابھی ہنگامی مدد لیں۔ ایپ کا انتظار نہ کریں۔')),
            const SizedBox(height: 8),
            Text(
                _t('Opening a dialer does not place or confirm a call. Carrier charges may apply.',
                    'ڈائلر کھلنے سے کال نہیں ہوتی یا رابطے کی تصدیق نہیں ہوتی۔ فون کے چارجز لاگو ہو سکتے ہیں۔'),
                style: Theme.of(context).textTheme.bodySmall),
            TextButton(
                key: const ValueKey('crisis-region'),
                onPressed: _chooseRegion,
                child: Text(
                    '${_t('Area', 'علاقہ')}: ${region?.name(ur) ?? _t('Choose your area', 'اپنا علاقہ منتخب کریں')}')),
            if (region != null)
              Text(ur ? region.coverageNoticeUr : region.coverageNotice,
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            _card([
              Text(
                  _t(
                      widget.isGuardian
                          ? 'Helping someone safely'
                          : 'While getting help',
                      widget.isGuardian
                          ? 'محفوظ طریقے سے مدد کریں'
                          : 'مدد لیتے ہوئے'),
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              Text(_t(
                  'Stay with someone you trust. If safe, move away from medicines, weapons or anything that could cause harm. If a partner is unsafe, choose another person or professional help.',
                  'قابل اعتماد شخص کے ساتھ رہیں۔ اگر محفوظ ہو تو دواؤں، ہتھیاروں یا نقصان پہنچانے والی چیزوں سے دور ہو جائیں۔ اگر شریکِ حیات محفوظ نہیں تو کسی دوسرے شخص یا پیشہ ورانہ مدد کا انتخاب کریں۔')),
              const SizedBox(height: 10),
              Text(_t(
                  'If the baby may be at risk, ask a safe adult to care for the baby while you get help. New severe confusion, unusual beliefs or voices after childbirth need urgent medical assessment.',
                  'اگر بچے کو خطرہ ہو تو مدد لیتے ہوئے کسی محفوظ بالغ سے بچے کی دیکھ بھال کہیں۔ زچگی کے بعد نئی شدید الجھن، غیر معمولی خیالات یا آوازیں فوری طبی جانچ چاہتی ہیں۔')),
            ]),
            if (_private) ...[_privatePanel(), _planPanel()],
            _card([
              ExpansionTile(
                  key: const PageStorageKey('crisis-counselling'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                      _t('Counselling and more help', 'مشاورت اور مزید مدد')),
                  children: [
                    Text(_t(
                        'Not emergency dispatch. Do not wait for counselling during immediate danger.',
                        'ہنگامی امداد نہیں۔ فوری خطرے میں مشاورتی لائن کا انتظار نہ کریں۔')),
                    for (final contact
                        in _catalog?.contacts ?? <CrisisContact>[]) ...[
                      const Divider(height: 24),
                      Text(contact.name(ur),
                          style: Theme.of(context).textTheme.titleMedium),
                      SelectableText(contact.phone,
                          textDirection: TextDirection.ltr),
                      Text(contact.hours(ur)),
                      const SizedBox(height: 6),
                      Text(contact.coverage(ur),
                          style: Theme.of(context).textTheme.bodySmall),
                      OutlinedButton.icon(
                          onPressed: () => _call(contact.phone),
                          icon: const Icon(Icons.call_outlined),
                          label: Text(_t('Open dialer', 'ڈائلر کھولیں'))),
                    ],
                    OutlinedButton.icon(
                        onPressed: () => _map(mentalHealth: true),
                        icon: const Icon(Icons.map_outlined),
                        label: Text(_t('Browse mental-health clinics',
                            'ذہنی صحت کے ادارے تلاش کریں'))),
                    if (_catalog != null)
                      Text(ur ? _catalog!.noticeUr : _catalog!.notice,
                          style: Theme.of(context).textTheme.bodySmall),
                  ])
            ]),
            _card([
              ExpansionTile(
                  key: const PageStorageKey('crisis-attention-chime'),
                  tilePadding: EdgeInsets.zero,
                  onExpansionChanged: (value) =>
                      setState(() => _alarmExpanded = value),
                  title: Text(_t('Optional attention sound',
                      'توجہ دلانے کی اختیاری آواز')),
                  children: [
                    CrisisAlarmCard(
                        isUrdu: ur,
                        accountId: widget.accountId,
                        active: _alarmExpanded),
                  ])
            ]),
            _card([
              ExpansionTile(
                  key: const PageStorageKey('crisis-grounding'),
                  tilePadding: EdgeInsets.zero,
                  title: Text(_t('A calming step, if safe',
                      'اگر محفوظ ہوں تو سکون کا قدم')),
                  children: [CrisisGrounding(isUrdu: ur)])
            ]),
          ])),
    );
  }

  Widget _privatePanel() {
    final guardian = _guardian;
    return _card([
      Text(_t('Optional private support', 'اختیاری نجی مدد'),
          style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      Text(_loading
          ? _t(
              'Optional account support is loading. Direct help above is ready.',
              'اختیاری اکاؤنٹ مدد لوڈ ہو رہی ہے۔ اوپر براہ راست مدد تیار ہے۔')
          : _online
              ? _t('Nothing here calls emergency services automatically.',
                  'خودکار ہنگامی کال نہیں ہوتی۔')
              : _t(
                  'Offline or private service unavailable: delivery cannot be checked. This phone does not automatically resend requests. A request already accepted by the server may still process. Use direct calls now.',
                  'آف لائن یا نجی سروس دستیاب نہیں؛ اطلاع پہنچنے کی تصدیق نہیں ہو سکتی۔ یہ فون خودکار دوبارہ درخواست نہیں بھیجتا۔ سرور کی قبول کردہ درخواست اب بھی بھیجی جا سکتی ہے۔ ابھی براہ راست کال کریں۔')),
      if (guardian != null && _online) ...[
        Text('${_t('Linked guardian', 'منسلک سرپرست')}: ${guardian.name}'),
        SwitchListTile(
            key: const ValueKey('crisis-safe-guardian'),
            contentPadding: EdgeInsets.zero,
            title: Text(_t('Safe guardian for urgent alerts',
                'فوری اطلاع کے لیے محفوظ سرپرست')),
            subtitle: Text(_t(
                'Off unless you confirm. Private plan and conversations stay private.',
                'تصدیق کے بغیر بند ہے۔ نجی منصوبہ اور گفتگو نجی رہتے ہیں۔')),
            value: guardian.safeToContactConfirmed,
            onChanged: _busy ? null : _guardianSafety),
        if (guardian.safeToContactConfirmed)
          CheckboxListTile(
              key: const ValueKey('crisis-notify-checkbox'),
              contentPadding: EdgeInsets.zero,
              title: Text(_t('Also request a guardian notice now',
                  'اب سرپرست کو بھی اطلاع کی درخواست')),
              value: _notify,
              onChanged: _busy || _requestId != null
                  ? null
                  : (value) => setState(() => _notify = value == true)),
      ],
      const SizedBox(height: 10),
      _action(
          _requestId != null
              ? _t('Retry the same request', 'اسی درخواست کی دوبارہ کوشش')
              : _notify
                  ? _t('Request guardian notice', 'سرپرست کو اطلاع کی درخواست')
                  : _t('Record help request privately',
                      'نجی مدد کی درخواست درج کریں'),
          Icons.shield_outlined,
          _online && !_busy ? _requestHelp : null,
          key: const ValueKey('crisis-request-help')),
      if (_requestId != null)
        TextButton(
            onPressed: _busy ? null : () => setState(() => _requestId = null),
            child: Text(_t('Discard retry · cannot recall a sent notice',
                'کوشش ہٹائیں · بھیجا پیغام واپس نہیں ہوتا'))),
      if (_event != null) ...[
        const Divider(),
        Text(_t('Open support record', 'مدد کا کھلا ریکارڈ'),
            style: Theme.of(context).textTheme.titleMedium),
        Text(_delivery(_event!)),
        Text(_t(
            'Acknowledging or closing this record does not confirm safety or contact anyone.',
            'ریکارڈ دیکھنے یا بند کرنے سے حفاظت کی تصدیق یا کسی سے رابطہ نہیں ہوتا۔')),
        if (_event!.status != 'acknowledged')
          OutlinedButton(
              onPressed:
                  _busy || !_online ? null : () => _updateEvent('acknowledged'),
              child: Text(
                  _t('I have seen this record', 'میں نے یہ ریکارڈ دیکھا ہے'))),
        TextButton(
            onPressed: _busy || !_online ? null : _closeEvent,
            child: Text(_t('Close this record', 'یہ ریکارڈ بند کریں'))),
      ],
      Wrap(spacing: 8, runSpacing: 8, children: [
        TextButton(
            onPressed: _loading || _busy ? null : _loadPrivate,
            child: Text(_t('Refresh support', 'مدد تازہ کریں'))),
        TextButton(
            onPressed: _online && !_busy
                ? () {
                    final accountId = widget.accountId!;
                    final service = _service;
                    Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => CrisisAccountGuard(
                            accountId: accountId,
                            child: _CrisisHistoryScreen(service: service))));
                  }
                : null,
            child: Text(_t('My support records', 'میرے مدد کے ریکارڈ'))),
      ]),
    ]);
  }

  Widget _planPanel() => _card([
        Text(
            _t('My short safety plan · optional',
                'مختصر حفاظتی منصوبہ · اختیاری'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (_download != null && !_online)
          Text(_t(
              'Downloaded private copy. Contacts may be out of date. Use only if still safe; permissions cannot be rechecked offline.',
              'ڈاؤن لوڈ شدہ نجی نقل۔ رابطے پرانے ہو سکتے ہیں۔ صرف محفوظ ہونے پر استعمال کریں؛ آف لائن اجازت کی تصدیق نہیں ہوتی۔')),
        if (_plan.isEmpty)
          Text(_t(
              'No form is required for help. When ready, save one coping step and one safe contact.',
              'مدد کے لیے فارم ضروری نہیں۔ تیار ہونے پر ایک قدم اور ایک محفوظ رابطہ درج کریں۔')),
        if (_plan.copingStep.isNotEmpty) Text(_plan.copingStep),
        if (_plan.supportPersonName.isNotEmpty) Text(_plan.supportPersonName),
        if (_plan.supportPhone.isNotEmpty)
          SelectableText(_plan.supportPhone, textDirection: TextDirection.ltr),
        const SizedBox(height: 10),
        OutlinedButton.icon(
            key: const ValueKey('crisis-edit-plan'),
            onPressed: !_online || _busy
                ? null
                : () {
                    final generation = _generation;
                    final accountId = widget.accountId!;
                    final plan = _plan;
                    final guardian = _guardian;
                    Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => CrisisAccountGuard(
                        accountId: accountId,
                        child: CrisisPlanEditor(
                          plan: plan,
                          guardian: guardian,
                          onSave: (plan) => _savePlan(plan,
                              expectedGeneration: generation,
                              expectedAccountId: accountId),
                        ),
                      ),
                    ));
                  },
            icon: const Icon(Icons.edit_outlined),
            label: Text(_t('Edit my optional plan', 'اختیاری منصوبہ بدلیں'))),
        if (_cache.available && !_plan.isEmpty)
          SwitchListTile(
              key: const ValueKey('crisis-download-plan'),
              contentPadding: EdgeInsets.zero,
              title: Text(_t(
                  'Keep encrypted offline copy', 'رمز شدہ آف لائن نقل رکھیں')),
              subtitle: Text(_t('This phone · 30 days · no automatic uploads',
                  'یہ فون · ۳۰ دن · خودکار اپ لوڈ نہیں')),
              value: _download != null,
              onChanged: _busy || (!_online && _download == null)
                  ? null
                  : _downloadPlan),
        if (!_plan.isEmpty)
          TextButton(
              onPressed: _online && !_busy ? _deletePlan : null,
              child: Text(_t('Delete server plan and download',
                  'سرور منصوبہ اور ڈاؤن لوڈ مٹائیں'))),
      ]);
}

class _CrisisHistoryScreen extends StatefulWidget {
  const _CrisisHistoryScreen({required this.service});
  final CrisisService service;
  @override
  State<_CrisisHistoryScreen> createState() => _CrisisHistoryScreenState();
}

class _CrisisHistoryScreenState extends State<_CrisisHistoryScreen> {
  final _events = <CrisisEvent>[];
  String? _cursor;
  bool _busy = false, _failed = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_busy || _events.length >= 100) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final history = await widget.service.history(before: _cursor);
      if (!mounted) return;
      setState(() {
        final ids = _events.map((event) => event.id).toSet();
        _events
            .addAll(history.events.where((event) => !ids.contains(event.id)));
        _cursor = history.nextCursor;
      });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    return Scaffold(
        appBar: AppBar(
            title: Text(ur ? 'میرے مدد کے ریکارڈ' : 'My support records')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(20), children: [
          Text(ur
              ? 'واقعات کا ریکارڈ، طبی صحت یابی کی تصدیق نہیں۔'
              : 'An event record—not confirmation of clinical recovery.'),
          for (final event in _events)
            Card(
                child: ListTile(
                    title: Text(event.triggeredAt
                        .toLocal()
                        .toIso8601String()
                        .substring(0, 10)),
                    subtitle: Text(ur
                        ? (event.isClosed
                            ? 'آپ نے ریکارڈ بند کیا'
                            : 'مدد کا ریکارڈ کھلا ہے')
                        : (event.isClosed
                            ? 'Record closed by you'
                            : 'Support record open')))),
          if (_failed)
            Text(ur ? 'ریکارڈ نہیں کھل سکے۔' : 'Records could not load.'),
          if (_busy) const Center(child: CircularProgressIndicator()),
          if (!_busy && !_failed && _events.isEmpty)
            Text(ur ? 'ابھی کوئی ریکارڈ نہیں۔' : 'No records yet.'),
          if (!_busy && (_failed || _cursor != null) && _events.length < 100)
            OutlinedButton(
                onPressed: _load,
                child: Text(ur ? 'مزید / دوبارہ کوشش' : 'Load more / retry')),
        ])));
  }
}
