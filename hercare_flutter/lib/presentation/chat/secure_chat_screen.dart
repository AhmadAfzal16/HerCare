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
import '../../services/chat_service.dart';

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
  final _viewportKey = GlobalKey();
  final Map<String, GlobalKey> _messageKeys = {};
  ChatProvider? _chat;
  Timer? _refreshTimer;
  Route<void>? _safetyRoute;
  ChatMessage? _pendingSafetyMessage;
  String? _acceptedMessageId;
  int _seenGeneration = -1;
  String? _seenAccountId;
  String? _seenRole;
  int? _initializingGeneration;
  Set<String> _knownMessageIds = {};
  bool _foreground = true;
  bool _visibilityScheduled = false;
  bool _loadingOlder = false;
  bool _pendingActionsVisible = false;
  bool _polling = false;
  int _pollFailures = 0;

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.extentAfter < 100) {
      _scheduleVisibility();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final provider = context.read<ChatProvider>();
    if (!identical(_chat, provider)) {
      _chat?.removeListener(_onChatChanged);
      _chat?.setVisible(false);
      _chat = provider;
      provider.addListener(_onChatChanged);
      _seenGeneration = -1;
      _seenAccountId = null;
      _seenRole = null;
      _onChatChanged();
    }
    // ModalRoute.isCurrentOf below registers an inherited dependency, so
    // pushing another route or opening a sheet suspends this page's polling.
    _scheduleVisibility();
  }

  bool get _isVisible =>
      mounted &&
      _foreground &&
      ModalRoute.of(context)?.isCurrent == true &&
      _chat?.accountId != null;

  bool _isCurrent(ChatProvider provider, int generation) =>
      mounted &&
      identical(_chat, provider) &&
      provider.generation == generation;

  void _onChatChanged() {
    final provider = _chat;
    if (!mounted || provider == null) return;
    if (_seenGeneration != provider.generation) {
      final bindingChanged =
          _seenAccountId != provider.accountId || _seenRole != provider.role;
      _seenGeneration = provider.generation;
      _seenAccountId = provider.accountId;
      _seenRole = provider.role;
      _controller.clear();
      _focusNode.unfocus();
      _refreshTimer?.cancel();
      _refreshTimer = null;
      _polling = false;
      _pollFailures = 0;
      _knownMessageIds = {};
      _messageKeys.clear();
      _acceptedMessageId = null;
      _pendingSafetyMessage = null;
      _initializingGeneration = null;
      _loadingOlder = false;
      _pendingActionsVisible = false;
      _closeOldSafetySheet();
      final generation = provider.generation;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!bindingChanged ||
            !_isCurrent(provider, generation) ||
            provider.accountId == null) {
          return;
        }
        _initialize(provider, generation);
      });
    }
    final accepted = provider.lastSentMessage;
    if (accepted != null && accepted.id != _acceptedMessageId) {
      _acceptedMessageId = accepted.id;
      if (_controller.text.trim() == accepted.content) {
        _controller.clear();
      }
      if (provider.role == 'mother' &&
          accepted.isMine &&
          accepted.containsDanger) {
        _pendingSafetyMessage = accepted;
      }
    }
    final ids = provider.messages.map((message) => message.id).toSet();
    _messageKeys.removeWhere((id, _) => !ids.contains(id));
    final hasNew = ids.difference(_knownMessageIds).isNotEmpty;
    final nearBottom = !_scrollController.hasClients ||
        _scrollController.position.extentAfter < 100;
    if (hasNew &&
        !_loadingOlder &&
        !provider.isLoadingOlder &&
        nearBottom &&
        _isVisible) {
      _scrollToEnd();
    }
    final pendingActions =
        provider.pendingAttempt != null && !provider.isSending;
    if (pendingActions && !_pendingActionsVisible && nearBottom && _isVisible) {
      _scrollToEnd();
    }
    _pendingActionsVisible = pendingActions;
    _knownMessageIds = ids;
    _scheduleVisibility();
  }

  Future<void> _initialize(ChatProvider provider, int generation) async {
    if (_initializingGeneration == generation) return;
    _initializingGeneration = generation;
    await provider.initialize();
    if (!_isCurrent(provider, generation)) return;
    if (_isVisible) _scrollToEnd(jump: true);
    _scheduleVisibility();
  }

  void _scheduleVisibility() {
    if (_visibilityScheduled || !mounted) return;
    _visibilityScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityScheduled = false;
      if (!mounted) return;
      _syncVisibility();
    });
  }

  void _syncVisibility() {
    final provider = _chat;
    if (provider == null) return;
    final visible = _isVisible;
    provider.setVisible(visible);
    if (!visible || provider.status?.available != true) {
      _refreshTimer?.cancel();
      _refreshTimer = null;
      return;
    }
    // Read receipts refer only to the server's loaded page cursor, never to a
    // guessed timestamp or to a successful send. Hidden routes don't mark read.
    if (provider.isAtLatest &&
        _scrollController.hasClients &&
        _scrollController.position.extentAfter < 100) {
      provider.markVisibleRead();
    }
    if (_pendingSafetyMessage != null && _safetyRoute == null) {
      _pendingSafetyMessage = null;
      _showSafetySheet(provider, provider.generation);
    }
    if (_refreshTimer != null || _polling) return;
    final generation = provider.generation;
    final delay = switch (_pollFailures) {
      0 => 10,
      1 => 20,
      2 => 40,
      _ => 60,
    };
    _refreshTimer = Timer(Duration(seconds: delay), () async {
      _refreshTimer = null;
      if (!_isCurrent(provider, generation) || !_isVisible) {
        provider.setVisible(false);
        return;
      }
      if (provider.isSending ||
          provider.isLoading ||
          provider.isLoadingOlder ||
          provider.isRefreshing) {
        _scheduleVisibility();
        return;
      }
      _polling = true;
      await provider.refreshNew();
      if (!_isCurrent(provider, generation)) return;
      _polling = false;
      final kind = provider.lastRefreshFailure?.kind;
      if (kind == ChatFailureKind.transport ||
          kind == ChatFailureKind.server ||
          kind == ChatFailureKind.rateLimited ||
          kind == ChatFailureKind.invalidResponse) {
        _pollFailures = (_pollFailures + 1).clamp(0, 3);
      } else {
        _pollFailures = 0;
      }
      _scheduleVisibility();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _chat?.setVisible(false);
      _refreshTimer?.cancel();
      _refreshTimer = null;
    } else {
      _pollFailures = 0;
      _scheduleVisibility();
      if (_isVisible) _chat?.refreshNew();
    }
  }

  void _closeOldSafetySheet() {
    final route = _safetyRoute;
    _safetyRoute = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (route.isActive) route.navigator?.removeRoute(route);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat?.removeListener(_onChatChanged);
    _chat?.setVisible(false);
    _refreshTimer?.cancel();
    _closeOldSafetySheet();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _send({bool retry = false}) async {
    final provider = _chat;
    if (provider == null || !_isVisible) return;
    final generation = provider.generation;
    final original = _controller.text;
    final content = retry ? provider.pendingAttempt?.content : original.trim();
    if (content == null || content.isEmpty) return;
    final sent =
        retry ? await provider.retryPending() : await provider.send(original);
    if (!_isCurrent(provider, generation) || !sent) return;
    // Text entered while an asynchronous operation completed is never erased.
    if (_controller.text == original && original.trim() == content) {
      _controller.clear();
    }
    if (!_isVisible) return;
    _focusNode.requestFocus();
    _scrollToEnd();
    _scheduleVisibility();
  }

  Future<void> _loadOlder() async {
    final provider = _chat;
    if (provider == null || !_isVisible || _loadingOlder) return;
    final generation = provider.generation;
    final position =
        _scrollController.hasClients ? _scrollController.position.pixels : null;
    final extent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : null;
    final anchor = _visibleAnchor();
    _loadingOlder = true;
    await provider.loadOlder();
    if (!_isCurrent(provider, generation)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent(provider, generation)) return;
      _loadingOlder = false;
      if (position == null || extent == null || !_scrollController.hasClients) {
        return;
      }
      // Preserve the current reading position when older messages prepend.
      final next =
          position + (_scrollController.position.maxScrollExtent - extent);
      _scrollController.jumpTo(next.clamp(
        _scrollController.position.minScrollExtent,
        _scrollController.position.maxScrollExtent,
      ));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isCurrent(provider, generation)) return;
        if (anchor != null && _scrollController.hasClients) {
          final render =
              _messageKeys[anchor.$1]?.currentContext?.findRenderObject();
          if (render is RenderBox && render.attached) {
            final adjustment = render.localToGlobal(Offset.zero).dy - anchor.$2;
            final corrected = _scrollController.position.pixels + adjustment;
            _scrollController.jumpTo(corrected.clamp(
              _scrollController.position.minScrollExtent,
              _scrollController.position.maxScrollExtent,
            ));
          }
        }
        _scheduleVisibility();
      });
    });
  }

  (String, double)? _visibleAnchor() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached) return null;
    final top = viewport.localToGlobal(Offset.zero).dy;
    final bottom = top + viewport.size.height;
    (String, double)? anchor;
    for (final entry in _messageKeys.entries) {
      final render = entry.value.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.attached) continue;
      final y = render.localToGlobal(Offset.zero).dy;
      if (y + render.size.height > top &&
          y < bottom &&
          (anchor == null || y < anchor.$2)) {
        anchor = (entry.key, y);
      }
    }
    return anchor;
  }

  Future<void> _returnToLatest() async {
    final provider = _chat;
    if (provider == null || !_isVisible) return;
    final generation = provider.generation;
    await provider.returnToLatest();
    if (!_isCurrent(provider, generation)) return;
    _scrollToEnd(jump: true);
    _scheduleVisibility();
  }

  void _scrollToEnd({bool jump = false}) {
    final generation = _chat?.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_isVisible ||
          _chat?.generation != generation ||
          !_scrollController.hasClients) {
        return;
      }
      final target = _scrollController.position.maxScrollExtent;
      if (jump) {
        _scrollController.jumpTo(target);
      } else {
        _scrollController.animateTo(target,
            duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
      }
    });
  }

  Future<void> _showSafetySheet(ChatProvider provider, int generation) async {
    if (!_isCurrent(provider, generation) ||
        !_isVisible ||
        _safetyRoute != null ||
        provider.role != 'mother') {
      return;
    }
    _focusNode.unfocus();
    final isUrdu = context.read<LanguageProvider>().isUrdu;
    final accountId = provider.accountId;
    Route<void>? shownRoute;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) {
        shownRoute = ModalRoute.of(sheetContext);
        _safetyRoute = shownRoute;
        return AnimatedBuilder(
          animation: provider,
          builder: (_, __) {
            final current = provider.generation == generation &&
                provider.accountId == accountId &&
                provider.role == 'mother';
            if (!current) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.health_and_safety_rounded,
                        color: AppColors.crisis, size: 42),
                    const SizedBox(height: 12),
                    Text(isUrdu ? 'آپ اکیلی نہیں ہیں' : 'You are not alone',
                        textAlign: TextAlign.center,
                        style: AppTextStyles.titleLarge),
                    const SizedBox(height: 8),
                    Text(
                      isUrdu
                          ? 'آپ کے پیغام سے فوری پریشانی کا امکان معلوم ہوا ہے۔ ابھی حفاظتی مدد کھول سکتی ہیں۔'
                          : 'Your message may indicate immediate distress. You can open safety support now.',
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyMedium,
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        key: const Key('chat-immediate-help'),
                        onPressed: () {
                          if (!_isCurrent(provider, generation) ||
                              provider.accountId != accountId ||
                              provider.role != 'mother') {
                            return;
                          }
                          Navigator.pop(sheetContext);
                          context.push(AppRoutes.crisis);
                        },
                        child: Text(
                            isUrdu ? 'فوری مدد کھولیں' : 'Open immediate help'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (identical(_safetyRoute, shownRoute)) _safetyRoute = null;
    if (_isCurrent(provider, generation)) _scheduleVisibility();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ChatProvider>();
    final isUrdu = context.watch<LanguageProvider>().isUrdu;
    // Register a dependency on route visibility rather than relying on timers
    // to discover that another screen or a modal now covers this conversation.
    ModalRoute.isCurrentOf(context);
    _scheduleVisibility();
    final textScale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0);
    return Scaffold(
      backgroundColor: context.hcBg,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: context.hcSurface,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 56 + 20 * (textScale - 1),
        titleSpacing: 0,
        actions: [
          IconButton(
            key: const Key('chat-open-help'),
            tooltip: isUrdu ? 'فوری مدد کھولیں' : 'Open immediate help',
            onPressed: () {
              _focusNode.unfocus();
              context.push(AppRoutes.crisis);
            },
            icon: const Icon(Icons.health_and_safety_outlined),
          ),
        ],
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              provider.status?.partnerName ??
                  (isUrdu ? 'محفوظ چیٹ' : 'Secure chat'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.titleMedium,
            ),
            Text(
              isUrdu ? 'ذخیرہ شدہ پیغامات خفیہ ہیں' : 'Encrypted at rest',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  AppTextStyles.labelSmall.copyWith(color: AppColors.success),
            ),
          ],
        ),
      ),
      body: SafeArea(
        top: false,
        child: provider.isLoading
            ? const Center(child: CircularProgressIndicator())
            : provider.status?.available != true
                ? _Unavailable(
                    isUrdu: isUrdu,
                    hasAccount: provider.accountId != null,
                    hasError: provider.error != null,
                    accessChanged: provider.failure?.kind ==
                            ChatFailureKind.accessDenied ||
                        provider.failure?.kind ==
                            ChatFailureKind.conversationChanged,
                    connectionFailure:
                        provider.failure?.kind == ChatFailureKind.transport,
                    onRetry: provider.initialize,
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => Column(
                      children: [
                        Expanded(
                          key: _viewportKey,
                          child: RefreshIndicator(
                            onRefresh: _loadOlder,
                            child: CustomScrollView(
                              key: const Key('chat-messages'),
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              slivers: [
                                SliverToBoxAdapter(
                                    child: _PrivacyStrip(isUrdu: isUrdu)),
                                if (provider.hasMore)
                                  SliverToBoxAdapter(
                                    child: Center(
                                      child: TextButton(
                                        key: const Key('chat-load-earlier'),
                                        onPressed: provider.isLoadingOlder
                                            ? null
                                            : _loadOlder,
                                        child: provider.isLoadingOlder
                                            ? const SizedBox.square(
                                                dimension: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2))
                                            : Text(isUrdu
                                                ? 'پرانے پیغامات'
                                                : 'Load earlier messages'),
                                      ),
                                    ),
                                  ),
                                if (provider.messages.isEmpty)
                                  SliverToBoxAdapter(
                                      child: _EmptyChat(isUrdu: isUrdu))
                                else
                                  SliverPadding(
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 14, 14, 8),
                                    sliver: SliverList.builder(
                                      itemCount: provider.messages.length,
                                      findChildIndexCallback: (key) {
                                        final index = provider.messages
                                            .indexWhere((message) =>
                                                _messageKeys[message.id] ==
                                                key);
                                        return index < 0 ? null : index;
                                      },
                                      itemBuilder: (_, index) => _MessageBubble(
                                        key: _messageKeys.putIfAbsent(
                                          provider.messages[index].id,
                                          GlobalKey.new,
                                        ),
                                        message: provider.messages[index],
                                        isUrdu: isUrdu,
                                      ),
                                    ),
                                  ),
                                if (!provider.isAtLatest)
                                  SliverToBoxAdapter(
                                    child: Center(
                                      child: OutlinedButton.icon(
                                        key: const Key('chat-return-latest'),
                                        onPressed: provider.isLoading
                                            ? null
                                            : _returnToLatest,
                                        icon: const Icon(
                                            Icons.arrow_downward_rounded),
                                        label: Text(isUrdu
                                            ? 'تازہ پیغامات دیکھیں'
                                            : 'Return to latest messages'),
                                      ),
                                    ),
                                  ),
                                if (provider.pendingAttempt != null)
                                  SliverToBoxAdapter(
                                    child: _PendingStrip(
                                      isUrdu: isUrdu,
                                      isSending: provider.isSending,
                                      onRetry: () => _send(retry: true),
                                      onDiscard: () {
                                        // This forgets only the local retry;
                                        // it cannot retract a server commit.
                                        final content =
                                            provider.pendingAttempt?.content;
                                        if (_controller.text.trim() ==
                                            content) {
                                          _controller.clear();
                                        }
                                        provider.discardPending();
                                      },
                                    ),
                                  )
                                else if (provider.error != null)
                                  SliverToBoxAdapter(
                                    child: _ErrorStrip(
                                        message: provider.error!,
                                        onRetry: provider.initialize),
                                  ),
                                const SliverToBoxAdapter(
                                    child: SizedBox(height: 12)),
                              ],
                            ),
                          ),
                        ),
                        // Even when a keyboard and large text leave a very
                        // short viewport, the composer remains scrollable.
                        ConstrainedBox(
                          constraints: BoxConstraints(
                              maxHeight: (constraints.maxHeight * .55)
                                  .clamp(0.0, 150.0)),
                          child: SingleChildScrollView(
                            child: _Composer(
                              controller: _controller,
                              focusNode: _focusNode,
                              enabled: provider.pendingAttempt == null,
                              canSend: provider.canSend,
                              isSending: provider.isSending,
                              maxLines: constraints.maxHeight < 260 ? 1 : 4,
                              isUrdu: isUrdu,
                              onSend: _send,
                            ),
                          ),
                        ),
                      ],
                    ),
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
        color: AppColors.successContainer
            .withValues(alpha: context.isDark ? .12 : .7),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppColors.success, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isUrdu
                  ? 'پیغامات ذخیرہ کرتے وقت خفیہ رکھے جاتے ہیں، لیکن یہ اینڈ ٹو اینڈ خفیہ کاری نہیں۔ صحت کی رپورٹ میں شامل نہیں ہوتے۔'
                  : 'Stored messages are encrypted, not end-to-end encrypted. They are not included in health reports.',
              style: AppTextStyles.labelSmall,
            ),
          ),
        ]),
      );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble(
      {super.key, required this.message, required this.isUrdu});
  final ChatMessage message;
  final bool isUrdu;

  @override
  Widget build(BuildContext context) {
    final localTime = message.createdAt.toLocal();
    return Align(
      alignment: message.isMine
          ? AlignmentDirectional.centerEnd
          : AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
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
            border:
                message.isMine ? null : Border.all(color: context.hcOutline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(message.content,
                    style: AppTextStyles.bodyMedium.copyWith(
                      color:
                          message.isMine ? Colors.white : context.hcTextPrimary,
                    )),
              ),
              const SizedBox(height: 3),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  Text(DateFormat('h:mm a').format(localTime),
                      style: AppTextStyles.labelSmall.copyWith(
                        fontSize: 9,
                        color: message.isMine
                            ? Colors.white70
                            : context.hcTextHint,
                      )),
                  if (message.isMine)
                    Semantics(
                      label: message.isRead
                          ? (isUrdu ? 'پڑھا گیا' : 'Read')
                          : (isUrdu
                              ? 'سرور پر محفوظ؛ پڑھنے کی تصدیق نہیں'
                              : 'Saved on server; not confirmed read'),
                      child: Icon(
                          message.isRead
                              ? Icons.done_all_rounded
                              : Icons.done_rounded,
                          size: 14,
                          color: message.isRead
                              ? const Color(0xFF67E8F9)
                              : Colors.white70),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.canSend,
    required this.isSending,
    required this.maxLines,
    required this.isUrdu,
    required this.onSend,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool canSend;
  final bool isSending;
  final int maxLines;
  final bool isUrdu;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) => Material(
        color: context.hcSurface,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                key: const Key('chat-composer'),
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                minLines: 1,
                maxLines: maxLines,
                maxLength: 2000,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: isUrdu ? 'پیغام لکھیں…' : 'Write a message…',
                  counterText: '',
                  filled: true,
                  fillColor: context.hcInputFill,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const Key('chat-send'),
              tooltip: isUrdu ? 'پیغام بھیجیں' : 'Send message',
              onPressed: !canSend || isSending ? null : onSend,
              style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.primaryLight),
              icon: isSending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      );
}

