import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/models/therapy_models.dart';
import '../../providers/language_provider.dart';
import '../../providers/therapy_provider.dart';

Future<void> showTherapySyncRecovery(BuildContext context) {
  final provider = context.read<TherapyProvider>();
  final owner = provider.accountId;
  return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _Recovery(provider: provider, owner: owner));
}

class _Recovery extends StatefulWidget {
  const _Recovery({required this.provider, required this.owner});
  final TherapyProvider provider;
  final String? owner;
  @override
  State<_Recovery> createState() => _RecoveryState();
}

class _RecoveryState extends State<_Recovery> {
  bool _busy = false;
  String? _message;
  bool get _own =>
      widget.owner != null &&
      widget.provider.canUseAccount &&
      widget.provider.accountId == widget.owner;

  Future<void> _act(String requestId, bool discard, bool urdu) async {
    if (_busy || !_own) return;
    if (discard) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(urdu
                    ? 'یہ ریکارڈ ہٹائیں؟'
                    : 'Discard this pending record?'),
                content: Text(urdu
                    ? 'صرف اس فون کا مسترد شدہ ریکارڈ ہٹے گا۔ سرور کی تاریخ نہیں مٹے گی۔ یہ مقامی ریکارڈ واپس نہیں آ سکے گا۔'
                    : 'Only this rejected phone record will be removed. Server history is unchanged. This local record cannot be recovered.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(urdu ? 'رہنے دیں' : 'Keep')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(urdu ? 'ہٹائیں' : 'Discard')),
                ],
              ));
      if (!mounted || !_own || confirmed != true) return;
    }
    setState(() {
      _busy = true;
      _message = null;
    });
    final success = discard
        ? await widget.provider
            .discardPending(requestId, expectedAccountId: widget.owner!)
        : await widget.provider
            .retryPending(requestId, expectedAccountId: widget.owner!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = !_own
          ? null
          : success
              ? (urdu
                  ? (discard
                      ? 'مقامی ریکارڈ ہٹ گیا۔ سرور کی تاریخ برقرار ہے۔'
                      : 'دوبارہ کوشش مکمل۔ نیچے موجود ریکارڈ کا جائزہ لیں۔')
                  : (discard
                      ? 'Pending phone record removed; server history is unchanged.'
                      : 'Retry finished. Review any remaining records below.'))
              : (urdu
                  ? 'کارروائی مکمل نہیں ہوئی۔ انٹرنیٹ اور رضامندی کا جائزہ لیں۔'
                  : 'Could not finish. Check your connection and consent.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final urdu = context.watch<LanguageProvider>().isUrdu;
    return AnimatedBuilder(
      animation: widget.provider,
      builder: (context, _) => PopScope(
        canPop: !_busy,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, 22, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
            children: [
              Text(urdu ? 'محفوظ ریکارڈ کا جائزہ' : 'Review pending records',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (!_own)
                Text(urdu
                    ? 'اکاؤنٹ بدل گیا ہے۔ یہ صفحہ بند کریں۔'
                    : 'Your account changed. Close this page.')
              else ...[
                Text(urdu
                    ? 'مسترد شدہ ریکارڈ خود بخود نہیں مٹتے۔ دوسرے درست ریکارڈ ہم آہنگ ہو سکتے ہیں۔'
                    : 'Rejected records are retained. Other valid records can still sync.'),
                if (_message != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(_message!)),
                if (widget.provider.pendingIssues.isEmpty)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 20),
                      child: Text(urdu
                          ? 'کوئی مسترد شدہ ریکارڈ باقی نہیں۔'
                          : 'No rejected records remain.')),
                ...widget.provider.pendingIssues.map((issue) {
                  final activity = TherapyCatalog.byId(issue.activityId);
                  final date = issue.completedAt
                      .toLocal()
                      .toIso8601String()
                      .split('T')
                      .first;
                  return Card(
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(urdu ? activity.titleUr : activity.title),
                              Text(date),
                              Text(urdu ? issue.reasonUr : issue.reason),
                              const SizedBox(height: 8),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                            _act(issue.requestId, false, urdu),
                                    child:
                                        Text(urdu ? 'دوبارہ کوشش' : 'Retry')),
                                TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () =>
                                            _act(issue.requestId, true, urdu),
                                    child: Text(urdu
                                        ? 'مقامی ریکارڈ ہٹائیں'
                                        : 'Discard phone record')),
                              ]),
                            ],
                          )));
                }),
              ],
              TextButton(
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  child: Text(urdu ? 'بند کریں' : 'Close')),
            ],
          ),
        ),
      ),
    );
  }
}
