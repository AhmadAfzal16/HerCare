import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/routing/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text_styles.dart';
import '../../core/theme/theme_ext.dart';
import '../../data/models/chat_models.dart';
import '../../providers/chat_provider.dart';
import '../../providers/language_provider.dart';

class SecureChatScreen extends StatefulWidget {
  const SecureChatScreen({super.key});

  @override
  State<SecureChatScreen> createState() => _SecureChatScreenState();
}

class _SecureChatScreenState extends State<SecureChatScreen>
    with WidgetsBindingObserver {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ChatProvider>().initialize();
      if (mounted) _scrollToEnd(jump: true);
      _startRefresh();
    });
  }

  void _startRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 4),
      (_) => context.read<ChatProvider>().refreshNew(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ChatProvider>().refreshNew();
      _startRefresh();
    } else {
      _refreshTimer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    final sent = await context.read<ChatProvider>().send(text);
    if (!mounted || !sent) return;
    final newest = context.read<ChatProvider>().messages.lastOrNull;
    _controller.clear();
    _focusNode.requestFocus();
    _scrollToEnd();
    if (newest?.containsDanger == true) {
      _showSafetySheet();
    }
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 280), curve: Curves.easeOut);
      }
    });
  }

  void _showSafetySheet() {
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.health_and_safety_rounded,
                  color: AppColors.crisis, size: 42),
              const SizedBox(height: 12),
              Text(isUrdu ? 'آپ اکیلی نہیں ہیں' : 'You are not alone',
                  style: AppTextStyles.titleLarge),
              const SizedBox(height: 8),
              Text(
                isUrdu
                    ? 'ہمیں لگا کہ آپ کو فوری مدد کی ضرورت ہو سکتی ہے۔ ابھی حفاظتی مدد کھولیں۔'
                    : 'Your message may indicate immediate distress. Open safety support now.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    this.context.push(AppRoutes.crisis);
                  },
                  child: Text(isUrdu ? 'فوری مدد کھولیں' : 'Open immediate help'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    return Scaffold(
      backgroundColor: context.hcBg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(provider.status?.partnerName ?? (isUrdu ? 'محفوظ چیٹ' : 'Secure chat'),
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: AppTextStyles.titleMedium),
            Text(isUrdu ? 'خفیہ اور محفوظ' : 'Private and encrypted',
                style: AppTextStyles.labelSmall.copyWith(color: AppColors.success)),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.status?.available != true
                ? _Unavailable(isUrdu: isUrdu, onRetry: provider.initialize)
                : Column(
                    children: [
                      _PrivacyStrip(isUrdu: isUrdu),
                      if (provider.error != null)
                        _ErrorStrip(message: provider.error!, onRetry: provider.initialize),
                      Expanded(
                        child: provider.messages.isEmpty
                            ? _EmptyChat(isUrdu: isUrdu)
                            : RefreshIndicator(
                                onRefresh: provider.loadOlder,
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
                                  keyboardDismissBehavior:
                                      ScrollViewKeyboardDismissBehavior.onDrag,
                                  itemCount: provider.messages.length +
                                      (provider.hasMore ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (provider.hasMore && index == 0) {
                                      return Center(
                                        child: TextButton(
                                          onPressed: provider.isLoadingOlder
                                              ? null : provider.loadOlder,
                                          child: provider.isLoadingOlder
                                              ? const SizedBox.square(
                                                  dimension: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2))
                                              : Text(isUrdu ? 'پرانے پیغامات' : 'Load earlier messages'),
                                        ),
                                      );
                                    }
                                    final offset = provider.hasMore ? 1 : 0;
                                    return _MessageBubble(
                                      message: provider.messages[index - offset],
                                      isUrdu: isUrdu,
                                    );
                                  },
                                ),
                              ),
                      ),
                      _Composer(
                        controller: _controller,
                        focusNode: _focusNode,
                        isSending: provider.isSending,
                        isUrdu: isUrdu,
                        onSend: _send,
                      ),
                    ],
                  ),
      ),
    );
  }
}

