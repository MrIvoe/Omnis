import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:omnis/core/playback_diagnostics.dart';
import 'package:omnis/core/playback_watchdog.dart';

import 'fakes/fake_playback_engine.dart';

/// [PlaybackWatchdog] implements §2 of the Omnis 2.0 product spec's
/// "permanent internal watchdog" — this is the first time it has direct
/// unit coverage, made possible by depending on the [PlaybackEngine]
/// interface (see that class's doc) instead of a concrete `AudioEngine`.
void main() {
  late FakePlaybackEngine engine;
  late PlaybackDiagnosticsStore diagnostics;
  late List<(dynamic type, int consecutive)> recoverCalls;
  late PlaybackWatchdog watchdog;

  PlaybackWatchdog makeWatchdog({
    Duration loadTimeout = const Duration(seconds: 10),
    Duration stallTimeout = const Duration(seconds: 5),
    int maxConsecutiveFailures = 3,
  }) {
    return PlaybackWatchdog(
      engine: engine,
      diagnostics: diagnostics,
      recover: (type, consecutive) async {
        recoverCalls.add((type, consecutive));
      },
      loadTimeout: loadTimeout,
      stallTimeout: stallTimeout,
      maxConsecutiveFailures: maxConsecutiveFailures,
    );
  }

  setUp(() {
    engine = FakePlaybackEngine();
    diagnostics = PlaybackDiagnosticsStore();
    recoverCalls = [];
  });

  tearDown(() async {
    await watchdog.dispose();
    await engine.dispose();
  });

  test('a freshly started watchdog with no events reports zero '
      'consecutive failures and no diagnostics', () {
    watchdog = makeWatchdog();
    watchdog.start();

    expect(watchdog.consecutiveFailures, 0);
    expect(diagnostics.diagnostics, isEmpty);
    expect(recoverCalls, isEmpty);
  });

  test('a decoder exception on playbackErrors is recorded as a hard '
      'failure and handed to the recovery callback', () async {
    watchdog = makeWatchdog();
    watchdog.start();

    engine.emitError('boom: corrupt file');
    await Future<void>.delayed(Duration.zero);

    expect(watchdog.consecutiveFailures, 1);
    expect(diagnostics.latest?.type, PlaybackFailureType.decoderException);
    expect(diagnostics.latest?.message, contains('boom: corrupt file'));
    expect(diagnostics.latest?.isHardFailure, isTrue);
    expect(recoverCalls, [(PlaybackFailureType.decoderException, 1)]);
  });

  test('an impossible position (past the reported duration) is detected '
      'immediately, no timing required', () async {
    watchdog = makeWatchdog();
    watchdog.start();
    engine.duration = const Duration(seconds: 10);

    engine.emitPosition(const Duration(seconds: 20));
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.latest?.type, PlaybackFailureType.impossiblePosition);
    expect(recoverCalls, [(PlaybackFailureType.impossiblePosition, 1)]);
  });

  test('a position within 2s of the duration is not flagged as '
      'impossible (end-of-track rounding tolerance)', () async {
    watchdog = makeWatchdog();
    watchdog.start();
    engine.duration = const Duration(seconds: 10);

    engine.emitPosition(const Duration(seconds: 11, milliseconds: 500));
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.diagnostics, isEmpty);
  });

  test('position stuck at the same value beyond the stall timeout is '
      'detected as positionStalled', () async {
    watchdog = makeWatchdog(stallTimeout: const Duration(milliseconds: 30));
    watchdog.start();

    engine.emitPosition(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    engine.emitPosition(const Duration(seconds: 5)); // same value again
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.latest?.type, PlaybackFailureType.positionStalled);
  });

  test('position that keeps advancing never trips the stall detector',
      () async {
    watchdog = makeWatchdog(stallTimeout: const Duration(milliseconds: 30));
    watchdog.start();

    engine.emitPosition(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    engine.emitPosition(const Duration(seconds: 6)); // advanced, not stuck
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.diagnostics, isEmpty);
  });

  test('staying in loading beyond the load timeout is detected as '
      'stuckLoading', () async {
    watchdog = makeWatchdog(loadTimeout: const Duration(milliseconds: 30));
    watchdog.start();

    engine.emitState(PlayerState(false, ProcessingState.loading));
    await Future<void>.delayed(const Duration(milliseconds: 60));
    engine.emitState(PlayerState(false, ProcessingState.loading));
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.latest?.type, PlaybackFailureType.stuckLoading);
  });

  test('reaching ready before the load timeout never trips stuckLoading',
      () async {
    watchdog = makeWatchdog(loadTimeout: const Duration(milliseconds: 500));
    watchdog.start();

    engine.emitState(PlayerState(false, ProcessingState.loading));
    engine.emitState(PlayerState(true, ProcessingState.ready));
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.diagnostics, isEmpty);
  });

  test('reaching ready resets the consecutive-failure counter', () async {
    watchdog = makeWatchdog();
    watchdog.start();

    engine.emitError('first failure');
    await Future<void>.delayed(Duration.zero);
    expect(watchdog.consecutiveFailures, 1);

    engine.emitState(PlayerState(true, ProcessingState.ready));
    await Future<void>.delayed(Duration.zero);

    expect(watchdog.consecutiveFailures, 0);
  });

  test('onTrackStarted() resets the consecutive-failure counter', () async {
    watchdog = makeWatchdog();
    watchdog.start();

    engine.emitError('first failure');
    await Future<void>.delayed(Duration.zero);
    expect(watchdog.consecutiveFailures, 1);

    watchdog.onTrackStarted();

    expect(watchdog.consecutiveFailures, 0);
  });

  test('consecutive failures accumulate across repeated errors', () async {
    watchdog = makeWatchdog();
    watchdog.start();

    engine.emitError('failure 1');
    await Future<void>.delayed(Duration.zero);
    engine.emitError('failure 2');
    await Future<void>.delayed(Duration.zero);

    expect(watchdog.consecutiveFailures, 2);
    expect(recoverCalls, [
      (PlaybackFailureType.decoderException, 1),
      (PlaybackFailureType.decoderException, 2),
    ]);
  });

  test('dispose() stops observing — events after dispose produce no new '
      'diagnostics', () async {
    watchdog = makeWatchdog();
    watchdog.start();
    await watchdog.dispose();

    engine.emitError('should be ignored');
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.diagnostics, isEmpty);
  });

  test('start() is idempotent — calling it twice does not double-subscribe '
      '(a single error only produces one diagnostic)', () async {
    watchdog = makeWatchdog();
    watchdog.start();
    watchdog.start();

    engine.emitError('boom');
    await Future<void>.delayed(Duration.zero);

    expect(diagnostics.diagnostics, hasLength(1));
  });
}
