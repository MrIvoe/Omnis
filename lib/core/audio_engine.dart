import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart' hide PlaybackState;
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart' show RepeatMode;
import 'package:omnis/core/ab_repeat_controller.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/home_widget_track_source.dart';
import 'package:omnis/core/playback_engine.dart';
import 'package:omnis/core/playback_os_integration.dart';
import 'package:omnis/core/playback_state.dart';
import 'package:omnis/core/queue_operations.dart';
import 'package:omnis_plugin_api/hardware_eq_band.dart';

// `HardwareEqBand` moved to `omnis_plugin_api` (see that package's
// `hardware_eq_band.dart`) so `EqualizerPlugin` can name it without
// depending on this file. Re-exported so every existing
// `import 'package:omnis/core/audio_engine.dart' show HardwareEqBand` in
// this app keeps working unchanged. `AudioEngine` below is still the only
// thing that ever constructs a real instance, via `HardwareEqBand.fromPlatform`.
export 'package:omnis_plugin_api/hardware_eq_band.dart' show HardwareEqBand;

/// Core playback engine.
///
/// This is the "indestructible layer" of Omnis. It owns the [AudioPlayer]
/// instances and exposes reactive [Stream]s that the UI and plugins
/// consume. No plugin code runs inside this class.
///
/// ## Queue model
///
/// The whole queue is always loaded as one [ConcatenatingAudioSource] on
/// the primary player, and just_audio owns advancement. [_sourceToQueue]
/// maps a player source index back to a queue index, because tracks with
/// no playable URL are skipped when the source is built and the two
/// indices would otherwise drift.
///
/// ## Crossfade
///
/// When [crossfadeDuration] is greater than zero, a second, otherwise-idle
/// [AudioPlayer] (`_crossfadePlayer`) preloads the next track and plays it
/// silently in parallel during the overlap window; a periodic ramp fades
/// the primary player's volume down and the second player's volume up.
/// When the primary auto-advances onto that same track (which just_audio's
/// own gapless engine does on its own), the second player is stopped —
/// the primary is now serving that audio natively, so there is no
/// discontinuity. A manual skip/seek abandons any in-flight crossfade
/// immediately; crossfade only ever applies to the automatic
/// end-of-track transition it was designed for.
class AudioEngine implements PlaybackEngine, HomeWidgetTrackSource {
  late final AudioPlayer _player;
  final AndroidEqualizer? _androidEqualizer;
  AudioPlayer? _crossfadePlayer;

  /// A-B repeat state machine — see [AbRepeatController].
  late final AbRepeatController _abRepeat;

  final List<BaseTrack> _queue = [];

  /// Maps player source index -> index in [_queue]. Tracks without a
  /// playable URI are omitted from the audio source, so these can differ.
  final List<int> _sourceToQueue = [];

  int _currentIndex = -1;
  BaseTrack? _currentTrack;
  Completer<void>? _initCompleter;

  /// Windows' notification-center/lock-screen/hardware-media-key
  /// integration (System Media Transport Controls) — the platform
  /// audio_service doesn't support. `null` everywhere else, or on
  /// Windows if SMTC failed to initialize (see [initialize]).
  OmnisWindowsMediaHandler? _windowsMediaHandler;

  /// Guards against reacting to index events emitted while we are swapping
  /// the audio source out from under the player.
  bool _rebuilding = false;

  /// Identity of the track the `onTrackStarted` hook last fired for, so a
  /// hook fires once per track rather than on every state change.
  String? _lastHookedTrack;

  /// Consecutive load failures, used to stop an auto-skip loop when every
  /// track in the queue is unplayable.
  int _consecutiveErrors = 0;

  StreamSubscription<int?>? _indexSub;
  StreamSubscription<PlayerState>? _stateSub;
  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<Duration>? _crossfadeWatchSub;

  /// Broadcast sink for native playback errors ([playbackErrors]).
  final StreamController<Object> _playbackErrorController =
      StreamController.broadcast();

  /// Global volume (0..1).
  double _volume = 1.0;

  /// Combined pre-gain multiplier contributed by plugins.
  double _preGainMultiplier = 1.0;

  /// Named multiplicative gain contributions (e.g. `'replay_gain'`,
  /// `'equalizer'`). Multiple plugins can each contribute a factor without
  /// clobbering one another — the effective pre-gain is the product of all
  /// contributions.
  final Map<String, double> _gainContributions = {};

  /// Crossfade duration (0 = disabled).
  Duration _crossfadeDuration = Duration.zero;

  /// Whether gapless concatenation is enabled.
  bool _gaplessEnabled = true;

  /// Shuffle/repeat state, mirrored onto the underlying just_audio player
  /// (see [setShuffleEnabled]/[setRepeatMode]) so that both manual
  /// next()/previous() *and* just_audio's own gapless auto-advance — which
  /// this class never intercepts, see the queue-model class doc — agree on
  /// what "next" means.
  bool _shuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.off;

