import 'package:flutter_test/flutter_test.dart';
import 'package:omnis/core/playback_diagnostics.dart';
import 'package:omnis/core/playback_watchdog.dart';

import 'fakes/fake_playback_engine.dart';

/// [PlaybackRecovery] implements the recovery flow from §2 of the Omnis
/// 2.0 product spec: identify failure → attempt local recovery → reload →
/// retry once → mark failed → advance queue → record diagnostic →
/// continue playback. First direct unit coverage, made possible by
/// depending on the [PlaybackEngine] interface instead of a concrete
/// `AudioEngine` — see that class's doc.
void main() {
  late FakePlaybackEngine engine;
  late PlaybackDiagnosticsStore diagnostics;
  late PlaybackWatchdog watchdog;
  late PlaybackRecovery recovery;

  /// Seeds the diagnostics store the way [PlaybackWatchdog._fail] would
  /// before handing off to recovery — [PlaybackRecovery] itself never
  /// creates the initial (unrecovered) diagnostic, only replaces it with
  /// a recovered one, so a bare `recover()` call with nothing seeded is a
  /// deliberate no-op on the diagnostics store (see the null-check in
  /// `_markRecovered`).
  void seed(PlaybackFailureType type) {
    diagnostics.add(PlaybackDiagnostic(
      type: type,
      message: 'seeded failure',
      occurredAt: DateTime.now().toUtc(),
    ));
  }

  setUp(() {
    engine = FakePlaybackEngine();
    diagnostics = PlaybackDiagnosticsStore();
    watchdog = PlaybackWatchdog(
      engine: engine,
      diagnostics: diagnostics,
      recover: (_, __) async {},
    );
    recovery = PlaybackRecovery(
      engine: engine,
      diagnostics: diagnostics,
      watchdog: watchdog,
    );
    // Only the "resets the watchdog's counter" test below actually emits
    // events on the fake engine's streams; starting the watchdog here is
    // harmless for every other test since nothing emits without an
    // explicit engine.emit*() call, and this test's own `recover`
    // callback is a no-op so it can never race with a direct
    // `recovery.recover(...)` call made by a test.
    watchdog.start();
  });

  tearDown(() async {
    await watchdog.dispose();
    await engine.dispose();
  });

  test('outputDeviceLost resets the output device, reloads, and resumes '
      'playback', () async {
    seed(PlaybackFailureType.outputDeviceLost);

    await recovery.recover(PlaybackFailureType.outputDeviceLost);

    expect(engine.calls,
        ['setOutputDeviceToDefault', 'reloadCurrentSource(position: null)', 'play']);
    expect(diagnostics.latest?.recovered, isTrue);
    expect(diagnostics.latest?.recoveryAction,
        'Reset output device and resumed playback');
  });

  test('stuckLoading reloads and retries on the first attempt', () async {
    seed(PlaybackFailureType.stuckLoading);

    await recovery.recover(PlaybackFailureType.stuckLoading);

    expect(engine.calls, ['reloadCurrentSource(position: null)', 'play']);
    expect(diagnostics.latest?.recoveryAction, 'Reloaded the source and resumed');
    expect(recovery.retryCount, 1);
  });

  test('stuckLoading advances past the track once the retry limit is '
      'exceeded', () async {
    seed(PlaybackFailureType.stuckLoading);
    await recovery.recover(PlaybackFailureType.stuckLoading); // attempt 1: retry

    seed(PlaybackFailureType.stuckLoading);
    engine.calls.clear();
    await recovery.recover(PlaybackFailureType.stuckLoading); // attempt 2: give up

    expect(engine.calls, ['next(wrap: true)']);
    expect(diagnostics.latest?.recoveryAction,
        'Marked the track failed and advanced the queue');
  });

  test('repeatedQueueFailure stops playback rather than retrying', () async {
    seed(PlaybackFailureType.repeatedQueueFailure);

    await recovery.recover(PlaybackFailureType.repeatedQueueFailure);

    expect(engine.calls, ['stop']);
    expect(diagnostics.latest?.recoveryAction,
        'Stopped after repeated queue failures');
  });

  test('decoderException makes no engine calls — the skip already '
      'happened in the engine\'s own error path', () async {
    seed(PlaybackFailureType.decoderException);

    await recovery.recover(PlaybackFailureType.decoderException);

    expect(engine.calls, isEmpty);
    expect(diagnostics.latest?.recoveryAction, 'Skipped the unplayable track');
  });

  test('impossiblePosition reloads and seeks to zero on the first '
      'attempt, then advances on the second', () async {
    seed(PlaybackFailureType.impossiblePosition);
    await recovery.recover(PlaybackFailureType.impossiblePosition);
    expect(engine.calls, [
      'reloadCurrentSource(position: null)',
      'seek(0:00:00.000000)',
    ]);

    seed(PlaybackFailureType.impossiblePosition);
    engine.calls.clear();
    await recovery.recover(PlaybackFailureType.impossiblePosition);
    expect(engine.calls, ['next(wrap: true)']);
  });

  test('positionStalled reloads at the current position and resumes on '
      'the first attempt, then advances on the second', () async {
    engine.position = const Duration(seconds: 42);
    seed(PlaybackFailureType.positionStalled);
    await recovery.recover(PlaybackFailureType.positionStalled);
    expect(engine.calls,
        ['reloadCurrentSource(position: 0:00:42.000000)', 'play']);

    seed(PlaybackFailureType.positionStalled);
    engine.calls.clear();
    await recovery.recover(PlaybackFailureType.positionStalled);
    expect(engine.calls, ['next(wrap: true)']);
  });

  test('advancing past a failed track resets the watchdog\'s consecutive '
      'failure counter', () async {
    // Give the watchdog a nonzero counter the way a real failure would —
    // watchdog.start() was called in setUp, so this actually goes
    // through PlaybackWatchdog's own detection path, not just the seeded
    // diagnostics store.
    engine.emitError('boom');
    await Future<void>.delayed(Duration.zero);
    expect(watchdog.consecutiveFailures, 1);

    // stuckLoading past its retry limit is the path that calls
    // _advancePastFailedTrack, which is what resets the watchdog.
    seed(PlaybackFailureType.stuckLoading);
    await recovery.recover(PlaybackFailureType.stuckLoading); // attempt 1
    seed(PlaybackFailureType.stuckLoading);
    await recovery.recover(PlaybackFailureType.stuckLoading); // attempt 2: advances

    expect(watchdog.consecutiveFailures, 0);
  });

  test('reset() zeroes the retry counter, so the next failure gets a '
      'fresh retry budget', () async {
    seed(PlaybackFailureType.stuckLoading);
    await recovery.recover(PlaybackFailureType.stuckLoading);
    expect(recovery.retryCount, 1);

    recovery.reset();
    expect(recovery.retryCount, 0);

    seed(PlaybackFailureType.stuckLoading);
    engine.calls.clear();
    await recovery.recover(PlaybackFailureType.stuckLoading);

    // Retried again instead of advancing, because reset() gave it a
    // fresh budget.
    expect(engine.calls, ['reloadCurrentSource(position: null)', 'play']);
  });

  test('a custom retryLimit is honoured', () async {
    recovery = PlaybackRecovery(
      engine: engine,
      diagnostics: diagnostics,
      watchdog: watchdog,
      retryLimit: 2,
    );

    for (var i = 0; i < 2; i++) {
      seed(PlaybackFailureType.stuckLoading);
      engine.calls.clear();
      await recovery.recover(PlaybackFailureType.stuckLoading);
      expect(engine.calls, ['reloadCurrentSource(position: null)', 'play'],
          reason: 'attempt ${i + 1} should still be within the retry budget');
    }

    seed(PlaybackFailureType.stuckLoading);
    engine.calls.clear();
    await recovery.recover(PlaybackFailureType.stuckLoading);
    expect(engine.calls, ['next(wrap: true)'],
        reason: 'the 3rd attempt exceeds retryLimit: 2');
  });
}
