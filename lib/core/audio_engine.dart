import 'dart:async';
import 'dart:io' show Platform;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/app_settings.dart' show RepeatMode;
import 'package:omnis/core/base_track.dart';
import 'package:smtc_windows/smtc_windows.dart' hide RepeatMode;

/// A single adjustable band on the platform's native equalizer.
///
/// Deliberately just_audio-agnostic in its public surface — no
/// `AndroidEqualizerBand` type leaks out — so a plugin that wants real
/// per-band control depends only on this, not on the audio backend.
class HardwareEqBand {
  /// Index of this band on the native equalizer.
  final int index;

  /// Approximate center frequency in Hz, as reported by the platform.
  final double centerFrequencyHz;

  /// Minimum gain the platform accepts, in decibels.
  final double minDecibels;

  /// Maximum gain the platform accepts, in decibels.
  final double maxDecibels;

  final Future<void> Function(double gain) _applyGain;
  double _gain;

  HardwareEqBand._({
    required this.index,
    required this.centerFrequencyHz,
    required this.minDecibels,
    required this.maxDecibels,
    required double initialGain,
    required Future<void> Function(double gain) applyGain,
  })  : _gain = initialGain,
        _applyGain = applyGain;

  /// Test-only constructor — production bands only come from
  /// [AudioEngine.hardwareEqBands], which reads real platform state.
  @visibleForTesting
  factory HardwareEqBand.forTesting({
    required int index,
    required double centerFrequencyHz,
    double minDecibels = -15,
    double maxDecibels = 15,
    double initialGain = 0,
    Future<void> Function(double gain)? applyGain,
  }) {
    return HardwareEqBand._(
      index: index,
      centerFrequencyHz: centerFrequencyHz,
      minDecibels: minDecibels,
      maxDecibels: maxDecibels,
      initialGain: initialGain,
      applyGain: applyGain ?? (_) async {},
    );
  }

  /// Current gain in decibels.
  double get gain => _gain;

  /// Set this band's gain, clamped to the platform's supported range.
  Future<void> setGain(double decibels) async {
    final clamped = decibels.clamp(minDecibels, maxDecibels);
    _gain = clamped;
    await _applyGain(clamped);
  }
}

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
class AudioEngine {
  late final AudioPlayer _player;
  final AndroidEqualizer? _androidEqualizer;
  AudioPlayer? _crossfadePlayer;

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
  _OmnisWindowsMediaHandler? _windowsMediaHandler;

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
  }

  /// The underlying just_audio player (exposed for low-level access).
  AudioPlayer get player => _player;

  /// Current track, or null when the queue is empty.
  BaseTrack? get currentTrack => _currentTrack;

  /// Read-only view of the queue.
  List<BaseTrack> get queue => List.unmodifiable(_queue);

  /// Current index in the queue; -1 when empty.
  int get currentIndex => _currentIndex;

  /// Position stream (ticks at ~200ms).
  Stream<Duration> get positionStream => _player.positionStream;

  /// Duration stream.
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Playback state stream.
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Current track stream (emits when the track changes).
  Stream<BaseTrack?> get trackStream => _trackController.stream;

  /// Queue change stream.
  Stream<List<BaseTrack>> get queueStream => _queueController.stream;

  /// Whether the player is currently playing.
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
          HardwareEqBand._(
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
      // _OmnisWindowsMediaHandler/SMTCWindows instead of letting this
      // throw-and-get-caught is the actual fix for "no notification/
      // media-key controls on Windows", not just a defensive skip.
      //
      // This used to sit behind `await _player.load()`, which throws
      // ("no audio source") because nothing is loaded at boot. The throw
      // was swallowed by the outer catch and audio_service was silently
      // never initialised — no media notification, no lock-screen
      // controls, on any platform.
      if (!kIsWeb && Platform.isWindows) {
        try {
          _windowsMediaHandler = await _OmnisWindowsMediaHandler.create(this);
        } catch (e) {
          debugPrint('Omnis: Windows media controls (SMTC) unavailable, '
              'continuing without them: $e');
        }
      } else {
        try {
          await AudioService.init(
            builder: () => _OmnisAudioHandler(this),
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
    await _abRepeatSub?.cancel();
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
  // Loops a marked section [_loopA, _loopB] of the current track
  // indefinitely — set point A, set point B, playback jumps back to A
  // every time it reaches B, until cleared. A common practicing/DJ
  // feature (Poweramp, Musicolet, most desktop players all have it) that
  // just_audio has no built-in concept of, so it's driven off the same
  // positionStream-watcher pattern the crossfade state machine already
  // uses in this class.

  Duration? _loopA;
  Duration? _loopB;
  StreamSubscription<Duration>? _abRepeatSub;

  /// The current A-B loop points, or `null` if A-B repeat is off.
  (Duration a, Duration b)? get abRepeatRange =>
      (_loopA != null && _loopB != null) ? (_loopA!, _loopB!) : null;

  /// Point A, once marked — set even before B is marked (and thus before
  /// looping actually starts), so UI can show a mid-way "A marked, tap
  /// again for B" state distinct from both "off" and "looping."
  Duration? get loopAMarker => _loopA;

  /// Marks point A at [position] (defaults to the current position).
  /// Clears any previously completed loop until [markLoopB] is also
  /// called — a lone A point does nothing yet.
  void markLoopA([Duration? position]) {
    _loopA = position ?? _player.position;
    _loopB = null;
  }

  /// Marks point B and, if it's after A, starts looping between them
  /// immediately. B at or before A is rejected (a zero/negative loop
  /// makes no sense) rather than silently doing nothing useful.
  bool markLoopB([Duration? position]) {
    final a = _loopA;
    if (a == null) return false;
    final b = position ?? _player.position;
    if (b <= a) return false;
    _loopB = b;
    _abRepeatSub ??= _player.positionStream.listen(_onPositionForAbRepeat);
    return true;
  }

  /// Clears A-B repeat and lets playback continue normally.
  void clearLoop() {
    _loopA = null;
    _loopB = null;
    _abRepeatSub?.cancel();
    _abRepeatSub = null;
  }

  void _onPositionForAbRepeat(Duration position) {
    final b = _loopB;
    if (b == null || _disposed) return;
    if (position >= b) {
      unawaited(_player.seek(_loopA));
    }
  }

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

/// Minimal AudioHandler used by audio_service when available on the
/// platform. It forwards to [AudioEngine].
class _OmnisAudioHandler extends BaseAudioHandler {
  final AudioEngine _engine;

  _OmnisAudioHandler(this._engine) {
    _engine.playerStateStream.listen((state) {
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
/// [_OmnisAudioHandler]/audio_service provides on Android/iOS/macOS but
/// has no Windows implementation of at all. Same shape as
/// [_OmnisAudioHandler]: forwards engine state out to SMTC, forwards
/// SMTC button presses back into the engine.
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
class _OmnisWindowsMediaHandler {
  final AudioEngine _engine;
  final SMTCWindows _smtc;
  final List<StreamSubscription<void>> _subs = [];

  _OmnisWindowsMediaHandler._(this._engine, this._smtc) {
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
        artist:
            track.artists.isNotEmpty ? track.artists.join(', ') : 'Unknown',
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

  static Future<_OmnisWindowsMediaHandler> create(AudioEngine engine) async {
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
    return _OmnisWindowsMediaHandler._(engine, smtc);
  }

  /// SMTC's thumbnail wants a local file path or a resolvable URI.
  /// `mediastore://` markers ([_OmnisAudioHandler._artUri]'s Android-only
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
