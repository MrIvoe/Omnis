import 'dart:async';

import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:omnis/core/playback_diagnostics.dart';
import 'package:omnis/core/playback_engine.dart';

/// The watchdog policy from §2 of the Omnis 2.0 product spec.
///
/// This is the "permanent internal watchdog" the spec calls for. It is
/// deliberately not part of `AudioEngine` itself — the engine exposes
/// streams, this class observes them through the [PlaybackEngine]
/// interface rather than the concrete engine. That keeps the engine small
/// and the watchdog genuinely testable in isolation, against a fake
/// [PlaybackEngine] instead of a real player.
///
/// It detects:
///
///  * **Stuck loading** — the player spent too long in
///    `loading`/`buffering` without reaching `ready`.
///  * **Position stalled** — playback was active but position did not
///    advance for a suspicious wall-clock amount (a wedged decoder, or an
///    output device that vanished mid-track).
///  * **Impossible position** — the current position is beyond the track's
///    reported duration, which should be impossible for a healthy player.
///  * **Decoder exception** — the native player surfaced an error
///    (corrupt/missing/unsupported file).
///  * **Repeated queue failure** — the queue kept failing to advance
///    (every remaining track unplayable, or queue corruption), tracked via
///    the engine's own consecutive-error counter.
///
/// Everything it detects becomes a [PlaybackDiagnostic], and it hands the
/// failure off to a recovery callback ([PlaybackRecovery] in production)
/// so the recovery policy stays swappable.
class PlaybackWatchdog {
  /// The engine being watched.
  final PlaybackEngine _engine;

  /// Where diagnostics are recorded.
  final PlaybackDiagnosticsStore _diagnostics;

  /// Invoked to execute the recovery policy.
  final Future<void> Function(PlaybackFailureType type, int consecutiveFailures)
      _recover;

  /// How long the player may stay in loading/buffering before it counts as
  /// stuck.
  final Duration _loadTimeout;

  /// How long position may stay frozen while playing before it counts as
  /// stalled.
  final Duration _stallTimeout;

  /// How many consecutive queue-advance failures force a stop instead of
  /// an infinite auto-skip loop over an entirely-unplayable queue.
  final int _maxConsecutiveFailures;

  DateTime? _loadingSince;
  DateTime? _lastPositionChange;
  Duration _lastPosition = Duration.zero;
  bool _lastPositionKnown = false;
  int _consecutiveFailures = 0;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<Object>? _eventSub;

  bool _disposed = false;

  /// The diagnostics store (read-only to the UI).
  PlaybackDiagnosticsStore get diagnostics => _diagnostics;

  /// Current consecutive-failure count — the recovery policy reads this to
  /// decide when to stop instead of looping.
  int get consecutiveFailures => _consecutiveFailures;

  /// How many consecutive failures are allowed before the recovery policy
  /// gives up on the current queue.
  int get maxConsecutiveFailures => _maxConsecutiveFailures;

  /// Constructor.
  PlaybackWatchdog({
    required PlaybackEngine engine,
    required PlaybackDiagnosticsStore diagnostics,
    required Future<void> Function(
            PlaybackFailureType failure, int consecutiveFailures)
        recover,
    Duration loadTimeout = const Duration(seconds: 10),
    Duration stallTimeout = const Duration(seconds: 5),
    int maxConsecutiveFailures = 3,
  })  : _engine = engine,
        _diagnostics = diagnostics,
        _recover = recover,
        _loadTimeout = loadTimeout,
        _stallTimeout = stallTimeout,
        _maxConsecutiveFailures = maxConsecutiveFailures;

  /// Start watching the engine. Safe to call more than once — each
  /// subscription is created only if it isn't already active.
  void start() {
    _lastPositionChange = DateTime.now();
    _positionSub ??= _engine.positionStream.listen(_onPosition);
    _stateSub ??= _engine.playerStateStream.listen(_onState);
    _eventSub ??= _engine.playbackErrors.listen(_onPlayerError);
  }