  // --- Crossfade transition state (see class doc) ---
  bool _crossfading = false;
  double? _crossfadeProgress;
  int? _crossfadeTargetQueueIndex;
  Timer? _crossfadeTicker;

  // --- Hardware equalizer state ---
  List<HardwareEqBand>? _hardwareEqBands;
  bool _hardwareEqLoadAttempted = false;

  /// Stream of the current track.
  final StreamController<BaseTrack?> _trackController =
      StreamController.broadcast();

  /// Stream of queue changes.
  final StreamController<List<BaseTrack>> _queueController =
      StreamController.broadcast();

  bool _disposed = false;

  /// Called whenever a track actually starts playing. Fires once per track.
  Function(BaseTrack)? onTrackStarted;

  static bool get _supportsHardwareEq => !kIsWeb && Platform.isAndroid;

  /// Constructor. The native Android equalizer effect (if any) is attached
  /// to the primary player's pipeline at construction time — just_audio
  /// requires that up front, it cannot be bolted on later.
  AudioEngine()
      : _androidEqualizer = _supportsHardwareEq ? AndroidEqualizer() : null {
    final eq = _androidEqualizer;
    _player = AudioPlayer(
      audioPipeline:
          eq != null ? AudioPipeline(androidAudioEffects: [eq]) : null,
    );
    _abRepeat = AbRepeatController(
      positionStream: _player.positionStream,
      currentPosition: () => _player.position,
      seek: (position) => _player.seek(position),
    );
  }

  /// The underlying just_audio player (exposed for low-level access).
  AudioPlayer get player => _player;

  /// Current track duration, or `null` if unknown/not loaded.
  @override
  Duration? get duration => _player.duration;

  /// Current position within the current track.
  @override
  Duration get position => _player.position;

  /// Whether the engine believes the queue is exhaustively unplayable —
  /// every remaining track failed to load. Read by the recovery policy to
  /// stop instead of spinning.
  bool get queueExhausted => _consecutiveErrors > _sourceToQueue.length;

  /// Consecutive load failures since the last successful `ready`.
  int get consecutiveErrors => _consecutiveErrors;

  /// Build a [PlaybackState] snapshot of the whole playback subsystem —
  /// the raw material the recovery journal persists and resume restores.
  @override
  PlaybackState captureState() {
    return PlaybackState(
      queue: List.of(_queue),
      currentIndex: _currentIndex,
      position: _player.position,
      wasPlaying: _player.playing,
      shuffleEnabled: _shuffleEnabled,
      repeatMode: _repeatMode,
      volume: _volume,
      speed: _player.speed,
      pitch: _player.pitch,
      skipSilenceEnabled: _player.skipSilenceEnabled,
      gaplessEnabled: _gaplessEnabled,
      crossfadeDuration: _crossfadeDuration,
    );
  }

  /// Reload the currently loaded queue source — the "reinitialize the
  /// decoder" step of the playback recovery flow. Rebuilds the same
  /// concatenated source at the current index (or [position] past it).
  /// Never throws: a failed rebuild logs and leaves the previous source
  /// untouched, failing soft exactly like every other engine operation.
  @override
  Future<void> reloadCurrentSource({Duration? position}) async {
    if (_queue.isEmpty) return;
    final target = _currentIndex < 0 ? 0 : _currentIndex;
    await _rebuildQueueSource(
      initialQueueIndex: target,
      initialPosition: position ?? _player.position,
    );
  }

  /// Best-effort output-device reset (headphones/DAC vanished). Today every
  /// platform reports the default device, so this is a no-op that exists as
  /// the forward-compatible seam for the hardware capability layer (§25 of
  /// the product spec) — when a real output controller exists, this resets
  /// to the system default and reloads the source so audio actually routes
  /// to it.
  @override
  Future<void> setOutputDeviceToDefault() async {
    // No device selection layer yet — store everything as 'default' and no-op.
    // A future OutputController replaces this body; captureState() continues
    // to record `outputDeviceId: 'default'` and recovery naturally falls back.
  }

  /// Current track, or null when the queue is empty.
  @override
  BaseTrack? get currentTrack => _currentTrack;

  /// Read-only view of the queue.
  List<BaseTrack> get queue => List.unmodifiable(_queue);

  /// Current index in the queue; -1 when empty.
  int get currentIndex => _currentIndex;

  /// Position stream (ticks at ~200ms).
  @override
  Stream<Duration> get positionStream => _player.positionStream;

  /// Duration stream.
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Playback state stream.
  @override
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Broadcast stream of raw playback errors from the native player
  /// (`playbackEventStream` errors — corrupt/missing/unsupported files).
  /// The playback watchdog subscribes here so a decoder failure becomes a
  /// recoverable diagnostic instead of a silent hang. The engine's own
  /// error path (`_skipAfterError`) already advances the queue; this
  /// stream is the *observation* half that lets the watchdog/UI see it.
  @override
  Stream<Object> get playbackErrors => _playbackErrorController.stream;

