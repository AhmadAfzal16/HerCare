import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hercare/presentation/therapy/meditation_focus_gate.dart';

void main() {
  test('stale delayed grant releases before a new owner can activate',
      () async {
    final gate = MeditationFocusGate();
    final oldOwner = Object(), newOwner = Object();
    final granted = Completer<bool>();
    final releasing = Completer<void>();
    final events = <String>[];
    var oldCurrent = true;
    final old = gate.acquire(oldOwner,
        activate: () async {
          events.add('old activate');
          return granted.future;
        },
        deactivate: () async {
          events.add('old release');
          await releasing.future;
        },
        isCurrent: () => oldCurrent);
    await Future<void>.delayed(Duration.zero);
    oldCurrent = false;
    final next = gate.acquire(newOwner,
        activate: () async {
          events.add('new activate');
          return true;
        },
        deactivate: () async {
          events.add('new release');
        },
        isCurrent: () => true);
    granted.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['old activate', 'old release']);
    releasing.complete();
    expect(await old, isFalse);
    expect(await next, isTrue);
    expect(events, ['old activate', 'old release', 'new activate']);
  });

  test('an old release queued after a new lease cannot release the new owner',
      () async {
    final gate = MeditationFocusGate();
    final oldOwner = Object(), newOwner = Object();
    final events = <String>[];
    expect(
        await gate.acquire(oldOwner,
            activate: () async => true,
            deactivate: () async => events.add('old stale release'),
            isCurrent: () => true),
        isTrue);
    final next = gate.acquire(newOwner,
        activate: () async {
          events.add('new activate');
          return true;
        },
        deactivate: () async => events.add('new stale release'),
        isCurrent: () => true);
    final obsolete = gate.release(oldOwner,
        deactivate: () async => events.add('obsolete release'));
    expect(await next, isTrue);
    await obsolete;
    expect(events, ['new activate']);
    await gate.release(newOwner,
        deactivate: () async => events.add('new release'));
    expect(events, ['new activate', 'new release']);
    await gate.release(newOwner,
        deactivate: () async => events.add('duplicate release'));
    expect(events, ['new activate', 'new release']);
  });

  test('activation and deactivation failures do not poison the serialized tail',
      () async {
    final gate = MeditationFocusGate();
    final first = Object(), second = Object(), third = Object();
    await expectLater(
        gate.acquire(first,
            activate: () async => throw StateError('native activation failed'),
            deactivate: () async {},
            isCurrent: () => true),
        throwsStateError);
    expect(
        await gate.acquire(second,
            activate: () async => true,
            deactivate: () async {},
            isCurrent: () => true),
        isTrue);
    await expectLater(
        gate.release(second,
            deactivate: () async => throw StateError('native release failed')),
        throwsStateError);
    expect(
        await gate.acquire(third,
            activate: () async => true,
            deactivate: () async {},
            isCurrent: () => true),
        isTrue);
    var released = false;
    await gate.release(third, deactivate: () async => released = true);
    expect(released, isTrue);
  });

  test('queued request that becomes stale never activates or deactivates',
      () async {
    final gate = MeditationFocusGate();
    final grant = Completer<bool>();
    final blocker = gate.acquire(Object(),
        activate: () => grant.future,
        deactivate: () async {},
        isCurrent: () => true);
    var current = true, activated = false, deactivated = false;
    final stale = gate.acquire(Object(),
        activate: () async {
          activated = true;
          return true;
        },
        deactivate: () async {
          deactivated = true;
        },
        isCurrent: () => current);
    current = false;
    grant.complete(true);
    expect(await blocker, isTrue);
    expect(await stale, isFalse);
    expect(activated, isFalse);
    expect(deactivated, isFalse);
  });

  test('denied activation does not acquire or release another owners lease',
      () async {
    final gate = MeditationFocusGate();
    final owner = Object();
    expect(
        await gate.acquire(owner,
            activate: () async => true,
            deactivate: () async {},
            isCurrent: () => true),
        isTrue);
    var deniedRelease = false, actualRelease = false;
    expect(
        await gate.acquire(Object(),
            activate: () async => false,
            deactivate: () async => deniedRelease = true,
            isCurrent: () => true),
        isFalse);
    await gate.release(owner, deactivate: () async => actualRelease = true);
    expect(deniedRelease, isFalse);
    expect(actualRelease, isTrue);
  });
}