class _PendingStrip extends StatelessWidget {
  const _PendingStrip({
    required this.isUrdu,
    required this.isSending,
    required this.onRetry,
    required this.onDiscard,
  });
  final bool isUrdu;
  final bool isSending;
  final VoidCallback onRetry;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('chat-pending-notice'),
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSending
                  ? (isUrdu
                      ? 'پیغام کی تصدیق ہو رہی ہے…'
                      : 'Confirming message…')
                  : (isUrdu
                      ? 'پیغام محفوظ ہوا یا نہیں، تصدیق نہیں ہو سکی۔ دوبارہ کوشش اسی پیغام کو بھیجے گی، نیا پیغام نہیں۔'
                      : 'Delivery is not confirmed. Retry checks the same message; it does not send a new copy.'),
              style: AppTextStyles.bodySmall,
            ),
            if (!isSending) ...[
              const SizedBox(height: 6),
              Text(
                isUrdu
                    ? 'مقامی کوشش ہٹانا سرور پر پہنچے پیغام کو حذف نہیں کرتا۔'
                    : 'Discarding this local attempt does not delete a message already saved on the server.',
                style: AppTextStyles.labelSmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    key: const Key('chat-retry-pending'),
                    onPressed: onRetry,
                    child: Text(isUrdu
                        ? 'اسی پیغام کی دوبارہ کوشش'
                        : 'Retry same message'),
                  ),
                  TextButton(
                    key: const Key('chat-discard-pending'),
                    onPressed: onDiscard,
                    child: Text(
                        isUrdu ? 'مقامی کوشش ہٹائیں' : 'Discard local attempt'),
                  ),
                ],
              ),
            ],
          ],
        ),
      );
}