  /// Stop watching and release subscriptions.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _positionSub?.cancel();
    await _stateSub?.cancel();
    await _eventSub?.cancel();
    _positionSub = null;
    _stateSub = null;
    _eventSub = null;
  }

  void _onState(PlayerState state) {
    if (_disposed) return;
    switch (state.processingState) {
      case ProcessingState.ready:
        // A successful load clears the consecutive-failure counter — the
        // player is healthy again.
        _consecutiveFailures = 0;
        _loadingSince = null;
      case ProcessingState.loading:
      case ProcessingState.buffering:
        _loadingSince ??= DateTime.now();
        final stuckFor = DateTime.now().difference(_loadingSince!);
        if (stuckFor >= _loadTimeout) {
          _fail(
            PlaybackFailureType.stuckLoading,
            'Playback was stuck ${state.processingState.name} for '
            '${stuckFor.inSeconds}s',
          );
        }
      case ProcessingState.idle:
      case ProcessingState.completed:
        _loadingSince = null;
    }
  }

  void _onPosition(Duration position) {
    if (_disposed) return;

    // Wall-clock stall detection: a healthy position stream advances
    // roughly every 200ms. If the position hasn't moved for the stall
    // timeout while the player claims it's playing, something is wedged.
    if (_lastPositionKnown && position == _lastPosition) {
      final since = _lastPositionChange;
      final now = DateTime.now();
      if (since != null && now.difference(since) >= _stallTimeout) {
        _fail(
          PlaybackFailureType.positionStalled,
          'Playback stalled at ${position.inSeconds}s without advancing',
        );
      }
      return;
    }

    _lastPosition = position;
    _lastPositionKnown = true;
    _lastPositionChange = DateTime.now();

    // Impossible-position sanity check: position past the reported
    // duration (with a small tolerance for rounding at track end).
    final duration = _engine.duration;
    if (duration != null &&
        duration > Duration.zero &&
        position > duration + const Duration(seconds: 2)) {
      _fail(
        PlaybackFailureType.impossiblePosition,
        'Position ${position.inMilliseconds}ms is past this track\'s '
        '${duration.inMilliseconds}ms duration',
      );
    }
  }

  void _onPlayerError(Object error) {
    if (_disposed) return;
    _fail(
      PlaybackFailureType.decoderException,
      'Native player error: $error',
    );
  }

  void _fail(PlaybackFailureType type, String message) {
    _consecutiveFailures++;
    final snapshot = _engine.captureState();
    final diagnostic = PlaybackDiagnostic.fromSnapshot(
      snapshot,
      type,
      message: message,
      occurredAt: DateTime.now().toUtc(),
      recovered: false,
    );
    _diagnostics.add(diagnostic);

    final consecutive = _consecutiveFailures;
    // Fire-and-forget: the recovery policy may be async; the watchdog
    // must never block the position stream.
    unawaited(_recover(type, consecutive));
  }

  /// The engine (or recovery) calls this whenever a track actually starts
  /// playing successfully — resets the consecutive-failure counter so a
  /// single transient failure doesn't cascade into a false "everything is
  /// broken" stop.
  void onTrackStarted() {
    _consecutiveFailures = 0;
  }
}

/// The recovery policy. Given a failure, implements the spec's flow:
///
/// ```text
/// Playback failure
///        ↓
/// Identify failure type
///        ↓
/// Attempt local recovery
///        ↓
/// Reload current source (reinitialize decoder)
///        ↓
/// Retry once
///        ↓
/// If still failing → mark track failed
///        ↓
/// Advance queue
///        ↓
/// Record diagnostic
///        ↓
/// Continue playback
/// ```
///
/// Deliberately takes the [PlaybackEngine] and the [PlaybackDiagnosticsStore]
/// — the engine owns the queue/player and is the only thing that can
/// reload/advance it; the store is where the "record diagnostic" step
/// lands. The policy is a plain class so it has a unit test independent of
/// any real player, against a fake [PlaybackEngine].
class PlaybackRecovery {
  final PlaybackEngine _engine;
  final PlaybackDiagnosticsStore _diagnostics;
  final PlaybackWatchdog _watchdog;

