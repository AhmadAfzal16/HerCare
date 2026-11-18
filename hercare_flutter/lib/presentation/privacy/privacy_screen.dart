import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../providers/auth_provider.dart';
import '../../providers/guardian_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/language_provider.dart';
import '../../services/privacy_service.dart';

class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key, this.service});
  final PrivacyService? service;
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  late final _service = widget.service ?? PrivacyService();
  String? _owner;
  PrivacySettings? _settings;
  bool _busy = false, _failed = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthProvider>();
    final id = auth.isAuthenticated &&
            auth.user?.isMother == true &&
            auth.user?.onboardingComplete == true
        ? auth.user?.id
        : null;
    if (id == _owner) return;
    _owner = id;
    _generation++;
    _settings = null;
    _failed = false;
    _busy = false;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _owner == id) _load();
      });
    }
  }

  bool _current(int generation) => mounted && generation == _generation;

  Future<void> _load() async {
    final id = _owner;
    if (id == null || _busy) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final settings = await _service.read(id);
      if (_current(generation)) setState(() => _settings = settings);
    } catch (_) {
      if (_current(generation)) {
        setState(() {
          _failed = true;
          _settings = null;
        });
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  Future<void> _change(String field, bool value) async {
    final id = _owner;
    if (id == null || _busy || _settings == null) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      final settings = await _service.update(id, field, value);
      if (!mounted || !_current(generation)) return;
      setState(() => _settings = settings);
      if (!settings.guardian) {
        context.read<GuardianProvider?>()?.reset();
        final chat = context.read<ChatProvider?>();
        chat?.bindAccount(null);
        chat?.bindAccount(id, role: 'mother');
      }
    } catch (_) {
      // A lost response may follow a committed change. Show no assumed value;
      // Retry reads the server rather than sending the change a second time.
      if (_current(generation)) {
        setState(() {
          _failed = true;
          _settings = null;
        });
      }
    } finally {
      if (_current(generation)) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    String tr(String en, String urdu) => ur ? urdu : en;
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(
          title: Text(tr('My Data & Privacy', 'میرا ڈیٹا اور پرائیویسی'))),
      body: SafeArea(
          child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(tr(
              'Your private journal and Hum-Raaz conversations are not shared with your guardian.',
              'آپ کا نجی جریدہ اور ہم راز کی گفتگو سرپرست کے ساتھ شیئر نہیں ہوتی۔')),
          const SizedBox(height: 16),
          if (_owner == null)
            Text(tr(
                'Mothers manage their own sharing permissions. Guardian access follows the linked mother’s choices.',
                'مائیں اپنی شیئرنگ کی اجازت خود منتخب کرتی ہیں۔ سرپرست کی رسائی انہی اجازتوں کے مطابق ہے۔'))
          else ...[
            if (_busy) const LinearProgressIndicator(),
            if (_failed) ...[
              Text(tr(
                  'Could not confirm your settings. Reconnect and retry before changing them.',
                  'ترتیبات کی تصدیق نہیں ہو سکی۔ انٹرنیٹ سے جڑ کر دوبارہ کوشش کریں۔')),
              TextButton.icon(
                  onPressed: _busy ? null : _load,
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Retry', 'دوبارہ کوشش'))),
            ],
            if (settings != null) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monitor_heart_outlined),
                title: Text(tr('Basic monitoring', 'بنیادی نگرانی')),
                subtitle: Text(settings.basic
                    ? tr(
                        'Enabled during onboarding for mood, sleep and screening.',
                        'موڈ، نیند اور جانچ کے لیے ابتدائی رضامندی دی گئی ہے۔')
                    : tr('Monitoring permission is off.',
                        'نگرانی کی اجازت بند ہے۔')),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(
                    tr('Share with my guardian', 'میرے سرپرست سے شیئر کریں')),
                subtitle: Text(tr(
                    'Aggregate reports and alerts, and access to your linked guardian chat.',
                    'مجموعی رپورٹس، اطلاعات اور منسلک سرپرست سے چیٹ کی رسائی۔')),
                value: settings.guardian,
                onChanged: _busy ? null : (v) => _change('consent_tier2', v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title:
                    Text(tr('Phone usage analysis', 'فون کے استعمال کا تجزیہ')),
                subtitle: Text(tr(
                    'Optional Android usage and notification analysis. Device access is managed separately.',
                    'اینڈرائیڈ کے استعمال اور اطلاعات کا اختیاری تجزیہ۔ فون کی اجازت الگ سے دیں۔')),
                value: settings.telemetry,
                onChanged: _busy ? null : (v) => _change('consent_tier3', v),
              ),
            ],
          ],
          const Divider(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.family_restroom_outlined),
            title: Text(tr('Guardian connection', 'سرپرست سے رابطہ')),
            subtitle: Text(
                tr('View or disconnect your link', 'رابطہ دیکھیں یا ختم کریں')),
            onTap: () => context.push(AppRoutes.guardianLink),
          ),
          if (_owner != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.phonelink_lock),
              title: Text(tr('Phone permissions', 'فون کی اجازتیں')),
              onTap: () => context.push(AppRoutes.digitalWellbeing),
            ),
          const SizedBox(height: 16),
          Text(tr(
              'Research participation is a separate optional choice. These switches do not enroll you in research.',
              'تحقیق میں شرکت الگ اور اختیاری انتخاب ہے۔ یہ اجازتیں آپ کو تحقیق میں شامل نہیں کرتیں۔')),
        ],
      )),
    );
  }
}