  /// Current track stream (emits when the track changes).
  @override
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  /// Queue change stream.
  Stream<List<BaseTrack>> get queueStream => _queueController.stream;

  /// Whether the player is currently playing.
  @override
  bool get isPlaying => _player.playing;

  /// Crossfade duration (0 = disabled).
  Duration get crossfadeDuration => _crossfadeDuration;

  /// Whether a crossfade transition is in progress right now.
  bool get isCrossfading => _crossfading;

  /// Gapless mode flag.
  bool get gaplessEnabled => _gaplessEnabled;

  /// Shuffle playback toggle.
  bool get shuffleEnabled => _shuffleEnabled;

  /// Repeat mode (off / repeat whole queue / repeat current track).
  RepeatMode get repeatMode => _repeatMode;

  /// Enable/disable shuffle. Mirrored onto just_audio itself — its own
  /// engine (not this class) drives auto-advance at the end of a track,
  /// so it has to be the one that actually knows the shuffled order.
  /// Turning shuffle on also rerolls the order immediately, so it doesn't
  /// wait for the next queue rebuild to feel randomised.
  Future<void> setShuffleEnabled(bool enabled) async {
    _shuffleEnabled = enabled;
    await _player.setShuffleModeEnabled(enabled);
    if (enabled) {
      await _player.shuffle();
    }
  }

  /// Set the repeat mode. Mirrored onto just_audio's own [LoopMode], for
  /// the same reason as [setShuffleEnabled].
  Future<void> setRepeatMode(RepeatMode mode) async {
    _repeatMode = mode;
    await _player.setLoopMode(switch (mode) {
      RepeatMode.off => LoopMode.off,
      RepeatMode.all => LoopMode.all,
      RepeatMode.one => LoopMode.one,
    });
  }

  /// Set the crossfade duration (0 disables it).
  ///
  /// Takes effect on the next automatic end-of-track transition; it does
  /// not rebuild the currently loaded source, so touching this setting
  /// never restarts the track that's playing.
  void setCrossfadeDuration(Duration duration) {
    _crossfadeDuration = duration.isNegative ? Duration.zero : duration;
    if (_crossfadeDuration <= Duration.zero) {
      _cancelCrossfade(restoreVolume: true);
    }
  }

  /// Enable/disable gapless concatenation.
  ///
  /// NOTE: the queue is always loaded as one [ConcatenatingAudioSource],
  /// which is inherently gapless on Android/iOS/macOS. Turning this off is
  /// therefore not honoured by the engine today; the flag is kept so the
  /// preference survives and a future non-gapless path can read it.
  void setGaplessEnabled(bool enabled) {
    _gaplessEnabled = enabled;
  }

  /// Real per-band hardware equalizer bands, when available.
  ///
  /// Populated the first time a queue successfully loads on a platform
  /// with a native equalizer (Android only via just_audio's
  /// `AndroidEqualizer`). `null` before that happens, or permanently
  /// everywhere else — callers must treat `null` the same as "not
  /// available" and fall back to a virtual model.
  List<HardwareEqBand>? get hardwareEqBands => _hardwareEqBands;

  /// Query the native equalizer's bands, if this platform has one.
  ///
  /// Safe to call repeatedly — only the first call (after a source has
  /// loaded) does any work. Never throws: platform channel failures leave
  /// [hardwareEqBands] `null` and callers fall back to their virtual
  /// model. This path only runs on Android and has not been exercised
  /// against real hardware while building this feature — treat it as
  /// best-effort until verified on a device.
  Future<void> ensureHardwareEqLoaded() async {
    final eq = _androidEqualizer;
    if (eq == null || _hardwareEqLoadAttempted) return;
    _hardwareEqLoadAttempted = true;
    try {
      await eq.setEnabled(true);
      final params = await eq.parameters.timeout(const Duration(seconds: 5));
      _hardwareEqBands = [
        for (final band in params.bands)
          HardwareEqBand.fromPlatform(
            index: band.index,
            centerFrequencyHz: band.centerFrequency,
            minDecibels: params.minDecibels,
            maxDecibels: params.maxDecibels,
            initialGain: band.gain,
            applyGain: band.setGain,
          ),
      ];
    } catch (e) {
      debugPrint('Omnis: native equalizer unavailable, plugins should fall '
          'back to a virtual model: $e');
      _hardwareEqBands = null;
    }
  }

