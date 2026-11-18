import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/care_directory.dart';
import '../../providers/language_provider.dart';
import '../../services/care_directory_service.dart';
import 'crisis_links.dart';

/// Low-input public support. Urgent calling stays available while loading,
/// signed out, offline, and when optional location permission is denied.
class CareDirectoryScreen extends StatefulWidget {
  const CareDirectoryScreen({
    super.key,
    this.service,
    this.location,
    this.links,
    this.calls,
    this.onUrgentHelp,
  });
  final CareDirectoryService? service;
  final CareLocationService? location;
  final CareDirectoryLinks? links;
  final CrisisLinks? calls;
  final VoidCallback? onUrgentHelp;

  @override
  State<CareDirectoryScreen> createState() => _CareDirectoryScreenState();
}

class _CareDirectoryScreenState extends State<CareDirectoryScreen>
    with WidgetsBindingObserver {
  late final _service = widget.service ?? CareDirectoryService();
  late final _location = widget.location ?? CareLocationService();
  late final _links = widget.links ?? CareDirectoryLinks();
  late final _calls = widget.calls ?? CrisisLinks();
  CareDirectorySnapshot? _snapshot;
  CarePosition? _position;
  Timer? _positionExpiry;
  String? _city;
  bool _loading = true, _locating = false, _refreshing = false;
  int _locationGeneration = 0;
  bool get _ur => context.read<LanguageProvider>().isUrdu;
  String _t(String en, String ur) => _ur ? ur : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    _locationGeneration++;
    _position = null;
    _positionExpiry?.cancel();
    unawaited(_location.cancel());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive) {
      return;
    }
    _locationGeneration++;
    _positionExpiry?.cancel();
    unawaited(_location.cancel());
    if (mounted) {
      setState(() {
        _position = null;
        _locating = false;
      });
    }
  }

  Future<void> _load() async {
    try {
      final offline = await _service.offline();
      if (mounted) setState(() => _snapshot = offline);
    } catch (_) {
      // The dialer remains available even when the public asset is damaged.
    }
    if (!mounted) return;
    setState(() => _loading = false);
    await _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    if (mounted) setState(() => _refreshing = true);
    try {
      final latest = await _service.refresh();
      if (mounted) {
        setState(() {
          _snapshot = latest;
          if (_city != null &&
              !latest.directory.facilities
                  .any((entry) => entry.cityEn == _city)) {
            _city = null;
          }
        });
      }
    } catch (_) {
      // Offline/source-check dates stay visible; never claim live availability.
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _notice(String en, String ur) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_t(en, ur)), duration: const Duration(seconds: 6)));
  }

  Future<bool> _confirm(
      String en, String ur, String bodyEn, String bodyUr) async {
    final urdu = _ur;
    return await showDialog<bool>(
          context: context,
          builder: (dialog) => Directionality(
            textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
            child: AlertDialog(
              scrollable: true,
              title: Text(urdu ? ur : en),
              content: Text(urdu ? bodyUr : bodyEn),
              actions: [
                TextButton(
                    onPressed: () => Navigator.of(dialog).pop(false),
                    child: Text(urdu ? 'ابھی نہیں' : 'Not now')),
                FilledButton(
                    onPressed: () => Navigator.of(dialog).pop(true),
                    child: Text(urdu ? 'جاری رکھیں' : 'Continue')),
              ],
            ),
          ),
        ) ==
        true;
  }

  Future<void> _locate() async {
    if (_locating) return;
    final consent = await _confirm(
        'Use approximate location once?',
        'ایک بار اندازاً مقام استعمال کریں؟',
        'Your phone may ask for permission. HerCare uses this foreground location only on this page to order institutions with source-checked coordinates. It is not saved, uploaded or used in the background. You can choose a city instead.',
        'فون اجازت مانگ سکتا ہے۔ ہرکیئر صرف اس صفحے پر ماخذ سے جانچے گئے اداروں کو ترتیب دینے کے لیے اندازاً مقام استعمال کرے گا۔ مقام محفوظ، اپ لوڈ یا پس منظر میں استعمال نہیں ہوگا۔ آپ شہر بھی منتخب کر سکتی ہیں۔');
    if (!consent || !mounted) return;
    final generation = ++_locationGeneration;
    setState(() => _locating = true);
    try {
      final position = await _location.current();
      if (!mounted || generation != _locationGeneration) return;
      setState(() {
        _position = position;
        _locating = false;
      });
      _positionExpiry?.cancel();
      if (position != null) {
        _positionExpiry = Timer(const Duration(minutes: 5), () {
          if (mounted) {
            unawaited(_location.cancel());
            setState(() => _position = null);
          }
        });
      }
      if (position == null) {
        unawaited(_location.cancel());
        _notice('Location unavailable. Choose a city or open Maps instead.',
            'مقام دستیاب نہیں۔ شہر منتخب کریں یا نقشہ کھولیں۔');
      }
    } catch (_) {
      if (!mounted || generation != _locationGeneration) return;
      setState(() => _locating = false);
      unawaited(_location.cancel());
      _notice('Location unavailable. Choose a city or open Maps instead.',
          'مقام دستیاب نہیں۔ شہر منتخب کریں یا نقشہ کھولیں۔');
    }
  }

  Future<void> _chooseCity() async {
    final entries = _snapshot?.directory.facilities;
    if (entries == null) return;
    final cities = <String, String>{};
    for (final entry in entries) {
      cities[entry.cityEn] = entry.city(_ur);
    }
    final choices = cities.keys.toList()..sort();
    final urdu = _ur;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => Directionality(
        textDirection: urdu ? TextDirection.rtl : TextDirection.ltr,
        child: SafeArea(
          child: FractionallySizedBox(
            heightFactor: .8,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                    urdu
                        ? 'اختیاری: شہر منتخب کریں'
                        : 'Optional: choose a city',
                    style: Theme.of(sheet).textTheme.titleLarge),
                const SizedBox(height: 12),
                ListTile(
                    key: const ValueKey('care-city-all'),
                    title:
                        Text(urdu ? 'تمام درج شدہ شہر' : 'All listed cities'),
                    onTap: () => Navigator.of(sheet).pop('')),
                for (final city in choices)
                  ListTile(
                      key: ValueKey('care-city-$city'),
                      title: Text(cities[city]!),
                      selected: city == _city,
                      onTap: () => Navigator.of(sheet).pop(city)),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted && chosen != null) {
      setState(() => _city = chosen.isEmpty ? null : chosen);
    }
  }

  Future<void> _call(CareFacility facility) async {
    try {
      if (!await _calls.call(facility.phone)) {
        _notice('Could not open the dialer. Use the displayed phone number.',
            'ڈائلر نہیں کھلا۔ درج شدہ فون نمبر استعمال کریں۔');
      }
    } catch (_) {
      _notice('Could not open the dialer. Use the displayed phone number.',
          'ڈائلر نہیں کھلا۔ درج شدہ فون نمبر استعمال کریں۔');
    }
  }

  Future<void> _maps(CareFacility facility) async {
    if (!await _confirm(
            'Open external Maps?',
            'بیرونی نقشہ کھولیں؟',
            'Only this institution’s public name and address are sent to Maps—not your HerCare location or health information. Maps may request its own location access or keep its own history. Check directions and opening hours yourself; this is not a guaranteed emergency service.',
            'نقشے کو صرف ادارے کا عوامی نام اور پتہ دیا جائے گا، ہرکیئر کا مقام یا صحت کی معلومات نہیں۔ نقشہ اپنی مقام کی اجازت یا ہسٹری استعمال کر سکتا ہے۔ راستہ اور اوقات خود جانچیں؛ یہ ہنگامی خدمت کی ضمانت نہیں۔') ||
        !mounted) {
      return;
    }
    try {
      if (!await _links.maps(facility)) {
        _notice('Could not open Maps. Use the displayed address.',
            'نقشہ نہیں کھلا۔ درج شدہ پتہ استعمال کریں۔');
      }
    } catch (_) {
      _notice('Could not open Maps. Use the displayed address.',
          'نقشہ نہیں کھلا۔ درج شدہ پتہ استعمال کریں۔');
    }
  }

  Future<void> _source(Uri uri) async {
    if (!await _confirm(
            'Open official source?',
            'سرکاری ماخذ کھولیں؟',
            'This institution’s website opens outside HerCare. Do not enter private health information unless you understand its privacy policy. A published listing does not confirm today’s availability.',
            'ادارے کی ویب سائٹ ہرکیئر سے باہر کھلے گی۔ نجی معلومات دینے سے پہلے اس کی رازداری کی پالیسی سمجھیں۔ درج شدہ معلومات آج کی دستیابی کی ضمانت نہیں۔') ||
        !mounted) {
      return;
    }
    try {
      if (!await _links.source(uri)) {
        _notice('Could not open the official source.', 'ماخذ نہیں کھلا۔');
      }
    } catch (_) {
      _notice('Could not open the official source.', 'ماخذ نہیں کھلا۔');
    }
  }

  Future<void> _urgent() async {
    if (widget.onUrgentHelp != null) {
      try {
        widget.onUrgentHelp!();
        return;
      } catch (_) {
        // A replaced source route must not make urgent calling unusable.
      }
    }
    try {
      if (!await _calls.openDialer()) {
        _notice('Open your phone app and call your local emergency number.',
            'فون ایپ کھول کر اپنے علاقے کے ہنگامی نمبر پر کال کریں۔');
      }
    } catch (_) {
      _notice('Open your phone app and call your local emergency number.',
          'فون ایپ کھول کر اپنے علاقے کے ہنگامی نمبر پر کال کریں۔');
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final directory = _snapshot?.directory;
    final directoryReview = directory?.reviewStatus(DateTime.now().toUtc());
    final entries = directory?.listed(city: _city, position: _position) ?? [];
    return Directionality(
      textDirection: _ur ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: context.hcBg,
        appBar: AppBar(
          backgroundColor: context.hcBg,
          toolbarHeight: 76,
          title: Text(_t('Find care', 'طبی مدد تلاش کریں'),
              maxLines: 2, overflow: TextOverflow.ellipsis),
          actions: [
            TextButton(
                onPressed: context.read<LanguageProvider>().toggleLocale,
                child: Text(_ur ? 'English' : 'اردو')),
          ],
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              FilledButton(
                key: const ValueKey('care-urgent'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    padding: const EdgeInsets.all(16)),
                onPressed: _urgent,
                child: Text(
                  _t('Immediate danger? Use urgent help',
                      'فوری خطرہ؟ ہنگامی مدد لیں'),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 12),
              Text(_t(
                  'Institutions checked against their official sources. Not a “best doctor” ranking, clinical endorsement or live appointment service. Call first to ask about mental-health care, hours and fees.',
                  'اداروں کی معلومات ان کے سرکاری ذرائع سے جانچی گئی ہیں۔ یہ بہترین ڈاکٹر کی درجہ بندی، طبی توثیق یا براہ راست اپائنٹمنٹ کی خدمت نہیں۔ ذہنی صحت کی سہولت، اوقات اور فیس کے لیے پہلے کال کریں۔')),
              if (_loading) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ] else if (directory == null) ...[
                const SizedBox(height: 16),
                Text(_t(
                    'The directory is unavailable. Urgent calling still works.',
                    'فہرست دستیاب نہیں۔ ہنگامی کال پھر بھی استعمال کی جا سکتی ہے۔')),
              ],
              if (directory != null) ...[
                const SizedBox(height: 16),
                Text(directory.notice(_ur)),
                if (directoryReview != 'current') ...[
                  const SizedBox(height: 8),
                  Text(_t(
                      directoryReview == 'date_unconfirmed'
                          ? 'Directory source-check dates are unconfirmed. Confirm details with the institution before travelling.'
                          : 'Directory review is overdue. Information may have changed; confirm details by phone.',
                      directoryReview == 'date_unconfirmed'
                          ? 'فہرست کے ماخذ کی جانچ کی تاریخیں غیر مصدقہ ہیں۔ سفر سے پہلے ادارے سے معلومات کی تصدیق کریں۔'
                          : 'فہرست کی دوبارہ جانچ ضروری ہے۔ معلومات بدل سکتی ہیں؛ فون سے تصدیق کریں۔')),
                ],
                const SizedBox(height: 12),
                Text(
                    _t(
                        _snapshot!.downloaded
                            ? 'Downloaded public directory. Individual source-check dates are shown below.'
                            : 'Offline-ready public directory included with the app. Source-check dates are shown below.',
                        _snapshot!.downloaded
                            ? 'ڈاؤن لوڈ کردہ عوامی فہرست۔ ہر ماخذ کی جانچ کی تاریخ نیچے درج ہے۔'
                            : 'ایپ میں شامل آف لائن عوامی فہرست۔ ماخذ کی جانچ کی تاریخیں نیچے درج ہیں۔'),
                    style: TextStyle(color: context.hcTextSecondary)),
                const SizedBox(height: 12),
                OutlinedButton(
                    key: const ValueKey('care-choose-city'),
                    onPressed: _chooseCity,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                          _city == null
                              ? _t('Choose a city (optional)',
                                  'شہر منتخب کریں (اختیاری)')
                              : entries.isEmpty
                                  ? _city!
                                  : entries.first.city(_ur),
                          textAlign: TextAlign.center),
                    )),
                if (directory.facilities
                    .any((entry) => entry.hasCoordinates)) ...[
                  const SizedBox(height: 8),
                  OutlinedButton(
                      key: const ValueKey('care-locate'),
                      onPressed: _locating ? null : _locate,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                            _t(
                                _locating
                                    ? 'Getting one approximate location…'
                                    : 'Order by approximate distance (optional)',
                                _locating
                                    ? 'اندازاً مقام معلوم کیا جا رہا ہے…'
                                    : 'اندازاً فاصلے سے ترتیب دیں (اختیاری)'),
                            textAlign: TextAlign.center),
                      )),
                ],
                if (_position != null) ...[
                  const SizedBox(height: 8),
                  Text(_t(
                      'Nearest listed map points by approximate straight-line distance only—not an entrance or travel time. Location accuracy: ±${(_position!.accuracyMeters / 1000).toStringAsFixed(1)} km. Missing-coordinate institutions cannot be ranked; this is not a complete directory.',
                      'صرف نقشے کے درج شدہ نقاط تک اندازاً سیدھا فاصلہ؛ یہ داخلی راستہ یا سفر کا وقت نہیں۔ مقام کی درستگی: ±${(_position!.accuracyMeters / 1000).toStringAsFixed(1)} کلومیٹر۔ جن اداروں کے نقاط نہیں ہیں ان کی درجہ بندی ممکن نہیں؛ یہ مکمل فہرست نہیں۔')),
                  TextButton(
                      key: const ValueKey('care-clear-location'),
                      onPressed: () {
                        _locationGeneration++;
                        _positionExpiry?.cancel();
                        unawaited(_location.cancel());
                        setState(() => _position = null);
                      },
                      child: Text(_t('Clear location', 'مقام ختم کریں'))),
                ],
                const SizedBox(height: 8),
                for (final facility in entries) _facilityCard(facility),
              ],
              const SizedBox(height: 12),
              TextButton(
                  key: const ValueKey('care-refresh'),
                  onPressed: _refreshing ? null : _refresh,
                  child: Text(_t(
                      _refreshing
                          ? 'Checking public directory…'
                          : 'Check directory updates',
                      _refreshing
                          ? 'عوامی فہرست جانچی جا رہی ہے…'
                          : 'فہرست کی تازہ معلومات دیکھیں'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _facilityCard(CareFacility facility) {
    final distance = _position == null ? null : facility.distanceKm(_position!);
    final checked = facility.checkedOn.toIso8601String().substring(0, 10);
    final due = facility.reviewDueOn.toIso8601String().substring(0, 10);
    final reviewStatus = facility.reviewStatus(DateTime.now().toUtc());
    return Card(
      key: ValueKey('care-facility-${facility.id}'),
      color: context.hcSurface,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(facility.name(_ur),
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(facility.city(_ur)),
            const SizedBox(height: 8),
            Text(facility.service(_ur)),
            const SizedBox(height: 8),
            Text(facility.address(_ur)),
            const SizedBox(height: 8),
            Directionality(
                textDirection: TextDirection.ltr,
                child: SelectableText(facility.phone)),
            if (distance != null) ...[
              const SizedBox(height: 8),
              Text(_t(
                  'Approximately ${distance < 1 ? '<1' : distance.ceil()} km to published map point (straight line)',
                  'نقشے کے شائع شدہ نقطے تک اندازاً ${distance < 1 ? '<1' : distance.ceil()} کلومیٹر سیدھا فاصلہ')),
              if (facility.coordinateKind == 'official_map_view_center')
                Text(_t('Official map-view centre, not a verified entrance.',
                    'سرکاری نقشے کا مرکزی نقطہ؛ تصدیق شدہ داخلی راستہ نہیں۔')),
            ] else if (_position != null) ...[
              const SizedBox(height: 8),
              Text(_t('No source-checked coordinates; distance not shown.',
                  'جانچے گئے نقاط دستیاب نہیں؛ فاصلہ نہیں دکھایا گیا۔')),
            ],
            const SizedBox(height: 8),
            Text(
                _t('Source checked: $checked · Review due: $due',
                    'ماخذ جانچا گیا: $checked · اگلی جانچ: $due'),
                style: TextStyle(color: context.hcTextSecondary)),
            if (reviewStatus != 'current') ...[
              const SizedBox(height: 8),
              Text(
                  _t(
                      reviewStatus == 'date_unconfirmed'
                          ? 'Source-check date is in the future or unconfirmed. Confirm details by phone.'
                          : 'Review overdue—details may have changed. Confirm by phone.',
                      reviewStatus == 'date_unconfirmed'
                          ? 'ماخذ کی جانچ کی تاریخ مستقبل کی یا غیر مصدقہ ہے۔ فون سے معلومات کی تصدیق کریں۔'
                          : 'دوبارہ جانچ ضروری ہے—معلومات بدل سکتی ہیں۔ فون سے تصدیق کریں۔'),
                  style: TextStyle(color: context.hcTextPrimary)),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
                key: ValueKey('care-call-${facility.id}'),
                onPressed: () => _call(facility),
                child: Text(
                    _t('Open institution dialer',
                        'ادارے کا نمبر ڈائلر میں کھولیں'),
                    textAlign: TextAlign.center)),
            const SizedBox(height: 8),
            OutlinedButton(
                key: ValueKey('care-map-${facility.id}'),
                onPressed: () => _maps(facility),
                child: Text(_t('View address in Maps', 'نقشے پر پتہ دیکھیں'),
                    textAlign: TextAlign.center)),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(_t('Official sources', 'سرکاری ذرائع')),
              children: [
                for (var index = 0; index < facility.sourceUrls.length; index++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(facility.sourceUrls[index].toString(),
                            textDirection: TextDirection.ltr,
                            style: TextStyle(color: context.hcTextSecondary)),
                        TextButton(
                            key: ValueKey('care-source-${facility.id}-$index'),
                            onPressed: () =>
                                _source(facility.sourceUrls[index]),
                            child: Text(_t('Open source ${index + 1}',
                                'ماخذ ${index + 1} کھولیں'))),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
