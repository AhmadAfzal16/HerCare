import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/presentation/therapy/pulse_analysis.dart';

/// Synthetic fingertip signal: slow drift + a pulse that darkens the image at
/// each beat + sensor noise, sampled with camera-like timing jitter.
List<PulseSample> camera(List<double> beatsMs,
    {double fps = 30, double noise = .15, int seed = 1, double drift = 3}) {
  final random = math.Random(seed);
  final end = beatsMs.last + 600;
  final samples = <PulseSample>[];
  for (var t = 0.0; t < end; t += 1000 / fps + (random.nextDouble() - .5) * 6) {
    var pulse = 0.0;
    for (final beat in beatsMs) {
      final dt = (t - beat) / 1000;
      if (dt > -.1 && dt < .6) {
        pulse += math.exp(-math.pow((dt - .12) / .08, 2));
      }
    }
    final value = 140 +
        drift * math.sin(t / 4000) -
        2.0 * pulse +
        noise * (random.nextDouble() - .5);
    samples.add(PulseSample(t, value));
  }
  return samples;
}

List<double> beats(int count, double Function(int) interval) {
  final out = <double>[300];
  for (var i = 1; i < count; i++) {
    out.add(out.last + interval(i));
  }
  return out;
}

void main() {
  test('camera reading recovers heart rate within 3 bpm at rest', () {
    for (final bpm in [58, 72, 95, 120]) {
      final ms = 60000 / bpm;
      final result = PulseAnalysis.fromCamera(
          camera(beats((30000 / ms).ceil() + 2, (_) => ms)));
      expect(result.ok, isTrue, reason: '$bpm bpm');
      expect((result.reading!.bpm - bpm).abs(), lessThanOrEqualTo(3),
          reason: '$bpm bpm');
      expect(result.reading!.source, 'camera');
    }
  });

  test('camera HRV tracks a real beat-to-beat change (relaxed vs tense)', () {
    // Alternating ±40 ms (RMSSD ≈ 80) vs ±8 ms (RMSSD ≈ 16).
    final relaxed = PulseAnalysis.fromCamera(
            camera(beats(40, (i) => 850 + (i.isEven ? 40 : -40)), seed: 3))
        .reading!;
    final tense = PulseAnalysis.fromCamera(
            camera(beats(45, (i) => 700 + (i.isEven ? 8 : -8)), seed: 4))
        .reading!;
    expect(relaxed.rmssdMs, isNotNull);
    expect(tense.rmssdMs, isNotNull);
    expect(relaxed.rmssdMs!, greaterThan(tense.rmssdMs! * 2));
    expect((relaxed.rmssdMs! - 80).abs(), lessThan(25));
  });

  test(
      'too short, flat (no finger) or very noisy signals are refused, not guessed',
      () {
    expect(PulseAnalysis.fromCamera(camera(beats(12, (_) => 800))).failure,
        PulseFailure.tooShort);
    final flat = [for (var t = 0.0; t < 30000; t += 33) PulseSample(t, 140)];
    expect(PulseAnalysis.fromCamera(flat).ok, isFalse);
    final shaky = camera(beats(40, (_) => 800), noise: 12, seed: 7);
    expect(PulseAnalysis.fromCamera(shaky).ok, isFalse);
  });

  test(
      'band intervals: artefacts are excluded and HRV computed only from clean neighbours',
      () {
    final clean = [for (var i = 0; i < 30; i++) 800.0 + (i.isEven ? 20 : -20)];
    final reading = PulseAnalysis.fromIntervals(clean, source: 'band').reading!;
    expect(reading.bpm, 75);
    expect(reading.rmssdMs, 40);
    final withArtefact = [...clean]..[10] = 1600; // a missed beat
    final kept =
        PulseAnalysis.fromIntervals(withArtefact, source: 'band').reading!;
    expect(kept.bpm, 75);
    expect(kept.rmssdMs, 40,
        reason: 'differences touching the artefact are dropped');
    final messy = [for (var i = 0; i < 30; i++) i % 3 == 0 ? 400.0 : 900.0];
    expect(PulseAnalysis.fromIntervals(messy, source: 'band').ok, isFalse);
  });
}
