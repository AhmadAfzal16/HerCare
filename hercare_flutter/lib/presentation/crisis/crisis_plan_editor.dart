import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/models/crisis_models.dart';
import '../../providers/language_provider.dart';

/// Three optional fields; no questionnaire or gate in front of urgent help.
class CrisisPlanEditor extends StatefulWidget {
  const CrisisPlanEditor({
    super.key,
    required this.plan,
    this.guardian,
    required this.onSave,
  });
  final CrisisPlan plan;
  final CrisisGuardian? guardian;
  final Future<bool> Function(CrisisPlan) onSave;

  @override
  State<CrisisPlanEditor> createState() => _CrisisPlanEditorState();
}

class _CrisisPlanEditorState extends State<CrisisPlanEditor> {
  final _form = GlobalKey<FormState>();
  late final _coping = TextEditingController(text: widget.plan.copingStep);
  late final _name = TextEditingController(text: widget.plan.supportPersonName);
  late final _phone = TextEditingController(text: widget.plan.supportPhone);
  bool _saving = false;

  @override
  void dispose() {
    _coping.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    return Scaffold(
      appBar: AppBar(
          title:
              Text(ur ? 'میرا مختصر حفاظتی منصوبہ' : 'My short safety plan')),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            Text(ur
                ? 'سب اختیاری ہے۔ اپنے لیے محفوظ شخص منتخب کریں، ضروری نہیں کہ وہ منسلک سرپرست ہو۔ یہ طبی حفاظتی منصوبے کا متبادل نہیں۔'
                : 'Everything is optional. Choose someone safe for you; they do not have to be your linked guardian. This is not a substitute for a clinician-supported safety plan.'),
            const SizedBox(height: 20),
            TextFormField(
              key: const ValueKey('crisis-plan-coping'),
              controller: _coping,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                  labelText: ur
                      ? 'ایک چیز جو میری مدد کرتی ہے'
                      : 'One thing that helps me',
                  hintText: ur
                      ? 'مثلاً کسی محفوظ شخص کے ساتھ بیٹھنا'
                      : 'For example, sit with someone safe'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('crisis-plan-name'),
              controller: _name,
              maxLength: 80,
              decoration: InputDecoration(
                  labelText:
                      ur ? 'قابل اعتماد شخص کا نام' : 'Trusted person’s name'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('crisis-plan-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              maxLength: 24,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ()-]'))
              ],
              validator: (value) {
                final normalized =
                    (value ?? '').replaceAll(RegExp(r'[\s()-]'), '');
                if (normalized.isNotEmpty &&
                    !RegExp(r'^\+?[0-9]{7,15}$').hasMatch(normalized)) {
                  return ur
                      ? 'درست فون نمبر درج کریں یا خالی چھوڑ دیں۔'
                      : 'Enter a valid phone number or leave it empty.';
                }
                return null;
              },
              decoration: InputDecoration(
                  labelText: ur ? 'اس شخص کا فون نمبر' : 'Their phone number'),
            ),
            if (widget.guardian != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving
                    ? null
                    : () {
                        _name.text = widget.guardian!.name;
                        _phone.text = widget.guardian!.phone;
                      },
                icon: const Icon(Icons.person_add_alt_1),
                label: Text(ur
                    ? 'اگر محفوظ ہے تو منسلک سرپرست استعمال کریں'
                    : 'Use linked guardian only if safe'),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const ValueKey('crisis-plan-save'),
              onPressed: _saving
                  ? null
                  : () async {
                      if (!_form.currentState!.validate()) return;
                      setState(() => _saving = true);
                      final saved = await widget.onSave(CrisisPlan(
                          version: widget.plan.version,
                          copingStep: _coping.text.trim(),
                          supportPersonName: _name.text.trim(),
                          supportPhone:
                              _phone.text.replaceAll(RegExp(r'[\s()-]'), '')));
                      if (!mounted || !context.mounted) return;
                      if (saved) {
                        Navigator.of(context).pop();
                      } else {
                        setState(() => _saving = false);
                      }
                    },
              child: Text(_saving
                  ? (ur ? 'محفوظ ہو رہا ہے…' : 'Saving…')
                  : (ur ? 'نجی منصوبہ محفوظ کریں' : 'Save private plan')),
            ),
          ]),
        ),
      ),
    );
  }
}
