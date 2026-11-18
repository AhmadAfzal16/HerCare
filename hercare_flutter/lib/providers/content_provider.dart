import 'package:flutter/foundation.dart';

import '../data/models/content_models.dart';
import '../presentation/content/content_cache.dart';
import '../services/content_service.dart';

class ContentDetail {
  const ContentDetail(this.item, {this.offline = false, this.savedAt});
  final ContentItem item;
  final bool offline;
  final DateTime? savedAt;
}

/// Account-bound, bounded catalogue state. A lifecycle-aware visible widget
/// requests refreshes; this provider never starts background timers or uploads
/// journals, chat, scores or device usage.
class ContentProvider extends ChangeNotifier {
  ContentProvider({ContentService? service, DateTime Function()? now})
      : _service = service ?? ContentService(),
        _now = now ?? DateTime.now;
  final ContentService _service;
  final DateTime Function() _now;
  String? _accountId;
  String? _origin;
  String _role = '', _language = 'en';
  bool _disposed = false, _offline = false, _dirty = true;
  int _generation = 0, _viewGeneration = 0, _failureCount = 0;
  ContentFeed? _feed, _saved;
  ContentPreferences? _currentPreferences;
  List<String> _allowedMediaHosts = const [];
  bool _safetyPriority = false;
  bool _cacheBlocked = false;
  CachedContent? _cached;
  String? _error;
  Future<void>? _load;
  String? _loadKey;
  bool _loadSaved = false, _queuedRefresh = false;
  DateTime? _lastRefresh, _lastSavedRefresh;
  final Map<String, String> _requestIds = {};
  final Set<String> _mutations = {};
  Object? _careRevision;
  int _signalRevision = 0;
  LiveFeed? _live;
  Future<void>? _liveLoad;
  final Set<String> _hiddenLive = {};

  /// Unreviewed trusted-channel results; never cached to disk, cleared on
  /// account change, hidden during safety priority, and re-checked against
  /// her music/faith opt-ins on this device too.
  List<LiveVideo> get liveVideos => !canUseAccount ||
          _offline ||
          safetyPriority ||
          _live == null ||
          _live!.safetyPriority
      ? const []
      : List.unmodifiable(_live!.items.where((video) =>
          !_hiddenLive.contains(video.videoId) &&
          (preferences.musicEnabled || !video.isMusic) &&
          (preferences.religiousEnabled || !video.isReligious) &&
          !preferences.disabledCategories.contains(video.category)));
  LiveFeed? get liveFeed => canUseAccount ? _live : null;

  Future<void> loadLive({String language = 'en'}) {
    if (!canUseAccount || safetyPriority) return Future.value();
    if (_liveLoad != null) return _liveLoad!;
    final generation = _generation;
    final work = () async {
      try {
        final result = await _service.live(language: language);
        if (!_same(generation)) return;
        _live = result;
        if (result.safetyPriority) _safetyPriority = true;
      } catch (_) {
        // Live search is optional; the reviewed feed keeps working.
        if (_same(generation)) _live = null;
      }
    }();
    _liveLoad = work;
    return work.whenComplete(() {
      if (_same(generation)) {
        _liveLoad = null;
        _notify();
      }
    });
  }

  Future<bool> hideLive(LiveVideo video) async {
    final generation = _generation;
    if (!_same(generation)) return false;
    _hiddenLive.add(video.videoId);
    _notify();
    try {
      await _service.hideLive(video.videoId);
      return _same(generation);
    } catch (_) {
      // Stay hidden on this phone for the session even if the server missed it.
      return false;
    }
  }

  String? get accountId => _accountId;
  String get role => _role;
  int get signalRevision => _signalRevision;

  /// An opaque local change marker, never sent to the network or written to
  /// disk. A visible page uses it to refresh after a confirmed care update.
  void observeCareRevision(Object revision) {
    if (!canUseAccount || _careRevision == revision) return;
    _careRevision = revision;
    _signalRevision++;
    invalidate();
    _notify();
  }

