import 'dart:async';

/// Loops a marked section `[A, B]` of whatever is currently playing,
/// indefinitely, until cleared — a common practicing/DJ feature (Poweramp,
/// Musicolet, most desktop players all have it).
///
/// Split out of `AudioEngine` per §51.2 of the Omnis 2.0 product spec
/// ("break up the large AudioEngine... public engine facade can remain
/// tiny"). Deliberately decoupled from `just_audio`'s `AudioPlayer` —
/// it depends only on a position stream, a way to read the current
/// position, and a way to seek — so it has a unit test independent of any
/// real player, the same rationale [AudioEngine.crossfadeVolumes] already
/// uses for its own pure-function split.
class AbRepeatController {
  final Stream<Duration> _positionStream;
  final Duration Function() _currentPosition;
  final Future<void> Function(Duration) _seek;

  Duration? _loopA;
  Duration? _loopB;
  StreamSubscription<Duration>? _sub;

  AbRepeatController({
    required Stream<Duration> positionStream,
    required Duration Function() currentPosition,
    required Future<void> Function(Duration) seek,
  })  : _positionStream = positionStream,
        _currentPosition = currentPosition,
        _seek = seek;

  /// The current A-B loop points, or `null` if A-B repeat is off.
  (Duration a, Duration b)? get range =>
      (_loopA != null && _loopB != null) ? (_loopA!, _loopB!) : null;

  /// Point A, once marked — set even before B is marked (and thus before
  /// looping actually starts), so UI can show a mid-way "A marked, tap
  /// again for B" state distinct from both "off" and "looping."
  Duration? get markerA => _loopA;

  /// Marks point A at [position] (defaults to the current position).
  /// Clears any previously completed loop until [markB] is also called —
  /// a lone A point does nothing yet.
  void markA([Duration? position]) {
    _loopA = position ?? _currentPosition();
    _loopB = null;
  }

  /// Marks point B and, if it's after A, starts looping between them
  /// immediately. B at or before A is rejected (a zero/negative loop makes
  /// no sense) rather than silently doing nothing useful. Returns whether
  /// the loop actually started.
  bool markB([Duration? position]) {
    final a = _loopA;
    if (a == null) return false;
    final b = position ?? _currentPosition();
    if (b <= a) return false;
    _loopB = b;
    _sub ??= _positionStream.listen(_onPosition);
    return true;
  }

  /// Clears A-B repeat and lets playback continue normally.
  void clear() {
    _loopA = null;
    _loopB = null;
    _sub?.cancel();
    _sub = null;
  }

  void _onPosition(Duration position) {
    final b = _loopB;
    if (b == null) return;
    if (position >= b) {
      unawaited(_seek(_loopA!));
    }
  }

  /// Releases the position subscription — call once, from the owner's own
  /// `dispose()`.
  Future<void> dispose() async {
    await _sub?.cancel();
  }
}
