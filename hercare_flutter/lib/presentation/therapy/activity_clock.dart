/// Counts foreground activity time using a monotonic clock, not wall time.
/// Call [pause] whenever an activity is hidden, paused, or reviewing a save.
class ActiveTherapyClock {
  ActiveTherapyClock({Duration Function()? elapsedSource}) {
    final stopwatch = Stopwatch()..start();
    _elapsedSource = elapsedSource ?? (() => stopwatch.elapsed);
  }

  late final Duration Function() _elapsedSource;
  Duration _accumulated = Duration.zero;
  Duration? _segmentStart;

  bool get running => _segmentStart != null;

  Duration get elapsed {
    final start = _segmentStart;
    final segment = start == null ? Duration.zero : _elapsedSource() - start;
    return _accumulated + (segment.isNegative ? Duration.zero : segment);
  }

  int get seconds => elapsed.inSeconds.clamp(0, 7200);

  /// The API uses whole seconds; a genuine sub-second activity rounds up.
  int get recordedSeconds =>
      ((elapsed.inMilliseconds + 999) ~/ 1000).clamp(1, 7200);

  void resume() => _segmentStart ??= _elapsedSource();

  void pause() {
    _accumulated = elapsed;
    _segmentStart = null;
  }
}