  bool get canUseAccount =>
      !_disposed && _accountId != null && _origin == _service.origin;
  bool get isLoading => _load != null;
  bool get isOffline => _offline;
  String? get error => _error;
  ContentFeed? get feed => canUseAccount ? _feed : null;
  ContentPreferences get preferences => !canUseAccount
      ? const ContentPreferences()
      : _currentPreferences ??
          _cached?.preferences ??
          const ContentPreferences();
  bool get safetyPriority => _safetyPriority;
  DateTime? get offlineSavedAt => _cached?.savedAt;
  ContentItem? get dailyVerse => !canUseAccount ||
          _offline ||
          safetyPriority ||
          (_feed?.dailyVerse != null &&
              (!preferences.allows(_feed!.dailyVerse!) ||
                  !_itemAvailable(_feed!.dailyVerse!)))
      ? null
      : _feed?.dailyVerse;
  List<String> get allowedMediaHosts =>
      canUseAccount ? List.unmodifiable(_allowedMediaHosts) : const [];
  List<ContentItem> items({bool savedOnly = false}) =>
      List.unmodifiable((_offline
              ? (_cacheCurrent ? _cached!.items : const <ContentItem>[])
              : (savedOnly ? _saved?.items : _feed?.items) ??
                  const <ContentItem>[])
          .where((item) =>
              canUseAccount &&
              !safetyPriority &&
              (item.audience == 'both' || item.audience == _role) &&
              preferences.allows(item) &&
              _itemAvailable(item)));

  bool get _cacheCurrent {
    if (_cached == null || _cacheBlocked) return false;
    final age = _now().toUtc().difference(_cached!.savedAt.toUtc());
    return !age.isNegative && age <= ContentCache.lifetime;
  }

  bool _itemAvailable(ContentItem item) {
    final now = _now().toUtc();
    return (item.reviewAfter == null || now.isBefore(item.reviewAfter!)) &&
        (item.availableUntil == null || now.isBefore(item.availableUntil!)) &&
        (item.availableFrom == null || !now.isBefore(item.availableFrom!));
  }

  bool busy(String id) => _mutations.any((key) => key.startsWith('$id:'));

  Duration get refreshInterval {
    final seconds = (_feed?.refreshAfterSeconds ?? 30).clamp(30, 600);
    final multiplier = 1 << _failureCount.clamp(0, 3);
    return Duration(seconds: (seconds * multiplier).clamp(30, 600));
  }

  void bindAccount(String? id, {String role = ''}) {
    final currentOrigin = _service.origin;
    if (_disposed ||
        (_accountId == id && _role == role && _origin == currentOrigin)) {
      return;
    }
    _accountId = id;
    _origin = currentOrigin;
    _role = role;
    _generation++;
    _viewGeneration++;
    _feed = null;
    _saved = null;
    _cached = null;
    _currentPreferences = null;
    _allowedMediaHosts = const [];
    _safetyPriority = false;
    _cacheBlocked = false;
    _error = null;
    _offline = false;
    _dirty = true;
    _load = null;
    _loadKey = null;
    _lastRefresh = null;
    _lastSavedRefresh = null;
    _requestIds.clear();
    _mutations.clear();
    _failureCount = 0;
    _queuedRefresh = false;
    _careRevision = null;
    _live = null;
    _liveLoad = null;
    _hiddenLive.clear();
    _signalRevision++;
    _service.bindAccount(id);
    notifyListeners();
  }

  bool _same(int generation, [int? view]) =>
      canUseAccount &&
      generation == _generation &&
      (view == null || view == _viewGeneration);
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Called after clinical/practice providers change, without sending their
  /// contents to another endpoint. The next visible refresh asks the server.
  void invalidate() {
    if (!canUseAccount) return;
    _dirty = true;
    if (_load != null) _queuedRefresh = true;
  }