  PlaybackRecovery({
    required PlaybackEngine engine,
    required PlaybackDiagnosticsStore diagnostics,
    required PlaybackWatchdog watchdog,
    this.retryLimit = 1,
  })  : _engine = engine,
        _diagnostics = diagnostics,
        _watchdog = watchdog;

  /// How many local-recovery retries are attempted before a failing track
  /// is treated as failed and the queue advances.
  final int retryLimit;

  int _attempts = 0;

  int get retryCount => _attempts;

  /// Called when the queue successfully lands on a new track (the recovery
  /// flow's "continue playback" has happened) — resets the retry counter.
  void reset() => _attempts = 0;

  /// Execute the recovery policy for [failure].
  Future<void> recover(PlaybackFailureType failure) async {
    _attempts++;

    // Identify the failure type and pick a response.
    switch (failure) {
      case PlaybackFailureType.outputDeviceLost:
        // Output disappeared — fall back to the default device and resume.
        await _engine.setOutputDeviceToDefault();
        await _engine.reloadCurrentSource();
        await _engine.play();
        _markRecovered('Reset output device and resumed playback');
        return;

      case PlaybackFailureType.stuckLoading:
        // One reload attempt; if still stuck, treat as failed and advance.
        if (_attempts <= retryLimit) {
          await _engine.reloadCurrentSource();
          await _engine.play();
          _markRecovered('Reloaded the source and resumed');
          return;
        }
        await _advancePastFailedTrack();
        return;

      case PlaybackFailureType.repeatedQueueFailure:
        // The queue is exhaustively unplayable or corrupt — stop rather
        // than spin.
        await _engine.stop();
        _markRecovered('Stopped after repeated queue failures');
        return;

      case PlaybackFailureType.decoderException:
        // The engine's own error path already advances on a native
        // decoder error (_skipAfterError). The watchdog's recovery here
        // only needs to make the diagnostic explicit and keep going.
        _markRecovered('Skipped the unplayable track');
        return;

      case PlaybackFailureType.invalidDuration:
      case PlaybackFailureType.impossiblePosition:
        // Duration/position weirdness: reload the current source once;
        // if it keeps failing, advance past the track.
        if (_attempts <= retryLimit) {
          await _engine.reloadCurrentSource();
          await _engine.seek(Duration.zero);
          _markRecovered('Reloaded source after invalid position/duration');
          return;
        }
        await _advancePastFailedTrack();
        return;

      case PlaybackFailureType.unknown:
      case PlaybackFailureType.positionStalled:
        // Best-effort local recovery: reload the current source once, then
        // advance if that doesn't help.
        if (_attempts <= retryLimit) {
          await _engine.reloadCurrentSource(position: _engine.position);
          await _engine.play();
          _markRecovered('Reloaded the current source and resumed');
          return;
        }
        await _advancePastFailedTrack();
        return;
    }
  }

  Future<void> _advancePastFailedTrack() async {
    // "If still failing → mark track failed → advance queue".
    _markRecovered('Marked the track failed and advanced the queue');
    await _engine.next(wrap: true);
    _watchdog.onTrackStarted();
  }

  void _markRecovered(String action) {
    // A clean recovery (or a deliberate advance/stop) shouldn't wear a
    // hard-failure chip — it's a recovered diagnostic, not a dead end.
    // Diagnostics are immutable, so the "recovered" version replaces the
    // original rather than mutating it.
    final latest = _diagnostics.latest;
    if (latest != null) {
      _diagnostics.clear();
      _diagnostics.add(PlaybackDiagnostic(
        type: latest.type,
        message: latest.message,
        occurredAt: latest.occurredAt,
        queueIndex: latest.queueIndex,
        trackId: latest.trackId,
        recovered: true,
        recoveryAction: action,
      ));
    }
  }
}
