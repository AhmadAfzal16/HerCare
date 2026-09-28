import 'package:flutter/foundation.dart';

import '../data/models/chat_models.dart';
import '../services/chat_service.dart';

class ChatProvider extends ChangeNotifier {
  ChatProvider({ChatService? service}) : _service = service ?? ChatService();

  final ChatService _service;
  ChatStatus? _status;
  final List<ChatMessage> _messages = [];
  bool _loading = false;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _refreshing = false;
  bool _hasMore = true;
  String? _error;

  ChatStatus? get status => _status;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _loading;
  bool get isSending => _sending;
  bool get isLoadingOlder => _loadingOlder;
  bool get hasMore => _hasMore;
  String? get error => _error;

  Future<void> initialize() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _status = await _service.getStatus();
      _messages.clear();
      if (_status!.available) {
        final initial = await _service.getMessages();
        _messages.addAll(initial);
        _hasMore = initial.length == 30;
        await _service.markRead();
      }
    } catch (error) {
      _error = _clean(error);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> send(String value) async {
    final content = value.trim();
    if (content.isEmpty || content.length > 2000 || _sending) return false;
    _sending = true;
    _error = null;
    notifyListeners();
    try {
      final message = await _service.send(content);
      _merge([message]);
      return true;
    } catch (error) {
      _error = _clean(error);
      return false;
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> refreshNew() async {
    if (_status?.available != true || _loading || _sending || _refreshing) {
      return;
    }
    _refreshing = true;
    try {
      // Refresh the recent window, not only newer timestamps. This also
      // updates delivery/read receipts and cannot miss same-timestamp rows.
      final incoming = await _service.getMessages(limit: 30);
      if (incoming.isNotEmpty) {
        _merge(incoming);
        if (incoming.any((message) => !message.isMine && !message.isRead)) {
          await _service.markRead();
        }
        notifyListeners();
      }
    } catch (error) {
      // Background refresh is deliberately quiet; manual retry remains visible.
      debugPrint('[HerCare chat] refresh failed');
    } finally {
      _refreshing = false;
    }
  }

  Future<void> loadOlder() async {
    if (!_hasMore || _messages.isEmpty || _loadingOlder) return;
    _loadingOlder = true;
    notifyListeners();
    try {
      final older =
          await _service.getMessages(before: _messages.first.createdAt);
      _hasMore = older.length == 30;
      _merge(older);
    } catch (error) {
      _error = _clean(error);
    } finally {
      _loadingOlder = false;
      notifyListeners();
    }
  }

  void _merge(Iterable<ChatMessage> values) {
    final byId = {for (final message in _messages) message.id: message};
    for (final message in values) {
      byId[message.id] = message;
    }
    _messages
      ..clear()
      ..addAll(byId.values)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');
}