  Future<void> load(
      {String language = 'en', bool savedOnly = false, bool force = false}) {
    if (!_disposed && _accountId != null && _origin != _service.origin) {
      bindAccount(_accountId, role: _role);
    }
    if (!canUseAccount) return Future.value();
    final normalized = language == 'ur' ? 'ur' : 'en';
    if (_language != normalized) {
      _language = normalized;
      _viewGeneration++;
      _dirty = true;
      _load = null;
      _loadKey = null;
    }
    final key = '$_generation:$_viewGeneration:$savedOnly';
    if (_loadKey == key && _load != null) return _load!;
    // Separate saved/feed refreshes serialize rather than repeatedly replacing
    // one another when both a home card and the full route are mounted.
    if (_load != null) {
      final current = _load!;
      return current.then((_) =>
          load(language: normalized, savedOnly: savedOnly, force: force));
    }
    final last = savedOnly ? _lastSavedRefresh : _lastRefresh;
    if (!force &&
        !_dirty &&
        last != null &&
        _now().difference(last) < refreshInterval) {
      return Future.value();
    }
    final generation = _generation, view = _viewGeneration;
    _loadKey = key;
    _loadSaved = savedOnly;
    final work = _loadFor(generation, view, normalized, savedOnly);
    _load = work;
    _notify();
    return work.whenComplete(() {
      if (!_same(generation, view) || _loadKey != key) return;
      _load = null;
      _loadKey = null;
      _notify();
      if (_queuedRefresh) {
        _queuedRefresh = false;
        load(language: _language, savedOnly: _loadSaved, force: true);
      }
    });
  }

  Future<void> _loadFor(
      int generation, int view, String language, bool savedOnly) async {
    try {
      if (_cached == null && !_cacheBlocked) {
        try {
          final copy = await _service.readCache();
          if (!_same(generation, view)) return;
          _cached = copy;
        } on ContentAccountException {
          rethrow;
        } catch (_) {
          // Secure-storage problems never prevent a fresh server request.
        }
      }
      final result =
          await _service.feed(language: language, savedOnly: savedOnly);
      if (!_same(generation, view)) return;
      _currentPreferences = result.preferences;
      _allowedMediaHosts = result.allowedMediaHosts;
      _safetyPriority = result.safetyPriority;
      final changed = _cached != null &&
          (_cached!.revision != result.catalogRevision ||
              _cached!.preferences.version != result.preferences.version);
      if (changed || result.safetyPriority) {
        _cached = null;
        await _clearCacheSafely();
        if (!_same(generation, view)) return;
      }
      if (savedOnly) {
        _saved = result;
        _lastSavedRefresh = _now();
        if (!result.safetyPriority) {
          try {
            await _service.writeCache(
                result.items, result.preferences, result.catalogRevision);
            if (!_same(generation, view)) return;
            _cacheBlocked = false;
            _cached = await _service.readCache();
          } on ContentAccountException {
            rethrow;
          } catch (_) {
            // Saving remains acknowledged by the server even if this phone
            // cannot retain an encrypted text copy.
          }
        }
      } else {
        _feed = result;
        _lastRefresh = _now();
      }
      if (!_same(generation, view)) return;
      _offline = false;
      _failureCount = 0;
      _dirty = false;
      _error = null;
    } on ContentAccountException {
      // Deliberately ignore a reply belonging to another account/origin.
    } catch (error) {
      if (!_same(generation, view)) return;
      _failureCount = (_failureCount + 1).clamp(0, 3);
      _error = error is ContentException
          ? error.message
          : 'Content could not be refreshed. Please retry.';
      _offline = error is ContentException && error.offline;
      if (error is ContentException && error.accessDenied) {
        _feed = null;
        _saved = null;
        _cached = null;
        _currentPreferences = null;
        _allowedMediaHosts = const [];
        await _clearCacheSafely();
      }
    }
  }

  Future<void> _clearCacheSafely() async {
    _cacheBlocked = true;
    try {
      await _service.clearCache();
    } catch (_) {/* Fail closed in memory. */}
  }

  /// Best-effort engagement signal for learning her topics; never blocks or
  /// shows an error, and is skipped offline or during safety priority.
  Future<void> recordEngagement(ContentItem item, String event,
      {int seconds = 0, String? reason}) async {
    final generation = _generation;
    if (!_same(generation) || safetyPriority || _offline) return;
    try {
      await _service.engagement(item.id, event,
          seconds: seconds, reason: reason);
      if (_same(generation)) invalidate();
    } catch (_) {/* Engagement is optional and never retried. */}
  }

