import 'dart:math' as math;

/// One brightness sample from the camera (fingertip over lens + flash).
class PulseSample {
  const PulseSample(this.timeMs, this.value);
  final double timeMs;
  final double value;
}

/// A short heart reading. HRV is RMSSD in milliseconds (Muñoz et al. 2015:
/// valid from short recordings). Camera readings are approximate.
class PulseReading {
  const PulseReading(
      {required this.bpm,
      this.rmssdMs,
      required this.beats,
      required this.source});
  final int bpm;
  final int? rmssdMs;
  final int beats;

  /// 'camera' or 'band'.
  final String source;
}

enum PulseFailure { tooShort, noisy, outOfRange }

class PulseResult {
  const PulseResult.ok(PulseReading this.reading) : failure = null;
  const PulseResult.failed(PulseFailure this.failure) : reading = null;
  final PulseReading? reading;
  final PulseFailure? failure;
  bool get ok => reading != null;
}

/// Plain-Dart photoplethysmography (PPG) and beat-interval analysis, so it
/// can be tested without a camera. Pipeline: resample to 30 Hz → remove slow
/// drift → smooth → find pulse peaks → reject implausible beat intervals →
/// heart rate from the median interval, RMSSD only from clean neighbours.
abstract final class PulseAnalysis {
  static const _rate = 30.0; // Hz after resampling
  static const minSeconds = 20;

  static PulseResult fromCamera(List<PulseSample> samples) {
    if (samples.length < 2) {
      return const PulseResult.failed(PulseFailure.tooShort);
    }
    final span = samples.last.timeMs - samples.first.timeMs;
    if (span < minSeconds * 1000 || samples.length < span / 1000 * 12) {
      return const PulseResult.failed(PulseFailure.tooShort);
    }
    final signal = _resample(samples);
    // Blood arriving makes the fingertip darker, so invert: peaks = beats.
    final detrended = _subtract(signal, _movingAverage(signal, _rate.round()));
    final smooth = _movingAverage(detrended, 4).map((v) => -v).toList();
    final peaks = _peaks(smooth);
    final intervals = <double>[
      for (var i = 1; i < peaks.length; i++)
        (peaks[i] - peaks[i - 1]) * 1000 / _rate
    ];
    return fromIntervals(intervals, source: 'camera', minimumAcceptance: .7);
  }

  /// Beat-to-beat intervals in ms (camera peaks, or a Bluetooth band's RR
  /// intervals). Intervals more than 25% from the median are treated as
  /// movement or missed beats and excluded (a common artefact rule).
  static PulseResult fromIntervals(List<double> intervals,
      {required String source, double minimumAcceptance = .8}) {
    final plausible = intervals.where((ms) => ms >= 333 && ms <= 1500).toList();
    if (plausible.length < 15) {
      return PulseResult.failed(intervals.length < 15
          ? PulseFailure.tooShort
          : PulseFailure.outOfRange);
    }
    final median = _median(plausible);
    final accepted = [
      for (final ms in intervals)
        ms >= 333 && ms <= 1500 && (ms - median).abs() <= median * .25
    ];
    final count = accepted.where((ok) => ok).length;
    if (count < 15 || count / intervals.length < minimumAcceptance) {
      return const PulseResult.failed(PulseFailure.noisy);
    }
    // Heart rate from the mean of clean intervals (standard practice); the
    // median above is only used to decide which intervals are clean.
    final clean = [
      for (var i = 0; i < intervals.length; i++)
        if (accepted[i]) intervals[i]
    ];
    final bpm =
        (60000 / (clean.reduce((a, b) => a + b) / clean.length)).round();
    if (bpm < 35 || bpm > 220) {
      return const PulseResult.failed(PulseFailure.outOfRange);
    }
    final differences = <double>[
      for (var i = 1; i < intervals.length; i++)
        if (accepted[i] && accepted[i - 1]) intervals[i] - intervals[i - 1]
    ];
    // HRV needs enough clean neighbouring beats; otherwise heart rate only.
    final cleanEnough =
        count / intervals.length >= .85 && differences.length >= 10;
    final rmssd = cleanEnough
        ? math
            .sqrt(differences.map((d) => d * d).reduce((a, b) => a + b) /
                differences.length)
            .round()
        : null;
    return PulseResult.ok(PulseReading(
        bpm: bpm,
        rmssdMs: rmssd != null && rmssd >= 1 && rmssd <= 300 ? rmssd : null,
        beats: count,
        source: source));
  }

  static List<double> _resample(List<PulseSample> samples) {
    final start = samples.first.timeMs, end = samples.last.timeMs;
    final out = <double>[];
    var j = 0;
    for (var t = start; t <= end; t += 1000 / _rate) {
      while (j < samples.length - 2 && samples[j + 1].timeMs < t) {
        j++;
      }
      final a = samples[j], b = samples[j + 1];
      final span = b.timeMs - a.timeMs;
      final f = span <= 0 ? 0.0 : ((t - a.timeMs) / span).clamp(0.0, 1.0);
      out.add(a.value + (b.value - a.value) * f);
    }
    return out;
  }

  static List<double> _movingAverage(List<double> values, int window) {
    final half = window ~/ 2;
    final prefix = List<double>.filled(values.length + 1, 0);
    for (var i = 0; i < values.length; i++) {
      prefix[i + 1] = prefix[i] + values[i];
    }
    return [
      for (var i = 0; i < values.length; i++)
        () {
          final lo = math.max(0, i - half),
              hi = math.min(values.length, i + half + 1);
          return (prefix[hi] - prefix[lo]) / (hi - lo);
        }()
    ];
  }

  static List<double> _subtract(List<double> a, List<double> b) =>
      [for (var i = 0; i < a.length; i++) a[i] - b[i]];

  /// Local maxima at least 0.33 s apart (≤180 bpm) and above an adaptive
  /// threshold; positions refined by parabolic interpolation, because 30 Hz
  /// sampling alone would quantise beat timing to 33 ms.
  static List<double> _peaks(List<double> s) {
    final positive = s.where((v) => v > 0).toList()..sort();
    if (positive.isEmpty) return const [];
    final threshold = positive[(positive.length * .5).floor()] * .5;
    final minGap = (_rate * .33).round();
    final peaks = <double>[];
    var last = -minGap;
    for (var i = 1; i < s.length - 1; i++) {
      if (s[i] <= threshold || s[i] < s[i - 1] || s[i] < s[i + 1]) continue;
      final lo = math.max(0, i - minGap),
          hi = math.min(s.length - 1, i + minGap);
      var isMax = true;
      for (var k = lo; k <= hi; k++) {
        if (s[k] > s[i]) {
          isMax = false;
          break;
        }
      }
      if (!isMax || i - last < minGap) continue;
      final denominator = s[i - 1] - 2 * s[i] + s[i + 1];
      final offset = denominator == 0
          ? 0.0
          : (.5 * (s[i - 1] - s[i + 1]) / denominator).clamp(-.5, .5);
      peaks.add(i + offset);
      last = i;
    }
    return peaks;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