  /// Initialize the engine. Also initializes audio_service if the
  /// platform supports it. Failures here are caught so the core player
  /// always boots.
  Future<void> initialize() async {
    if (_initCompleter != null) {
      return _initCompleter!.future;
    }

    _initCompleter = Completer<void>();
    try {
      _bindPlayerStreams();
      // audio_service has no Windows implementation at all (only
      // Android/iOS/macOS) — routing Windows through
      // OmnisWindowsMediaHandler/SMTCWindows (playback_os_integration.dart)
      // instead of letting this throw-and-get-caught is the actual fix for
      // "no notification/media-key controls on Windows", not just a
      // defensive skip.
      //
      // This used to sit behind `await _player.load()`, which throws
      // ("no audio source") because nothing is loaded at boot. The throw
      // was swallowed by the outer catch and audio_service was silently
      // never initialised — no media notification, no lock-screen
      // controls, on any platform.
      if (!kIsWeb && Platform.isWindows) {
        try {
          _windowsMediaHandler = await OmnisWindowsMediaHandler.create(this);
        } catch (e) {
          debugPrint('Omnis: Windows media controls (SMTC) unavailable, '
              'continuing without them: $e');
        }
      } else {
        try {
          await AudioService.init(
            builder: () => OmnisAudioHandler(this),
            config: const AudioServiceConfig(
              androidNotificationChannelId: 'com.omnis.music.channel',
              androidNotificationChannelName: 'Omnis Playback',
              androidNotificationOngoing: true,
            ),
          );
        } catch (e) {
          debugPrint('Omnis: audio_service unavailable, continuing without '
              'background controls: $e');
        }
      }
    } catch (e, st) {
      debugPrint('Omnis: audio engine initialization failed: $e');
      debugPrint('$st');
    } finally {
      if (!_initCompleter!.isCompleted) {
        _initCompleter!.complete();
      }
    }
  }

  /// Await engine initialization (used by tests / callers that need it).
  Future<void> get initialized => _initCompleter?.future ?? Future.value();

  /// Subscribe to the player once, for the player's whole lifetime.
  void _bindPlayerStreams() {
    _indexSub = _player.currentIndexStream.listen((sourceIndex) {
      if (_disposed || _rebuilding || sourceIndex == null) return;
      if (sourceIndex < 0 || sourceIndex >= _sourceToQueue.length) return;
      final queueIndex = _sourceToQueue[sourceIndex];
      if (queueIndex < 0 || queueIndex >= _queue.length) return;
      if (_crossfading) {
        if (queueIndex == _crossfadeTargetQueueIndex) {
          unawaited(_finishCrossfade());
        } else {
          // The primary landed somewhere our crossfade wasn't expecting
          // (a manual seek/skip that raced past our guards) — abandon the
          // stale fade rather than leave two players fighting for volume.
          _cancelCrossfade(restoreVolume: true);
        }
      }
      _setCurrent(_queue[queueIndex], queueIndex);
    });

    _stateSub = _player.playerStateStream.listen((state) {
      if (_disposed) return;
      if (state.processingState == ProcessingState.ready) {
        _consecutiveErrors = 0;
      }
      if (state.playing) _fireTrackStarted();
    });

    // A corrupt or missing file surfaces as an error on the playback event
    // stream. Skip past it instead of leaving the player wedged.
    _eventSub = _player.playbackEventStream.listen(
      null,
      onError: (Object e, StackTrace st) {
        if (_disposed) return;
        debugPrint('Omnis: playback error: $e');
        if (!_playbackErrorController.isClosed) {
          _playbackErrorController.add(e);
        }
        _skipAfterError();
      },
    );

    // Drives the crossfade state machine — see class doc.
    _crossfadeWatchSub = _player.positionStream.listen(_onPositionForCrossfade);
  }

  Future<void> _skipAfterError() async {
    _consecutiveErrors++;
    // Every remaining track failed — stop rather than spin.
    if (_consecutiveErrors > _sourceToQueue.length) {
      debugPrint('Omnis: no playable tracks left in the queue, stopping.');
      await _player.stop();
      return;
    }
    await next();
  }

