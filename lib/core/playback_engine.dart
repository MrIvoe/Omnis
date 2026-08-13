import 'dart:async';

import 'package:just_audio/just_audio.dart' show PlayerState;
import 'package:omnis/core/playback_state.dart';

/// The playback-engine surface [PlaybackWatchdog] and [PlaybackRecovery]
/// need to observe and act on.
///
/// Split out per §51.3 of the Omnis 2.0 product spec ("introduce stable
/// capability protocols... create one when another implementation is
/// realistically possible"). [AudioEngine] is the only real
/// implementation today, but depending on this interface rather than the
/// concrete class is what makes the watchdog/recovery policy unit
/// testable against a fake engine, instead of requiring a real
/// just_audio player and platform channels neither of which are
/// available in this project's test environment.
abstract interface class PlaybackEngine {
  /// Position stream (ticks at ~200ms).
  Stream<Duration> get positionStream;

  /// Playback state stream.
  Stream<PlayerState> get playerStateStream;

  /// Broadcast stream of raw playback errors from the native player.
  Stream<Object> get playbackErrors;

  /// Current track duration, or `null` if unknown/not loaded.
  Duration? get duration;

  /// Current position within the current track.
  Duration get position;

  /// Build a [PlaybackState] snapshot of the whole playback subsystem.
  PlaybackState captureState();

  /// Best-effort output-device reset (headphones/DAC vanished).
  Future<void> setOutputDeviceToDefault();

  /// Reload the currently loaded queue source — the "reinitialize the
  /// decoder" step of the playback recovery flow.
  Future<void> reloadCurrentSource({Duration? position});

  /// Start playing (resume).
  Future<void> play();

  /// Stop playback.
  Future<void> stop();

  /// Seek within the current track.
  Future<void> seek(Duration position);

  /// Skip to the next track. Returns false when there is no next track
  /// and [wrap] is false.
  Future<bool> next({bool wrap = false});
}
