import 'dart:async';

import 'package:audio_service/audio_service.dart' hide PlaybackState;
import 'package:just_audio/just_audio.dart' show PlayerState, ProcessingState;
import 'package:omnis/core/audio_engine.dart';
import 'package:smtc_windows/smtc_windows.dart';

// OS media-session integration for AudioEngine — the notification
// center / lock-screen / hardware-media-key surface (§2 of the Omnis 2.0
// product spec: "OS media controls, lock screen controls, notification
// controls, media session, external media keys").
//
// Split out of `audio_engine.dart` per §51.2 of the product spec ("break
// up the large AudioEngine... the public engine facade can remain
// tiny"). Both classes here only ever talk to AudioEngine through its
// existing public streams and transport methods (play/pause/stop/seek/
// next/previous, playerStateStream/positionStream/trackStream) — this
// file has no access to (and makes no assumptions about) the engine's
// private queue/crossfade internals, which is what makes it safe to move
// wholesale with no behavior change.

/// Minimal AudioHandler used by audio_service when available on the
/// platform (Android/iOS/macOS). It forwards to [AudioEngine].
class OmnisAudioHandler extends BaseAudioHandler {
  final AudioEngine _engine;

  OmnisAudioHandler(this._engine) {
    _engine.playerStateStream.listen((PlayerState state) {
      final playing = state.playing;
      final processing = state.processingState;
      playbackState.add(playbackState.value.copyWith(
        playing: playing,
        controls: [
          MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          MediaControl.skipToNext,
        ],
        processingState: switch (processing) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
      ));
    });
    _engine.positionStream.listen((pos) {
      playbackState.add(playbackState.value.copyWith(
        updatePosition: pos,
      ));
    });
    _engine.trackStream.listen((track) {
      if (track == null) return;
      mediaItem.add(MediaItem(
        id: track.id,
        title: track.title,
        artist: track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown',
        album: track.album,
        // BaseTrack.duration is in seconds everywhere else in the app; this
        // used to be read as milliseconds, so the notification showed a
        // ~3-minute song as 3 seconds long.
        duration: Duration(seconds: track.duration),
        artUri: _artUri(track.coverArt),
      ));
    });
  }

  /// Only hand audio_service artwork URIs it can actually fetch.
  ///
  /// `MediaScanner` stores Android artwork as `mediastore://<id>`, which is
  /// a marker for `QueryArtworkWidget`, not a resolvable URI — passing it
  /// through made the media notification try (and fail) to load it.
  static Uri? _artUri(String? coverArt) {
    if (coverArt == null || coverArt.isEmpty) return null;
    final uri = Uri.tryParse(coverArt);
    if (uri == null) return null;
    const loadable = {'http', 'https', 'file', 'content', 'asset'};
    if (!loadable.contains(uri.scheme)) return null;
    return uri;
  }

  @override
  Future<void> play() => _engine.play();

  @override
  Future<void> pause() => _engine.pause();

  @override
  Future<void> stop() => _engine.stop();

  @override
  Future<void> seek(Duration position) => _engine.seek(position);

  @override
  Future<void> skipToNext() async {
    await _engine.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await _engine.previous();
  }
}

/// Windows System Media Transport Controls integration — the
/// notification-center / lock-screen / hardware-media-key surface
/// [OmnisAudioHandler]/audio_service provides on Android/iOS/macOS but has
/// no Windows implementation of at all. Same shape as [OmnisAudioHandler]:
/// forwards engine state out to SMTC, forwards SMTC button presses back
/// into the engine.
///
/// Uses `smtc_windows`, a Flutter Windows plugin that bundles a compiled
/// Rust component (via cargokit) for the actual SMTC/WinRT calls —
/// building it requires a Rust toolchain (`cargo`) on the machine doing
/// the Windows build, on top of the usual Flutter/Visual Studio
/// requirements. See docs/BUILDING.md.
///
/// **Verification status**: implemented against smtc_windows' documented
/// public API; not exercised against a real Windows build in this
/// environment — a pre-existing Visual Studio/Flutter tooling version
/// mismatch blocks Windows builds here entirely (see docs/BUILDING.md),
/// unrelated to this feature specifically. [AudioEngine.initialize]'s
/// try/catch around [create] means a failure here degrades to "no
/// Windows media controls," the same fail-soft contract audio_service
/// already has on platforms it doesn't support.
class OmnisWindowsMediaHandler {
  final AudioEngine _engine;
  final SMTCWindows _smtc;
  final List<StreamSubscription<void>> _subs = [];

  OmnisWindowsMediaHandler._(this._engine, this._smtc) {
    _subs.add(_engine.playerStateStream.listen((state) {
      _smtc.setPlaybackStatus(
          state.playing ? PlaybackStatus.playing : PlaybackStatus.paused);
    }));
    _subs.add(_engine.positionStream.listen(_smtc.setPosition));
    _subs.add(_engine.trackStream.listen((track) {
      if (track == null) {
        _smtc.clearMetadata();
        return;
      }
      _smtc.updateMetadata(MusicMetadata(
        title: track.title,
        artist: track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown',
        album: track.album,
        thumbnail: _thumbnailFor(track.coverArt),
      ));
      _smtc.setStartTime(Duration.zero);
      _smtc.setEndTime(Duration(seconds: track.duration));
    }));
    _subs.add(_smtc.buttonPressStream.listen((button) {
      switch (button) {
        case PressedButton.play:
          _engine.play();
        case PressedButton.pause:
          _engine.pause();
        case PressedButton.next:
          _engine.next();
        case PressedButton.previous:
          _engine.previous();
        case PressedButton.stop:
          _engine.stop();
        case PressedButton.fastForward:
        case PressedButton.rewind:
        case PressedButton.record:
        case PressedButton.channelUp:
        case PressedButton.channelDown:
          break; // Not surfaced in Omnis's transport controls.
      }
    }));
  }

  static Future<OmnisWindowsMediaHandler> create(AudioEngine engine) async {
    await SMTCWindows.initialize();
    final smtc = SMTCWindows(
      config: const SMTCConfig(
        playEnabled: true,
        pauseEnabled: true,
        nextEnabled: true,
        prevEnabled: true,
        stopEnabled: false,
        fastForwardEnabled: false,
        rewindEnabled: false,
      ),
    );
    return OmnisWindowsMediaHandler._(engine, smtc);
  }

  /// SMTC's thumbnail wants a local file path or a resolvable URI.
  /// `mediastore://` markers ([OmnisAudioHandler._artUri]'s Android-only
  /// concern) never occur on Windows — `MediaScanner`'s desktop path
  /// always produces a real local path or nothing.
  static String? _thumbnailFor(String? coverArt) =>
      (coverArt == null || coverArt.isEmpty) ? null : coverArt;

  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _smtc.dispose();
  }
}
