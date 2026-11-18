import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/language_provider.dart';
import '../../services/community_service.dart';
import 'community_account_scope.dart';
import 'community_widgets.dart';

/// Administrator-only, community aliases only; never displays clinical data.
class CommunityMembers extends StatelessWidget {
  const CommunityMembers({super.key, required this.service});
  final CommunityService service;
  @override
  Widget build(BuildContext context) => CommunityAccountScope(
      builder: (_, owner) => _MembersView(service: service, accountId: owner));
}

class _MembersView extends StatefulWidget {
  const _MembersView({required this.service, required this.accountId});
  final CommunityService service;
  final String? accountId;
  @override
  State<_MembersView> createState() => _MembersViewState();
}

class _MembersViewState extends State<_MembersView> {
  final _members = <Map<String, dynamic>>[];
  String? _cursor, _error;
  bool _loading = false;
  int _generation = 0;
  bool get _current =>
      mounted && CommunityAccountScope.current(context, widget.accountId);
  bool get ur => context.read<LanguageProvider>().isUrdu;
  String tr(String en, String other) => ur ? other : en;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (!_current || (more && (_loading || _cursor == null))) return;
    final generation = ++_generation;
    final cursor = more ? _cursor : null;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _members.clear();
        _cursor = null;
      }
    });
    try {
      final page = await widget.service.members(cursor: cursor);
      if (!_current || generation != _generation) return;
      final items = (page['items'] as List)
          .map((v) => Map<String, dynamic>.from(v as Map));
      setState(() {
        final ids = _members.map((v) => v['id']).toSet();
        _members.addAll(items
            .where((v) => !ids.contains(v['id']))
            .take(200 - _members.length));
        _cursor =
            _members.length >= 200 ? null : page['next_cursor'] as String?;
      });
    } catch (error) {
      if (_current && generation == _generation) {
        setState(() {
          _error = error.toString();
          if (error is CommunityException && error.unavailable) {
            _members.clear();
            _cursor = null;
          }
        });
      }
    } finally {
      if (_current && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _change(Map<String, dynamic> member) async {
    if (!_current || _loading) return;
    final restore = member['suspended'] == true;
    final reason = await showDialog<String>(
        context: context,
        builder: (_) => CommunityAccountScope(
            accountId: widget.accountId,
            builder: (_, __) => CommunityReasonDialog(
                title: tr(restore ? 'Restore member' : 'Suspend member',
                    restore ? 'رکن بحال کریں' : 'رکن معطل کریں'))));
    if (!_current || reason == null) return;
    setState(() => _loading = true);
    try {
      await widget.service.suspend(member['id'] as String, !restore, reason);
      if (_current) await _load();
    } catch (error) {
      if (_current) {
        setState(() {
          _error = error.toString();
          _loading = false;
          if (error is CommunityException && error.unavailable) {
            _members.clear();
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    return Scaffold(
        appBar: AppBar(
            title: Text(tr('Manage members', 'اراکین کی نگرانی'),
                maxLines: 2, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                  onPressed: _loading ? null : () => _load(),
                  tooltip: tr('Refresh', 'تازہ کریں'),
                  icon: const Icon(Icons.refresh))
            ]),
        body: SafeArea(
            child: RefreshIndicator(
                onRefresh: () => _load(),
                child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(tr(
                          'Use a documented reason for every action. These are community aliases, not clinical records.',
                          'ہر عمل کی وجہ درج کریں۔ یہ حلقے کے نام ہیں، طبی ریکارڈ نہیں۔')),
                      if (_loading) const LinearProgressIndicator(),
                      if (_error != null)
                        CommunityNotice(
                            text: _error!,
                            action: TextButton(
                                onPressed: () => _load(),
                                child: Text(tr('Retry', 'دوبارہ کوشش')))),
                      for (final member in _members)
                        Card(
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(member['alias'] as String),
                                      Text(member['suspended'] == true
                                          ? tr('Suspended', 'معطل')
                                          : tr('Active', 'فعال')),
                                      OutlinedButton(
                                          onPressed: _loading
                                              ? null
                                              : () => _change(member),
                                          child: Text(
                                              member['suspended'] == true
                                                  ? tr('Restore member',
                                                      'رکن بحال کریں')
                                                  : tr('Suspend member',
                                                      'رکن معطل کریں'))),
                                    ]))),
                      if (!_loading && _members.isEmpty && _error == null)
                        CommunityNotice(
                            text: tr('No members yet.', 'ابھی کوئی رکن نہیں۔')),
                      if (_cursor != null)
                        OutlinedButton(
                            onPressed:
                                _loading ? null : () => _load(more: true),
                            child: Text(tr('Load more', 'مزید دیکھیں'))),
                    ]))));
  }
}
