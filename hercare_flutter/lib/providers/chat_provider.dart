import 'package:flutter/foundation.dart';

import '../data/models/chat_models.dart';
import '../services/chat_service.dart';

/// One memory-only attempt, pinned to its original account and conversation.
class ChatPendingAttempt {
  const ChatPendingAttempt({
    required this.accountId,
    required this.conversationId,
    required this.requestId,
    required this.content,
  });

  final String accountId;
  final String conversationId;
  final String requestId;
  final String content;
}

class ChatProvider extends ChangeNotifier {
  ChatProvider({
    ChatService? service,
    String Function()? requestIdFactory,
    DateTime Function()? clock,
  })  : _service = service ?? ChatService(),
        _requestIdFactory = requestIdFactory ?? ChatService.createRequestId,
        _clock = clock ?? DateTime.now;

  static const pageSize = 50;
  static const maxMessages = 500;
  static const maxForwardPagesPerRefresh = 5;

  final ChatService _service;
  final String Function() _requestIdFactory;
  final DateTime Function() _clock;
  ChatStatus? _status;
  final List<ChatMessage> _messages = [];
  String? _accountId;
  String? _role;
  int _generation = 0;
  bool _disposed = false;
  bool _visible = false;
  bool _loading = false;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _refreshing = false;
  bool _reading = false;
  bool _hasMore = false;
  bool _hasForwardBacklog = false;
  bool _historyLimited = false;
  bool _isAtLatest = true;
  String? _olderCursor;
  String? _forwardCursor;
  ChatMessage? _forwardBoundary;
  String? _lastReadCursor;
  String? _lastReadFromCursor;
  String? _error;
  String? _readReceiptError;
  ChatFailure? _failure;
  ChatFailure? _lastRefreshFailure;
  ChatPendingAttempt? _pending;
  ChatMessage? _lastSentMessage;
  DateTime? _nextReceiptCheck;
  DateTime? _nextReadAttempt;

  String? get accountId => _accountId;
  String? get role => _role;
  int get generation => _generation;
  ChatStatus? get status => _status;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _loading;
  bool get isSending => _sending;
  bool get isLoadingOlder => _loadingOlder;
  bool get isRefreshing => _refreshing;
  bool get hasMore => _hasMore;
  bool get hasForwardBacklog => _hasForwardBacklog;
  bool get historyLimited => _historyLimited;
  bool get isAtLatest => _isAtLatest;
  String? get error => _error;
  String? get readReceiptError => _readReceiptError;
  ChatFailure? get failure => _failure;
  ChatFailure? get lastRefreshFailure => _lastRefreshFailure;
  ChatPendingAttempt? get pendingAttempt => _pending;
  ChatPendingAttempt? get pendingSend => _pending;
  ChatMessage? get lastSentMessage => _lastSentMessage;
  bool get _busy => _loading || _sending || _loadingOlder || _refreshing;
  bool get canSend =>
      !_disposed &&
      _accountId != null &&
      (_role == 'mother' || _role == 'guardian') &&
      _status?.available == true &&
      _status?.conversationId != null &&
      !_busy &&
      _isAtLatest &&
      _pending == null;