class _PrivacyStrip extends StatelessWidget {
  const _PrivacyStrip({required this.isUrdu});
  final bool isUrdu;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: AppColors.successContainer.withValues(alpha: context.isDark ? .12 : .7),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded, color: AppColors.success, size: 17),
          const SizedBox(width: 8),
          Expanded(child: Text(
            isUrdu ? 'پیغامات صحت کی رپورٹ میں شامل نہیں ہوتے' : 'Messages are never included in health reports',
            style: AppTextStyles.labelSmall,
          )),
        ]),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isUrdu});
  final ChatMessage message;
  final bool isUrdu;
  @override
  Widget build(BuildContext context) {
    final localTime = message.createdAt.toLocal();
    return Align(
      alignment: message.isMine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
        child: Container(
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.fromLTRB(14, 10, 11, 7),
          decoration: BoxDecoration(
            color: message.isMine ? AppColors.primary : context.hcSurface,
            borderRadius: BorderRadiusDirectional.only(
              topStart: const Radius.circular(18),
              topEnd: const Radius.circular(18),
              bottomStart: Radius.circular(message.isMine ? 18 : 4),
              bottomEnd: Radius.circular(message.isMine ? 4 : 18),
            ),
            border: message.isMine ? null : Border.all(color: context.hcOutline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(message.content,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: message.isMine ? Colors.white : context.hcTextPrimary,
                    )),
              ),
              const SizedBox(height: 3),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Text(DateFormat('h:mm a').format(localTime),
                    style: AppTextStyles.labelSmall.copyWith(
                      fontSize: 9,
                      color: message.isMine ? Colors.white70 : context.hcTextHint,
                    )),
                if (message.isMine) ...[
                  const SizedBox(width: 4),
                  Icon(message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14, color: message.isRead ? const Color(0xFF67E8F9) : Colors.white70),
                ],
              ]),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.focusNode,
    required this.isSending, required this.isUrdu, required this.onSend});
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final bool isUrdu;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) => Material(
        color: context.hcSurface,
        elevation: 8,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 10, 12,
              10 + MediaQuery.viewPaddingOf(context).bottom),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: isUrdu ? 'پیغام لکھیں…' : 'Write a message…',
                  counterText: '',
                  filled: true,
                  fillColor: context.hcInputFill,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: isSending ? null : onSend,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white, disabledBackgroundColor: AppColors.primaryLight),
              icon: isSending
                  ? const SizedBox.square(dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      );
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.isUrdu});
  final bool isUrdu;
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            Container(padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(color: AppColors.primaryContainer, shape: BoxShape.circle),
              child: const Icon(Icons.forum_outlined, color: AppColors.primary, size: 36)),
            const SizedBox(height: 16),
            Text(isUrdu ? 'گفتگو شروع کریں' : 'Start a supportive conversation',
                textAlign: TextAlign.center, style: AppTextStyles.titleMedium),
            const SizedBox(height: 7),
            Text(isUrdu ? 'احترام اور ہمدردی کے ساتھ رابطہ کریں۔' : 'Reach out with care, respect, and empathy.',
                textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
          ]),
        ),
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.isUrdu, required this.onRetry});
  final bool isUrdu;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Icon(Icons.link_off_rounded, size: 48, color: AppColors.textHint),
            const SizedBox(height: 14),
            Text(isUrdu ? 'چیٹ ابھی دستیاب نہیں' : 'Chat is not available yet',
                textAlign: TextAlign.center, style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(isUrdu ? 'ایک فعال سرپرست ربط اور ماں کی اجازت درکار ہے۔' : 'An active guardian link and the mother’s sharing consent are required.',
                textAlign: TextAlign.center, style: AppTextStyles.bodySmall),
            const SizedBox(height: 18),
            Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 8, children: [
              ElevatedButton(onPressed: () => context.push(AppRoutes.guardianLink),
                  child: Text(isUrdu ? 'ربط قائم کریں' : 'Set up link')),
              OutlinedButton(onPressed: onRetry,
                  child: Text(isUrdu ? 'دوبارہ کوشش' : 'Retry')),
            ]),
          ]),
        ),
      );
}

class _ErrorStrip extends StatelessWidget {
  const _ErrorStrip({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;
  @override
  Widget build(BuildContext context) => Container(
        color: AppColors.errorContainer,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        child: Row(children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: AppTextStyles.labelSmall.copyWith(color: AppColors.error))),
          IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh, size: 18),
              color: AppColors.error, visualDensity: VisualDensity.compact),
        ]),
      );
}

extension<T> on List<T> {
  T? get lastOrNull => isEmpty ? null : last;
}
