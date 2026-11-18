import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/presentation/therapy/breathing_band_panel.dart';
import 'package:hercare/presentation/therapy/pulse_analysis.dart';
import 'package:hercare/presentation/therapy/pulse_check_screen.dart';

void main() {
  tearDown(() => HeartBandFeed.instance.update(live: false));

  Future<PulseReading?> open(WidgetTester tester, {int seconds = 30}) async {
    PulseReading? result;
    var closed = false;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<PulseReading>(
                      MaterialPageRoute(
                          builder: (_) => PulseCheckScreen(
                              isUrdu: false,
                              after: false,
                              seconds: seconds,
                              findCameras: () async => const [])));
                  closed = true;
                },
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(closed, isFalse);
    return result;
  }

  testWidgets(
      'no camera available: explains and lets her skip, nothing returned',
      (tester) async {
    await open(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('camera or flash is not available'),
        findsOneWidget);
    await tester.tap(find.byKey(const Key('pulse-skip')));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets(
      'connected band: beat intervals become heart rate and variability',
      (tester) async {
    HeartBandFeed.instance.update(live: true, bpm: 75);
    PulseReading? reading;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => TextButton(
                onPressed: () async => reading = await Navigator.of(context)
                    .push<PulseReading>(MaterialPageRoute(
                        builder: (_) => const PulseCheckScreen(
                            isUrdu: false, after: true, seconds: 1))),
                child: const Text('open')))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Heart check — after'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pulse-use-band')));
    await tester.pump();
    for (var i = 0; i < 20; i++) {
      HeartBandFeed.instance
          .update(live: true, bpm: 75, intervals: [i.isEven ? 820 : 780]);
    }
    // The band reading counts timer ticks, so fake time drives it to the end.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await tester.pumpAndSettle();
    expect(find.text('75 beats per minute'), findsOneWidget);
    expect(find.text('Heart-rate variability: 40 ms'), findsOneWidget);
    expect(find.text('Measured with your band.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pulse-use-reading')));
    await tester.pumpAndSettle();
    expect(reading?.bpm, 75);
    expect(reading?.rmssdMs, 40);
    expect(reading?.source, 'band');
  });
}