  Future<ContentDetail?> detail(String id, {String? reason}) async {
    final generation = _generation;
    if (!_same(generation) || safetyPriority) return null;
    try {
      final item = await _service.detail(id, reason: reason);
      if (!_same(generation)) return null;
      return ContentDetail(item);
    } on ContentAccountException {
      return null;
    } on ContentException catch (error) {
      if (!_same(generation)) return null;
      if (error.offline && !_cacheBlocked) {
        final cached = await _service.readCache();
        if (!_same(generation)) return null;
        for (final item in cached?.items ?? const <ContentItem>[]) {
          if (item.id == id &&
              preferences.allows(item) &&
              (item.audience == 'both' || item.audience == _role)) {
            return ContentDetail(item, offline: true, savedAt: cached?.savedAt);
          }
        }
      }
      if (error.statusCode == 404 ||
          error.accessDenied ||
          error.statusCode == 409) {
        _cached = null;
        if (error.statusCode == 409) _safetyPriority = true;
        if (error.accessDenied) {
          _feed = null;
          _saved = null;
          _currentPreferences = null;
          _allowedMediaHosts = const [];
        }
        await _clearCacheSafely();
        _notify();
      }
      rethrow;
    }
  }

  Future<bool> updatePreferences(ContentPreferences next) async {
    final generation = _generation;
    if (!_same(generation) || _mutations.contains('preferences')) return false;
    _mutations.add('preferences');
    _error = null;
    _notify();
    try {
      await _service.preferences(next);
      if (!_same(generation)) return false;
      _feed = null;
      _saved = null;
      _cached = null;
      _currentPreferences = next;
      await _clearCacheSafely();
      if (!_same(generation)) return false;
      invalidate();
      await load(language: _language, force: true);
      return _same(generation) && _error == null;
    } catch (error) {
      if (_same(generation)) {
        _error = error is ContentException
            ? error.message
            : 'Preferences could not be saved. Please retry.';
        if (error is ContentException && error.statusCode == 409) invalidate();
        if (error is ContentException && error.accessDenied) {
          _feed = null;
          _saved = null;
          _cached = null;
          _currentPreferences = null;
          _allowedMediaHosts = const [];
          await _clearCacheSafely();
        }
      }
      return false;
    } finally {
      if (_same(generation)) {
        _mutations.remove('preferences');
        _notify();
      }
    }
  }

  bool get savingPreferences => _mutations.contains('preferences');

  Future<bool> setSaved(ContentItem item, bool value) => _mutate(item,
      'saved:$value', (requestId) => _service.save(item.id, value, requestId));
  Future<bool> giveFeedback(ContentItem item, String value) => _mutate(
      item,
      'feedback:$value',
      (requestId) => _service.feedback(item.id, value, requestId));

  Future<bool> _mutate(ContentItem item, String action,
      Future<void> Function(String) send) async {
    final generation = _generation, key = '${item.id}:$action';
    if (!_same(generation) || busy(item.id)) return false;
    if (_requestIds.length >= 64 && !_requestIds.containsKey(key)) {
      _requestIds.clear();
    }
    final intentPrefix = '${item.id}:${action.split(':').first}:';
    _requestIds.removeWhere(
        (existing, _) => existing.startsWith(intentPrefix) && existing != key);
    final requestId = _requestIds.putIfAbsent(key, ContentService.requestId);
    _mutations.add(key);
    _error = null;
    _notify();
    try {
      await send(requestId);
      if (!_same(generation)) return false;
      _requestIds.remove(key);
      // A successful unsave/dismiss must not leave an offline copy behind.
      if (action == 'saved:false' || action == 'feedback:dismissed') {
        _cached = null;
        await _clearCacheSafely();
      }
      if (!_same(generation)) return false;
      invalidate();
      await load(language: _language, force: true);
      if (!_same(generation)) return false;
      // Fresh saved list rechecks publication/permissions before text caching.
      if (action.startsWith('saved:')) {
        await load(language: _language, savedOnly: true, force: true);
      }
      return _same(generation);
    } catch (error) {
      if (_same(generation)) {
        _error = error is ContentException
            ? error.message
            : 'This change was not confirmed. Retry to check it.';
        if (error is ContentException && error.accessDenied) {
          _feed = null;
          _saved = null;
          _cached = null;
          _currentPreferences = null;
          _allowedMediaHosts = const [];
          await _clearCacheSafely();
        }
      }
      return false;
    } finally {
      if (_same(generation)) {
        _mutations.remove(key);
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