class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.isUrdu});
  final bool isUrdu;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                  color: AppColors.primaryContainer, shape: BoxShape.circle),
              child: const Icon(Icons.forum_outlined,
                  color: AppColors.primary, size: 36)),
          const SizedBox(height: 16),
          Text(isUrdu ? 'گفتگو شروع کریں' : 'Start a supportive conversation',
              textAlign: TextAlign.center, style: AppTextStyles.titleMedium),
          const SizedBox(height: 7),
          Text(
              isUrdu
                  ? 'احترام اور ہمدردی کے ساتھ رابطہ کریں۔'
                  : 'Reach out with care, respect, and empathy.',
              textAlign: TextAlign.center,
              style: AppTextStyles.bodySmall),
        ]),
      );
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({
    required this.isUrdu,
    required this.hasAccount,
    required this.hasError,
    required this.accessChanged,
    required this.connectionFailure,
    required this.onRetry,
  });
  final bool isUrdu;
  final bool hasAccount;
  final bool hasError;
  final bool accessChanged;
  final bool connectionFailure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            Icon(
              connectionFailure
                  ? Icons.cloud_off_rounded
                  : Icons.link_off_rounded,
              size: 48,
              color: AppColors.textHint,
            ),
            const SizedBox(height: 14),
            Text(
                accessChanged
                    ? (isUrdu
                        ? 'چیٹ کی اجازت بدل گئی ہے'
                        : 'Chat access changed')
                    : hasError
                        ? (connectionFailure
                            ? (isUrdu
                                ? 'چیٹ سے رابطہ نہیں ہو سکا'
                                : 'Could not connect to chat')
                            : (isUrdu
                                ? 'چیٹ ابھی لوڈ نہیں ہو سکی'
                                : 'Chat could not load right now'))
                        : (isUrdu
                            ? 'چیٹ ابھی دستیاب نہیں'
                            : 'Chat is not available yet'),
                textAlign: TextAlign.center,
                style: AppTextStyles.titleMedium),
            const SizedBox(height: 8),
            Text(
                !hasAccount
                    ? (isUrdu
                        ? 'چیٹ استعمال کرنے کے لیے سائن ان کریں۔'
                        : 'Sign in to use chat.')
                    : accessChanged
                        ? (isUrdu
                            ? 'ربط یا اجازت بدل سکتی ہے۔ تازہ حالت دیکھنے کے لیے چیٹ دوبارہ لوڈ کریں۔'
                            : 'Your link or permission may have changed. Reload chat to check the current status.')
                        : hasError
                            ? (connectionFailure
                                ? (isUrdu
                                    ? 'اپنا رابطہ چیک کر کے دوبارہ کوشش کریں۔ ربط کی حالت کی ابھی تصدیق نہیں ہوئی۔'
                                    : 'Check your connection and try again. Your link status has not been confirmed.')
                                : (isUrdu
                                    ? 'چیٹ کی تازہ حالت کی تصدیق نہیں ہوئی۔ کچھ دیر بعد دوبارہ کوشش کریں۔'
                                    : 'The current chat status is not confirmed. Please try again in a moment.'))
                            : (isUrdu
                                ? 'ایک فعال سرپرست ربط اور ماں کی اجازت درکار ہے۔'
                                : 'An active guardian link and the mother’s sharing consent are required.'),
                textAlign: TextAlign.center,
                style: AppTextStyles.bodySmall),
            if (hasAccount) ...[
              const SizedBox(height: 18),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (!hasError)
                    ElevatedButton(
                      onPressed: () => context.push(AppRoutes.guardianLink),
                      child: Text(isUrdu ? 'ربط قائم کریں' : 'Set up link'),
                    ),
                  OutlinedButton(
                    onPressed: onRetry,
                    child: Text(isUrdu ? 'دوبارہ کوشش' : 'Retry'),
                  ),
                ],
              ),
            ],
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
          Expanded(
              child: Text(message,
                  style: AppTextStyles.labelSmall
                      .copyWith(color: AppColors.error))),
          IconButton(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, size: 18),
              color: AppColors.error,
              visualDensity: VisualDensity.compact),
        ]),
      );
}