  /// Authentication binding is explicit; old completions can never populate a
  /// different account's private chat. Binding itself does no network work.
  void bindAccount(String? accountId, {String? role}) {
    if (_disposed) return;
    final normalized = accountId?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_accountId == next && _role == role) return;
    _generation++;
    _accountId = next;
    _role = next == null ? null : role;
    _visible = false;
    _resetPrivate();
    _notify();
  }

  /// This is deliberately notification-free so route visibility can be updated
  /// safely from inherited route/lifecycle observations during widget builds.
  void setVisible(bool value) {
    if (_disposed) return;
    _visible = value;
  }

  Future<void> initialize() async {
    if (_disposed || _accountId == null || _busy) return;
    final generation = _generation;
    final account = _accountId!;
    final priorConversation = _status?.conversationId;
    _loading = true;
    if (_pending == null) {
      _error = null;
      _failure = null;
    }
    _notify();
    try {
      final status = await _service.getStatusBound(accountId: account);
      if (!_current(generation)) return;
      if (priorConversation != null && !status.available) {
        throw const ChatFailure(ChatFailureKind.accessDenied,
            'Secure chat access is no longer available.');
      }
      if (priorConversation != null &&
          status.conversationId != priorConversation) {
        throw const ChatFailure(ChatFailureKind.conversationChanged,
            'The conversation has changed. Reload chat.');
      }
      if (_pending != null &&
          status.conversationId != _pending!.conversationId) {
        throw const ChatFailure(ChatFailureKind.conversationChanged,
            'The conversation has changed. Reload chat.');
      }
      if (!status.available || status.conversationId == null) {
        _resetConversation();
        _status = status;
        return;
      }
      final conversation = status.conversationId!;
      final page = await _service.getMessagePage(
          accountId: account, conversationId: conversation, limit: pageSize);
      if (!_current(generation)) return;
      _checkPage(page, conversation);
      _status = status;
      _messages
        ..clear()
        ..addAll(page.messages);
      _olderCursor = page.olderCursor;
      _forwardCursor = page.newerCursor;
      _forwardBoundary = page.messages.lastOrNull;
      if (priorConversation != conversation) _lastReadCursor = null;
      _hasMore = page.hasMore;
      _hasForwardBacklog = false;
      _historyLimited = false;
      _isAtLatest = true;
      _lastRefreshFailure = null;
      _nextReceiptCheck = _clock().add(const Duration(seconds: 30));
      _reconcilePending(page.messages);
    } catch (error) {
      if (_current(generation)) _recordFailure(error);
    } finally {
      if (_current(generation)) {
        _loading = false;
        _notify();
      }
    }
  }

  Future<void> returnToLatest() => initialize();

  Future<bool> send(String value) async {
    final content = value.trim();
    if (!canSend || content.isEmpty || content.length > 2000) return false;
    final attempt = ChatPendingAttempt(
      accountId: _accountId!,
      conversationId: _status!.conversationId!,
      requestId: _requestIdFactory(),
      content: content,
    );
    return _sendAttempt(attempt);
  }

  Future<bool> retryPending() async {
    final attempt = _pending;
    if (_disposed ||
        attempt == null ||
        _busy ||
        attempt.accountId != _accountId ||
        attempt.conversationId != _status?.conversationId ||
        _status?.available != true ||
        !_isAtLatest ||
        _failure?.deliveryUncertain != true) {
      return false;
    }
    return _sendAttempt(attempt);
  }

  void discardPending() {
    if (_disposed || _sending || _pending == null) return;
    _pending = null;
    _error = null;
    _failure = null;
    _notify();
  }

  Future<bool> _sendAttempt(ChatPendingAttempt attempt) async {
    final generation = _generation;
    _sending = true;
    _pending = attempt;
    _lastSentMessage = null;
    _error = null;
    _failure = null;
    _notify();
    try {
      final message = await _service.sendBound(
        accountId: attempt.accountId,
        conversationId: attempt.conversationId,
        clientRequestId: attempt.requestId,
        content: attempt.content,
      );
      if (!_current(generation, conversation: attempt.conversationId)) {
        return false;
      }
      if (message.conversationId != attempt.conversationId ||
          message.clientRequestId != attempt.requestId ||
          !message.isMine ||
          message.content != attempt.content) {
        throw const ChatFailure(ChatFailureKind.invalidResponse,
            'Chat could not confirm this message. Try again safely.');
      }
      _merge([message]);
      _lastSentMessage = message;
      _pending = null;
      // Sending a local message must not advance the incoming/read cursor:
      // partner messages may have committed before it while the send was slow.
      return true;
    } catch (error) {
      if (_current(generation, conversation: attempt.conversationId)) {
        final failure = _asFailure(error);
        if (!failure.deliveryUncertain) _pending = null;
        _recordFailure(failure);
      }
      return false;
    } finally {
      if (_current(generation)) {
        _sending = false;
        _notify();
      }
    }
  }

  Future<void> refreshNew() async {
    if (_disposed ||
        !_visible ||
        _status?.available != true ||
        _accountId == null ||
        _status?.conversationId == null ||
        _busy ||
        !_isAtLatest) {
      return;
    }
    final generation = _generation;
    final account = _accountId!;
    final conversation = _status!.conversationId!;
    _refreshing = true;
    _notify();
    try {
      var more = false;
      for (var index = 0; index < maxForwardPagesPerRefresh; index++) {
        final page = await _service.getMessagePage(
          accountId: account,
          conversationId: conversation,
          after: _forwardCursor,
          limit: pageSize,
        );
        if (!_current(generation, conversation: conversation)) return;
        _checkPage(page, conversation);
        if (page.messages.isNotEmpty) {
          if (_forwardBoundary != null &&
              ChatMessage.compare(page.messages.first, _forwardBoundary!) <=
                  0) {
            throw const ChatFailure(ChatFailureKind.invalidResponse,
                'Chat returned a non-progressing page. Reload chat.');
          }
          _merge(page.messages);
          _forwardCursor = page.newerCursor;
          _forwardBoundary = page.messages.last;
          _reconcilePending(page.messages);
        }
        more = page.hasMore;
        _hasForwardBacklog = more;
        if (!more) break;
      }
      // Receipt polling never imports a recent-only window or moves the
      // incoming high-water mark. That would skip an undrained burst of rows.
      if (!more &&
          (_pending != null ||
              _nextReceiptCheck == null ||
              !_clock().isBefore(_nextReceiptCheck!))) {
        final recent = await _service.getMessagePage(
          accountId: account,
          conversationId: conversation,
          limit: pageSize,
        );
        if (!_current(generation, conversation: conversation)) return;
        _checkPage(recent, conversation);
        final known = {for (final message in _messages) message.id};
        _merge(recent.messages.where((message) => known.contains(message.id)));
        _reconcilePending(recent.messages);
        _nextReceiptCheck = _clock().add(const Duration(seconds: 30));
      }
      if (_failure?.deliveryUncertain != true) {
        _error = null;
        _failure = null;
      }
      _lastRefreshFailure = null;
    } catch (error) {
      if (_current(generation, conversation: conversation)) {
        _lastRefreshFailure = _asFailure(error);
        _recordFailure(error, background: true);
      }
    } finally {
      if (_current(generation)) {
        _refreshing = false;
        _notify();
      }
    }
  }

  Future<void> loadOlder() async {
    if (_disposed ||
        !_hasMore ||
        _olderCursor == null ||
        _accountId == null ||
        _status?.conversationId == null ||
        _busy) {
      return;
    }
    final generation = _generation;
    final account = _accountId!;
    final conversation = _status!.conversationId!;
    _loadingOlder = true;
    _error = null;
    _notify();
    try {
      final page = await _service.getMessagePage(
        accountId: account,
        conversationId: conversation,
        before: _olderCursor,
        limit: pageSize,
      );
      if (!_current(generation, conversation: conversation)) return;
      _checkPage(page, conversation);
      if (page.messages.isNotEmpty &&
          _messages.isNotEmpty &&
          ChatMessage.compare(page.messages.last, _messages.first) >= 0) {
        throw const ChatFailure(ChatFailureKind.invalidResponse,
            'Chat returned an overlapping earlier page. Reload chat.');
      }
      _merge(page.messages, preferOlder: true);
      _hasMore = page.hasMore;
      _olderCursor = _messages.firstOrNull?.cursor ?? page.olderCursor;
      _reconcilePending(page.messages);
    } catch (error) {
      if (_current(generation, conversation: conversation)) {
        _recordFailure(error);
      }
    } finally {
      if (_current(generation)) {
        _loadingOlder = false;
        _notify();
      }
    }
  }

  /// Called by the visible screen after its message frame is presented.
  /// A receipt failure is never reported as a failed send and never fabricated.
  Future<void> markVisibleRead() async {
    // Only acknowledge the currently loaded range, never earlier unloaded
    // history or an accepted local send beyond the incoming high-water mark.
    final safeMessages = _forwardBoundary == null
        ? const <ChatMessage>[]
        : _messages
            .where((message) =>
                ChatMessage.compare(message, _forwardBoundary!) <= 0)
            .toList();
    final through = safeMessages.lastOrNull?.cursor;
    final from = safeMessages.firstOrNull?.cursor;
    if (_disposed ||
        !_visible ||
        _reading ||
        (_nextReadAttempt != null && _clock().isBefore(_nextReadAttempt!)) ||
        _busy ||
        through == null ||
        from == null ||
        (through == _lastReadCursor && from == _lastReadFromCursor) ||
        _messages.isEmpty ||
        _accountId == null ||
        _status?.conversationId == null) {
      return;
    }
    final generation = _generation;
    final account = _accountId!;
    final conversation = _status!.conversationId!;
    _reading = true;
    try {
      await _service.markReadBound(
          accountId: account,
          conversationId: conversation,
          throughCursor: through,
          fromCursor: from);
      if (!_current(generation, conversation: conversation)) return;
      _lastReadCursor = through;
      _lastReadFromCursor = from;
      _readReceiptError = null;
      _nextReadAttempt = null;
    } catch (error) {
      if (_current(generation, conversation: conversation)) {
        final failure = _asFailure(error);
        if (failure.kind == ChatFailureKind.accessDenied ||
            failure.kind == ChatFailureKind.conversationChanged) {
          _recordFailure(failure);
        } else {
          _readReceiptError = 'Read status could not be updated.';
          _nextReadAttempt = _clock().add(const Duration(seconds: 30));
        }
      }
    } finally {
      if (_current(generation)) {
        _reading = false;
        _notify();
      }
    }
  }

  void _checkPage(ChatPage page, String conversation) {
    if (page.conversationId != conversation ||
        page.messages.length > pageSize ||
        page.messages.any((message) =>
            message.conversationId != conversation ||
            message.cursor == null ||
            message.id.isEmpty) ||
        (page.messages.isNotEmpty &&
            (page.olderCursor != page.messages.first.cursor ||
                page.newerCursor != page.messages.last.cursor)) ||
        (page.hasMore && page.messages.isEmpty)) {
      throw const ChatFailure(ChatFailureKind.invalidResponse,
          'The server returned invalid chat data. Reload chat.');
    }
    for (var index = 1; index < page.messages.length; index++) {
      if (ChatMessage.compare(page.messages[index - 1], page.messages[index]) >=
          0) {
        throw const ChatFailure(ChatFailureKind.invalidResponse,
            'The server returned unordered chat data. Reload chat.');
      }
    }
  }

  void _merge(Iterable<ChatMessage> values, {bool preferOlder = false}) {
    final byId = {for (final message in _messages) message.id: message};
    for (final message in values) {
      byId[message.id] = message;
    }
    _messages
      ..clear()
      ..addAll(byId.values)
      ..sort(ChatMessage.compare);
    if (_messages.length > maxMessages) {
      _historyLimited = true;
      if (preferOlder) {
        _messages.removeRange(maxMessages, _messages.length);
        // Keep a contiguous earlier window rather than silently jumping over
        // hundreds of records to the current conversation.
        _isAtLatest = false;
      } else {
        _messages.removeRange(0, _messages.length - maxMessages);
        _hasMore = true;
      }
    }
    _olderCursor = _messages.firstOrNull?.cursor;
  }

  void _reconcilePending(Iterable<ChatMessage> messages) {
    final pending = _pending;
    if (pending == null ||
        pending.accountId != _accountId ||
        pending.conversationId != _status?.conversationId) {
      return;
    }
    for (final message in messages) {
      if (message.isMine &&
          message.clientRequestId == pending.requestId &&
          message.conversationId == pending.conversationId &&
          message.content == pending.content) {
        _pending = null;
        _lastSentMessage = message;
        _error = null;
        _failure = null;
        return;
      }
    }
  }

  bool _current(int generation, {String? conversation}) =>
      !_disposed &&
      _generation == generation &&
      _accountId != null &&
      (conversation == null || _status?.conversationId == conversation);

  ChatFailure _asFailure(Object error) => error is ChatFailure
      ? error
      : const ChatFailure(ChatFailureKind.transport,
          'Could not connect to secure chat. Please try again.');

  void _recordFailure(Object error, {bool background = false}) {
    final failure = _asFailure(error);
    if (failure.kind == ChatFailureKind.accessDenied ||
        failure.kind == ChatFailureKind.conversationChanged) {
      _generation++;
      _resetPrivate();
      _failure = failure;
      _error = failure.message;
      _notify();
      return;
    }
    // A quiet read/refresh must not replace a pending send's uncertain outcome.
    if (background && _pending != null && _failure?.deliveryUncertain == true) {
      return;
    }
    _failure = failure;
    _error = failure.message;
  }

  void _resetConversation() {
    _messages.clear();
    _pending = null;
    _lastSentMessage = null;
    _olderCursor = null;
    _forwardCursor = null;
    _forwardBoundary = null;
    _lastReadCursor = null;
    _lastReadFromCursor = null;
    _readReceiptError = null;
    _hasMore = false;
    _hasForwardBacklog = false;
    _historyLimited = false;
    _isAtLatest = true;
    _nextReceiptCheck = null;
    _nextReadAttempt = null;
  }

  void _resetPrivate() {
    _status = null;
    _resetConversation();
    _loading = false;
    _sending = false;
    _loadingOlder = false;
    _refreshing = false;
    _reading = false;
    _error = null;
    _failure = null;
    _lastRefreshFailure = null;
  }

  void clearError() {
    if (_disposed || _pending != null) return;
    _error = null;
    _failure = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _resetPrivate();
    super.dispose();
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? get lastOrNull => isEmpty ? null : last;
}
