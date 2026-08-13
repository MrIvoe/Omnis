import 'dart:async';

import 'package:just_audio/just_audio.dart' show PlayerState;
import 'package:omnis/core/app_settings.dart' show RepeatMode;
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/playback_engine.dart';
import 'package:omnis/core/playback_state.dart';

/// A controllable in-memory [PlaybackEngine] double for testing
/// [PlaybackWatchdog]/[PlaybackRecovery] without a real just_audio player
/// or platform channels — see [PlaybackEngine]'s class doc for why this
/// seam exists.
///
/// Tests drive it by calling [emitPosition]/[emitState]/[emitError] and
/// setting [duration]/[position] directly, then assert against [calls] —
/// an ordered log of every transport method invoked (e.g.
/// `'reloadCurrentSource(position: 0:00:05.000000)'`).
class FakePlaybackEngine implements PlaybackEngine {
  final _positionController = StreamController<Duration>.broadcast();
  final _playerStateController = StreamController<PlayerState>.broadcast();
  final _errorsController = StreamController<Object>.broadcast();

  @override
  Duration? duration = const Duration(minutes: 3);

  @override
  Duration position = Duration.zero;

  /// Ordered log of every transport method this fake was called with.
  final List<String> calls = [];

  /// If set, [next] returns this instead of the default `true`.
  bool nextReturnValue = true;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;

  @override
  Stream<Object> get playbackErrors => _errorsController.stream;

  @override
  PlaybackState captureState() => PlaybackState(
        queue: [
          BaseTrack(
            id: 'fake-track',
            title: 'Fake Track',
            artists: const ['Fake Artist'],
            album: 'Fake Album',
            duration: 180,
            type: TrackType.local,
          ),
        ],
        currentIndex: 0,
        position: position,
        wasPlaying: true,
        shuffleEnabled: false,
        repeatMode: RepeatMode.off,
        volume: 1.0,
        speed: 1.0,
        pitch: 1.0,
        skipSilenceEnabled: false,
        gaplessEnabled: true,
        crossfadeDuration: Duration.zero,
      );

  @override
  Future<void> setOutputDeviceToDefault() async {
    calls.add('setOutputDeviceToDefault');
  }

  @override
  Future<void> reloadCurrentSource({Duration? position}) async {
    calls.add('reloadCurrentSource(position: $position)');
  }

  @override
  Future<void> play() async {
    calls.add('play');
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
  }

  @override
  Future<void> seek(Duration position) async {
    calls.add('seek($position)');
  }

  @override
  Future<bool> next({bool wrap = false}) async {
    calls.add('next(wrap: $wrap)');
    return nextReturnValue;
  }

  void emitPosition(Duration d) => _positionController.add(d);

  void emitState(PlayerState s) => _playerStateController.add(s);

  void emitError(Object e) => _errorsController.add(e);

  Future<void> dispose() async {
    await _positionController.close();
    await _playerStateController.close();
    await _errorsController.close();
  }
}
