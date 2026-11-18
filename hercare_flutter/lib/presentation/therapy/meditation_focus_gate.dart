/// Serializes focus leases between HerCare's bundled meditation narrators.
/// This does not coordinate unrelated audio players elsewhere in the app.
class MeditationFocusGate {
  static final shared = MeditationFocusGate();

  Future<void> _tail = Future.value();
  Object? _activeOwner;

  Future<T> _queue<T>(Future<T> Function() operation) {
    final work = _tail.then<T>((_) => operation());
    // One failed platform operation must not poison later focus requests.
    _tail = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }

  Future<bool> acquire(
    Object owner, {
    required Future<bool> Function() activate,
    required Future<void> Function() deactivate,
    required bool Function() isCurrent,
  }) =>
      _queue(() async {
        if (!isCurrent()) return false;
        final granted = await activate();
        if (!granted) return false;
        _activeOwner = owner;
        if (!isCurrent()) {
          // Release a stale grant before the next queued owner can activate.
          _activeOwner = null;
          await deactivate();
          return false;
        }
        return true;
      });

  Future<void> release(
    Object owner, {
    required Future<void> Function() deactivate,
  }) =>
      _queue(() async {
        // Check at execution time, not when this release was requested.
        if (!identical(_activeOwner, owner)) return;
        _activeOwner = null;
        await deactivate();
      });
}
