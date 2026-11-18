import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/language_provider.dart';
import '../../data/models/community_models.dart';

const communityTopics = {
  'coping': ['Coping together', 'مل کر مقابلہ'],
  'recovery': ['Recovery stories', 'صحت یابی کی کہانیاں'],
  'family': ['Family & support', 'خاندان اور مدد'],
  'bonding': ['Baby bonding', 'بچے سے تعلق'],
  'medication': ['Medication experiences', 'ادویات کے تجربات'],
};
String communityTopic(String key, bool ur) =>
    communityTopics[key]?[ur ? 1 : 0] ?? key;

class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard(
      {super.key,
      required this.post,
      required this.urdu,
      this.onOpen,
      this.onAction,
      this.onReaction,
      this.busy = false,
      this.expanded = false});
  final CommunityPost post;
  final bool urdu, busy, expanded;
  final VoidCallback? onOpen;
  final ValueChanged<String>? onAction;
  final ValueChanged<String>? onReaction;
  String tr(String en, String ur) => urdu ? ur : en;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
        margin: const EdgeInsets.only(bottom: 14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              CircleAvatar(
                  backgroundColor: colors.secondaryContainer,
                  child: Icon(Icons.spa_outlined,
                      color: colors.onSecondaryContainer)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(post.alias,
                        style: Theme.of(context).textTheme.titleSmall),
                    Text(
                        MaterialLocalizations.of(context)
                            .formatShortDate(post.createdAt.toLocal()),
                        style: Theme.of(context).textTheme.bodySmall),
                  ])),
              if (onAction != null)
                PopupMenuButton<String>(
                    enabled: !busy,
                    onSelected: onAction,
                    itemBuilder: (_) => [
                          if (post.mine)
                            PopupMenuItem(
                                value: 'delete',
                                child: Text(tr('Delete', 'حذف کریں')))
                          else ...[
                            PopupMenuItem(
                                value: 'report',
                                child: Text(tr('Report content / member',
                                    'مواد یا رکن کی رپورٹ'))),
                            PopupMenuItem(
                                value: 'block',
                                child: Text(
                                    tr('Block member', 'رکن کو بلاک کریں'))),
                          ],
                        ]),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              Text(communityTopic(post.topic, urdu),
                  style: TextStyle(
                      color: colors.primary, fontWeight: FontWeight.w600)),
              if (post.expert)
                Text(tr('• Expert response', '• ماہر کا جواب'),
                    style: TextStyle(color: colors.primary)),
              if (post.parentId != null) Text(tr('• Reply', '• جواب')),
              if (post.status != 'published')
                Text(post.status == 'pending'
                    ? tr('• Awaiting review', '• جائزے کا منتظر')
                    : tr('• Removed by moderation', '• جائزے میں ہٹا دیا گیا')),
            ]),
            if (post.title.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(post.title, style: Theme.of(context).textTheme.titleMedium),
            ],
            const SizedBox(height: 8),
            Text(post.body,
                maxLines: expanded ? null : 6,
                overflow: expanded ? null : TextOverflow.ellipsis,
                textDirection: RegExp(r'[\u0600-\u06ff]').hasMatch(post.body)
                    ? TextDirection.rtl
                    : TextDirection.ltr),
            const SizedBox(height: 12),
            if (post.status == 'published' && onReaction != null)
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final entry in {
                  'heart': '💜',
                  'hug': '🤗',
                  'support': '🌷',
                  'solidarity': tr('You’re not alone', 'آپ اکیلی نہیں')
                }.entries)
                  FilterChip(
                      label: Text(
                          '${entry.value} ${post.reactions[entry.key] ?? 0}'),
                      selected: post.myReactions.contains(entry.key),
                      onSelected: busy ? null : (_) => onReaction!(entry.key)),
              ]),
            if (onOpen != null)
              Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: TextButton.icon(
                    onPressed: onOpen,
                    icon:
                        const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                    label: Text(
                        '${tr('Read discussion', 'گفتگو پڑھیں')} · ${post.comments}'),
                  )),
          ]),
        ));
  }
}

class CommunityReasonDialog extends StatefulWidget {
  const CommunityReasonDialog({super.key, required this.title});
  final String title;
  @override
  State<CommunityReasonDialog> createState() => _CommunityReasonDialogState();
}

class _CommunityReasonDialogState extends State<CommunityReasonDialog> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ur = context.watch<LanguageProvider>().isUrdu;
    return CommunityDialog(
        title: Text(widget.title),
        content: SingleChildScrollView(
            child: TextField(
                controller: _reason,
                minLines: 2,
                maxLines: 5,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    labelText: ur
                        ? 'وجہ (کم از کم تین حروف)'
                        : 'Reason (at least 3 characters)'))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(ur ? 'منسوخ' : 'Cancel')),
          FilledButton(
              onPressed: _reason.text.trim().length < 3
                  ? null
                  : () => Navigator.pop(context, _reason.text.trim()),
              child: Text(ur ? 'تصدیق' : 'Confirm')),
        ]);
  }
}

/// Title, inputs and actions all scroll when a keyboard or large font leaves
/// little height. Scrolling only AlertDialog.content cannot protect its header.
class CommunityDialog extends StatelessWidget {
  const CommunityDialog(
      {super.key,
      required this.title,
      required this.content,
      required this.actions});
  final Widget title, content;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 450),
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DefaultTextStyle(
                        style: Theme.of(context).textTheme.headlineSmall!,
                        child: title),
                    const SizedBox(height: 16),
                    content,
                    const SizedBox(height: 16),
                    Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions),
                  ]))));
}

class CommunityNotice extends StatelessWidget {
  const CommunityNotice({super.key, required this.text, this.action});
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(children: [
        const Icon(Icons.forum_outlined, size: 38),
        const SizedBox(height: 12),
        Text(text, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 12), action!],
      ]));
}