  /// Dispose the engine.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _crossfadeTicker?.cancel();
    await _indexSub?.cancel();
    await _stateSub?.cancel();
    await _eventSub?.cancel();
    await _crossfadeWatchSub?.cancel();
    await _abRepeat.dispose();
    await _player.dispose();
    final fadePlayer = _crossfadePlayer;
    if (fadePlayer != null) {
      await fadePlayer.dispose();
    }
    if (!_trackController.isClosed) {
      await _trackController.close();
    }
    if (!_queueController.isClosed) {
      await _queueController.close();
    }
    if (!_playbackErrorController.isClosed) {
      await _playbackErrorController.close();
    }
    await _windowsMediaHandler?.dispose();
  }

  /// Replace the whole queue with [tracks].
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    _queue
      ..clear()
      ..addAll(tracks);
    _emitQueue();
    if (_queue.isEmpty) {
      await _clearSource();
      return;
    }
    final start =
        (startIndex >= 0 && startIndex < _queue.length) ? startIndex : 0;
    await _rebuildQueueSource(initialQueueIndex: start);
  }

  /// Add a track to the end of the queue, preserving current playback.
  Future<void> addTrack(BaseTrack track) async {
    _queue.add(track);
    _emitQueue();
    if (_currentIndex < 0) {
      await _rebuildQueueSource(initialQueueIndex: 0);
    } else {
      await _rebuildQueueSource(
        initialQueueIndex: _currentIndex,
        initialPosition: _player.position,
      );
    }
  }

  /// Insert a track to play immediately after the current one — the
  /// "Play next" queue action (§7 of the Omnis 2.0 product spec, which
  /// calls out "play next" and "add to queue" as distinct actions;
  /// [addTrack] is "add to queue," this is "play next"). Preserves
  /// current playback, exactly like [addTrack]; with nothing currently
  /// playing, "next" is the very front of the queue, so it behaves the
  /// same as [addTrack] in that case.
  Future<void> playNext(BaseTrack track) async {
    final insertAt = _currentIndex < 0 ? 0 : _currentIndex + 1;
    _queue.insert(insertAt, track);
    _emitQueue();
    if (_currentIndex < 0) {
      await _rebuildQueueSource(initialQueueIndex: 0);
    } else {
      await _rebuildQueueSource(
        initialQueueIndex: _currentIndex,
        initialPosition: _player.position,
      );
    }
  }

  /// Remove the track at [index].
  Future<void> removeTrack(int index) async {
    if (index < 0 || index >= _queue.length) return;
    final wasCurrent = index == _currentIndex;
    final position = _player.position;
    _queue.removeAt(index);

    if (_currentIndex > index) {
      _currentIndex--;
    } else if (wasCurrent && _currentIndex >= _queue.length) {
      _currentIndex = _queue.length - 1;
    }
    _emitQueue();

    if (_queue.isEmpty) {
      await _clearSource();
      return;
    }
    await _rebuildQueueSource(
      initialQueueIndex: _currentIndex < 0 ? 0 : _currentIndex,
      // Removing the playing track starts its replacement from the top;
      // removing any other track must not disturb the current position.
      initialPosition: wasCurrent ? Duration.zero : position,
    );
  }

  /// Moves the track at [from] to [to] (same `(oldIndex, newIndex)`
  /// convention as `ReorderableListView.onReorder`), preserving playback
  /// position and the identity of whatever's currently playing — only
  /// its index may change. Index math itself lives in the pure, unit-
  /// tested `QueueOperations.reorder`.
  Future<void> moveTrack(int from, int to) async {
    if (from < 0 || from >= _queue.length || to < 0 || to > _queue.length) {
      return;
    }
    final position = _player.position;
    final (newQueue, newCurrentIndex) =
        QueueOperations.reorder(_queue, _currentIndex, from, to);
    _queue
      ..clear()
      ..addAll(newQueue);
    _currentIndex = newCurrentIndex;
    _emitQueue();
    await _rebuildQueueSource(
      initialQueueIndex: _currentIndex < 0 ? 0 : _currentIndex,
      initialPosition: position,
    );
  }

  /// Shuffles every track after the current one, leaving what's already
  /// played and what's currently playing untouched. Index math lives in
  /// the pure, unit-tested `QueueOperations.shuffledRemaining`.
  Future<void> shuffleRemaining() async {
    final position = _player.position;
    final newQueue = QueueOperations.shuffledRemaining(_queue, _currentIndex);
    _queue
      ..clear()
      ..addAll(newQueue);
    _emitQueue();
    await _rebuildQueueSource(
      initialQueueIndex: _currentIndex < 0 ? 0 : _currentIndex,
      initialPosition: position,
    );
  }

  /// Play the track at queue [index].
  Future<void> playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _cancelCrossfade(restoreVolume: true);
    final sourceIndex = _sourceToQueue.indexOf(index);
    if (sourceIndex < 0) {
      // Not currently represented in the audio source (e.g. the queue
      // changed underneath us): rebuild around the requested track.
      await _rebuildQueueSource(initialQueueIndex: index);
    } else {
      await _player.seek(Duration.zero, index: sourceIndex);
      _setCurrent(_queue[index], index);
    }
    await _player.play();
  }

  /// Start playing (resume).
  @override
  Future<void> play() async {
    if (_queue.isEmpty) return;
    if (_currentIndex < 0) {
      await playAt(0);
      return;
    }
    await _player.play();
  }

  /// Pause playback.
  Future<void> pause() async => _player.pause();

  /// Stop playback.
  @override
  Future<void> stop() async {
    _cancelCrossfade(restoreVolume: true);
    await _player.stop();
  }

  /// Skip to the next track, honouring shuffle/repeat. Returns false when
  /// there is no next track and [wrap] is false.
  ///
  /// Delegates to just_audio's own `hasNext`/`nextIndex`/`seekToNext()`
  /// rather than hand-rolled index math, so a manual skip always agrees
  /// with the engine's own gapless auto-advance (which only just_audio
  /// itself ever triggers — see the queue-model class doc) about what
  /// "next" means under shuffle/repeat. One consequence: with repeat-one,
  /// "next" restarts the current track rather than skipping past the
  /// repeat — just_audio ties both to the same loop-mode-aware index, and
  /// diverging from that would mean tracking a second, parallel notion of
  /// "next" that could drift out of sync with it.
  @override
  Future<bool> next({bool wrap = false}) async {
    if (_sourceToQueue.isEmpty) return false;
    _cancelCrossfade(restoreVolume: true);
    if (!_player.hasNext) {
      if (!wrap) return false;
      final indices = _player.effectiveIndices;
      final target =
          (indices != null && indices.isNotEmpty) ? indices.first : 0;
      if (target >= _sourceToQueue.length) return false;
      await _player.seek(Duration.zero, index: target);
      _setCurrent(_queue[_sourceToQueue[target]], _sourceToQueue[target]);
      await _player.play();
      return true;
    }
    final target = _player.nextIndex;
    await _player.seekToNext();
    if (target != null && target < _sourceToQueue.length) {
      _setCurrent(_queue[_sourceToQueue[target]], _sourceToQueue[target]);
    }
    await _player.play();
    return true;
  }

  /// Skip to the previous track (or restart the current one if it has
  /// played for more than 3 seconds, or there is no previous track under
  /// the current shuffle/repeat state).
  Future<bool> previous() async {
    if (_sourceToQueue.isEmpty) return false;
    _cancelCrossfade(restoreVolume: true);
    if (_player.position > const Duration(seconds: 3) || !_player.hasPrevious) {
      await seek(Duration.zero);
      return true;
    }
    final target = _player.previousIndex;
    await _player.seekToPrevious();
    if (target != null && target < _sourceToQueue.length) {
      _setCurrent(_queue[_sourceToQueue[target]], _sourceToQueue[target]);
    }
    await _player.play();
    return true;
  }

  /// Seek within the current track.
  @override
  Future<void> seek(Duration position) => _player.seek(position);

  /// Set the global master volume.
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _applyVolumes();
  }

  /// Master volume (0..1), before plugin gain contributions.
  double get volume => _volume;

  /// Set a named multiplicative gain contribution. The effective pre-gain
  /// applied to the player is the product of every contribution currently
  /// registered, clamped to a sane range so a bug in one plugin can't blow
  /// out the volume or silence it entirely.
  Future<void> setGainContribution(String source, double multiplier) async {
    _gainContributions[source] =
        (multiplier.isFinite && multiplier > 0) ? multiplier : 1.0;
    await _applyVolumes();
  }

  /// Drop a named gain contribution entirely (e.g. its plugin was
  /// disabled), so it stops multiplying into the effective volume.
  Future<void> clearGainContribution(String source) async {
    if (_gainContributions.remove(source) == null) return;
    await _applyVolumes();
  }

  /// Set the pre-gain directly. Kept for backward compatibility — prefer
  /// [setGainContribution] with a named source.
  Future<void> setPreGain(double multiplier) =>
      setGainContribution('_direct', multiplier);

  /// Pure crossfade volume math: given a base volume and progress (0..1)
  /// through the overlap window, returns the (outgoing, incoming) volumes
  /// for the primary and crossfade players. Exposed as a pure function so
  /// it has a unit test independent of any real [AudioPlayer].
  static (double outgoing, double incoming) crossfadeVolumes(
    double base,
    double progress,
  ) {
    final t = progress.clamp(0.0, 1.0);
    final b = base.clamp(0.0, 1.0);
    return (b * (1 - t), b * t);
  }

  Future<void> _applyVolumes() async {
    final combined = _gainContributions.values.fold<double>(
      1.0,
      (acc, m) => acc * m,
    );
    _preGainMultiplier = combined.clamp(0.1, 2.0);
    final base = (_volume * _preGainMultiplier).clamp(0.0, 1.0);

    final progress = _crossfadeProgress;
    if (progress == null) {
      await _player.setVolume(base);
      return;
    }
    final (outgoing, incoming) = crossfadeVolumes(base, progress);
    await _player.setVolume(outgoing);
    final fadePlayer = _crossfadePlayer;
    if (fadePlayer != null) {
      await fadePlayer.setVolume(incoming);
    }
  }

  /// Set playback speed. This also shifts pitch unless [setPitch] is used
  /// to compensate — just_audio ties the two together the way most
  /// platform media players do; [pitch] is the independent knob for
  /// anyone who wants speed changed without the "chipmunk"/"slow-mo"
  /// pitch shift, the way Poweramp's separate tempo/pitch controls work.
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.25, 2.0));
  }

  /// Playback speed.
  double get speed => _player.speed;

  /// Set pitch independently of speed (1.0 = unshifted). Real, native
  /// just_audio support — not a DSP effect this project implemented.
  Future<void> setPitch(double pitch) async {
    await _player.setPitch(pitch.clamp(0.5, 2.0));
  }

  /// Current pitch factor.
  double get pitch => _player.pitch;

  /// Skip-silence toggle: shortens silent gaps in playback instead of
  /// playing through them at normal speed — same feature name/behavior as
  /// Poweramp's and most podcast players'. Real, native just_audio
  /// support, not something this project implemented.
  Future<void> setSkipSilenceEnabled(bool enabled) async {
    await _player.setSkipSilenceEnabled(enabled);
  }

  /// Whether skip-silence is on.
  bool get skipSilenceEnabled => _player.skipSilenceEnabled;

  // --- A-B repeat ---
  //
  // A common practicing/DJ feature (Poweramp, Musicolet, most desktop
  // players all have it) that just_audio has no built-in concept of. The
  // actual state machine lives in [AbRepeatController] (see its class
  // doc for why it was split out); these are thin delegating wrappers so
  // every existing caller of markLoopA/markLoopB/clearLoop/abRepeatRange/
  // loopAMarker keeps working unchanged.

  /// The current A-B loop points, or `null` if A-B repeat is off.
  (Duration a, Duration b)? get abRepeatRange => _abRepeat.range;

  /// Point A, once marked — set even before B is marked (and thus before
  /// looping actually starts), so UI can show a mid-way "A marked, tap
  /// again for B" state distinct from both "off" and "looping."
  Duration? get loopAMarker => _abRepeat.markerA;

  /// Marks point A at [position] (defaults to the current position).
  /// Clears any previously completed loop until [markLoopB] is also
  /// called — a lone A point does nothing yet.
  void markLoopA([Duration? position]) => _abRepeat.markA(position);

  /// Marks point B and, if it's after A, starts looping between them
  /// immediately. B at or before A is rejected (a zero/negative loop
  /// makes no sense) rather than silently doing nothing useful.
  bool markLoopB([Duration? position]) => _abRepeat.markB(position);

  /// Clears A-B repeat and lets playback continue normally.
  void clearLoop() => _abRepeat.clear();

  /// Resolve a track to a playable URI.
  ///
  /// Local paths must go through [Uri.file]: a Windows path such as
  /// `C:\Music\a.mp3` fed to `Uri.parse` yields a URI with scheme `c`,
  /// which just_audio cannot open. A single-letter scheme is therefore
  /// treated as a drive letter, not a real scheme.
  static Uri? uriFor(BaseTrack track) {
    final local = track.localPath;
    if (local != null && local.isNotEmpty) {
      final parsed = Uri.tryParse(local);
      if (parsed != null && parsed.hasScheme && parsed.scheme.length > 1) {
        // Already a real URI (content://, file://, http://, asset://…).
        return parsed;
      }
      try {
        return Uri.file(local);
      } catch (_) {
        return null;
      }
    }
    final stream = track.streamUrl;
    if (stream == null || stream.isEmpty) return null;
    final parsed = Uri.tryParse(stream);
    if (parsed == null || !parsed.hasScheme) return null;
    return parsed;
  }

  Future<void> _clearSource() async {
    _cancelCrossfade(restoreVolume: true);
    _sourceToQueue.clear();
    _rebuilding = true;
    try {
      await _player.stop();
    } catch (_) {
      // Stopping a player that never loaded a source is not an error.
    } finally {
      _rebuilding = false;
    }
    _setCurrent(null, -1);
  }

  /// Rebuild the [ConcatenatingAudioSource] from the current queue.
  Future<void> _rebuildQueueSource({
    int? initialQueueIndex,
    Duration? initialPosition,
  }) async {
    _cancelCrossfade(restoreVolume: true);
    final children = <AudioSource>[];
    _sourceToQueue.clear();
    for (var i = 0; i < _queue.length; i++) {
      final uri = uriFor(_queue[i]);
      if (uri == null) {
        debugPrint('Omnis: skipping "${_queue[i].title}" — no playable URI.');
        continue;
      }
      children.add(AudioSource.uri(uri, tag: _queue[i]));
      _sourceToQueue.add(i);
    }

    if (children.isEmpty) {
      await _clearSource();
      return;
    }

    final target = initialQueueIndex ?? _currentIndex;
    var sourceIndex = _sourceToQueue.indexOf(target);
    if (sourceIndex < 0) sourceIndex = 0;

    _rebuilding = true;
    try {
      await _player.setAudioSource(
        ConcatenatingAudioSource(children: children),
        initialIndex: sourceIndex,
        initialPosition: initialPosition ?? Duration.zero,
      );
      // The platform is guaranteed connected once a source has loaded —
      // this is the only reliable place to query the native equalizer.
      unawaited(ensureHardwareEqLoaded());
    } catch (e) {
      debugPrint('Omnis: failed to load the queue: $e');
    } finally {
      _rebuilding = false;
    }

    final queueIndex = _sourceToQueue[sourceIndex];
    _setCurrent(_queue[queueIndex], queueIndex);
  }

  void _setCurrent(BaseTrack? track, int index) {
    final changed = _currentTrack?.id != track?.id || _currentIndex != index;
    _currentTrack = track;
    _currentIndex = index;
    if (!changed) return;
    // An A-B loop only makes sense against the track it was marked on —
    // leaving it armed across a skip would silently start looping an
    // unrelated section of whatever plays next.
    clearLoop();
    if (!_trackController.isClosed) {
      _trackController.add(track);
    }
    if (_player.playing) _fireTrackStarted();
  }

  /// Fire the plugin hook once per track, whichever happens last: the
  /// track becoming current, or playback actually starting.
  void _fireTrackStarted() {
    final track = _currentTrack;
    if (track == null) return;
    final key = '$_currentIndex:${track.id}';
    if (_lastHookedTrack == key) return;
    _lastHookedTrack = key;
    onTrackStarted?.call(track);
  }

  void _emitQueue() {
    if (_queueController.isClosed) return;
    _queueController.add(List.unmodifiable(_queue));
  }

  // --- Crossfade state machine ---
  //
  // Entered only from _onPositionForCrossfade, which fires on every
  // position tick of the primary player. When the remaining time on the
  // current track drops to or below _crossfadeDuration and there is a
  // next track in the queue, _startCrossfade preloads it on a second,
  // otherwise-idle player and ramps volumes over the overlap window.
  // Manual navigation (next/previous/playAt/stop) and queue rebuilds all
  // abandon an in-flight crossfade via _cancelCrossfade — crossfade only
  // ever applies to the automatic end-of-track transition.

  void _onPositionForCrossfade(Duration position) {
    if (_disposed || _rebuilding || _crossfading) return;
    if (_crossfadeDuration <= Duration.zero) return;
    if (position <= Duration.zero) return;
    final total = _player.duration;
    if (total == null || total <= Duration.zero) return;
    final remaining = total - position;
    if (remaining.isNegative || remaining > _crossfadeDuration) return;

    // Uses just_audio's own shuffle/repeat-aware nextIndex rather than
    // "current source position + 1" — under shuffle, the actual next
    // track is almost never the next sequential one. Repeat-one's
    // nextIndex equals the current index; crossfading a track into
    // itself would just be two overlapping copies of the same audio, so
    // that case is skipped rather than "faded."
    final sourceIndex = _sourceToQueue.indexOf(_currentIndex);
    final nextSourceIndex = _player.nextIndex;
    if (sourceIndex < 0 ||
        nextSourceIndex == null ||
        nextSourceIndex == sourceIndex ||
        nextSourceIndex >= _sourceToQueue.length) {
      return;
    }
    final nextQueueIndex = _sourceToQueue[nextSourceIndex];
    final uri = uriFor(_queue[nextQueueIndex]);
    if (uri == null) return;

    unawaited(_startCrossfade(nextQueueIndex, uri, remaining));
  }

  Future<void> _startCrossfade(
    int queueIndex,
    Uri uri,
    Duration overlap,
  ) async {
    _crossfading = true;
    _crossfadeTargetQueueIndex = queueIndex;
    _crossfadeProgress = 0.0;

    final fadePlayer = _crossfadePlayer ??= AudioPlayer();
    try {
      await fadePlayer.setVolume(0);
      await fadePlayer.setAudioSource(AudioSource.uri(uri));
      await fadePlayer.play();
    } catch (e) {
      debugPrint(
        'Omnis: crossfade preload failed, staying gapless for this '
        'transition: $e',
      );
      _cancelCrossfade(restoreVolume: true);
      return;
    }

    final totalMs = overlap.inMilliseconds.clamp(1, 1 << 30);
    final startedAt = DateTime.now();
    _crossfadeTicker?.cancel();
    _crossfadeTicker = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!_crossfading) return;
      final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
      final t = (elapsedMs / totalMs).clamp(0.0, 1.0);
      _crossfadeProgress = t;
      unawaited(_applyVolumes());
      if (t >= 1.0) {
        _crossfadeTicker?.cancel();
        _crossfadeTicker = null;
      }
    });
  }

  /// The primary player has landed on the track the crossfade was fading
  /// into — its own gapless engine did the handoff, so the second player
  /// is now redundant and can stop.
  Future<void> _finishCrossfade() async {
    _crossfadeTicker?.cancel();
    _crossfadeTicker = null;
    _crossfading = false;
    _crossfadeProgress = null;
    _crossfadeTargetQueueIndex = null;
    await _applyVolumes();
    final fadePlayer = _crossfadePlayer;
    if (fadePlayer != null) {
      try {
        await fadePlayer.stop();
      } catch (_) {}
    }
  }

  void _cancelCrossfade({required bool restoreVolume}) {
    _crossfadeTicker?.cancel();
    _crossfadeTicker = null;
    final wasActive = _crossfading;
    _crossfading = false;
    _crossfadeProgress = null;
    _crossfadeTargetQueueIndex = null;
    final fadePlayer = _crossfadePlayer;
    if (wasActive && fadePlayer != null) {
      unawaited(fadePlayer.stop());
    }
    if (restoreVolume) {
      unawaited(_applyVolumes());
    }
  }
}
