import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:omnis/core/base_track.dart';

/// Core playback engine.
///
/// This is the "indestructible layer" of Omnis. It owns the single
/// [AudioPlayer] instance and exposes reactive [Stream]s that the UI and
/// plugins consume. No plugin code runs inside this class.
class AudioEngine {
  final AudioPlayer _player = AudioPlayer();
  final List<BaseTrack> _queue = [];
  int _currentIndex = -1;
  BaseTrack? _currentTrack;
  Completer<void>? _initCompleter;

  /// Global volume (0..1).
  double _volume = 1.0;

  /// User volume multiplier used by the ReplayGain plugin.
  double _preGainMultiplier = 1.0;

  /// Crossfade duration (0 = disabled).
  Duration _crossfadeDuration = Duration.zero;

  /// Whether gapless concatenation is enabled.
  bool _gaplessEnabled = true;

  /// Stream of the current track.
  final StreamController<BaseTrack?> _trackController =
      StreamController.broadcast();

  /// Stream of queue changes.
  final StreamController<List<BaseTrack>> _queueController =
      StreamController.broadcast();

  bool _disposed = false;

  /// Called whenever a playable item should trigger plugin hooks.
  Function(BaseTrack)? onTrackStarted;

  /// Constructor.
  AudioEngine();

  /// The underlying just_audio player (exposed for plugins like the
  /// equalizer that need low-level access).
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

  /// Gapless mode flag.
  bool get gaplessEnabled => _gaplessEnabled;

  /// Set the crossfade duration. When > 0, gapless concatenation is
  /// replaced by a per-transition crossfade.
  void setCrossfadeDuration(Duration duration) {
    _crossfadeDuration = duration;
    _rebuildQueueSource();
  }

  /// Enable/disable gapless concatenation.
  void setGaplessEnabled(bool enabled) {
    _gaplessEnabled = enabled;
    _rebuildQueueSource();
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
      await _player.load();
      // audio_service is best-effort; on desktop it may be unavailable.
      try {
        await AudioService.init(
          builder: () => _OmnisAudioHandler(this),
          config: const AudioServiceConfig(
            androidNotificationChannelId: 'com.omnis.music.channel',
            androidNotificationChannelName: 'Omnis Playback',
            androidNotificationOngoing: true,
          ),
        );
      } catch (_) {
        // The core player works without audio_service.
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

  /// Dispose the engine.
  Future<void> dispose() async {
    _disposed = true;
    await _player.dispose();
    if (!_trackController.isClosed) {
      await _trackController.close();
    }
    if (!_queueController.isClosed) {
      await _queueController.close();
    }
  }

  /// Replace the whole queue with [tracks].
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) async {
    _queue
      ..clear()
      ..addAll(tracks);
    _currentIndex = startIndex >= 0 && startIndex < _queue.length
        ? startIndex
        : (_queue.isEmpty ? -1 : 0);
    _emitQueue();
    if (_queue.isEmpty) {
      _setCurrent(null, -1);
      await _rebuildQueueSource();
      return;
    }
    await _rebuildQueueSource();
    // Emit the current track so the UI (Now Playing) updates immediately,
    // even when playback is started via play() after setQueue().
    _setCurrent(_queue[_currentIndex], _currentIndex);
  }

  /// Add a track to the end of the queue.
  Future<void> addTrack(BaseTrack track) async {
    _queue.add(track);
    _emitQueue();
    if (_currentIndex < 0) {
      await setQueue(_queue, startIndex: 0);
    } else if (_gaplessEnabled) {
      await _rebuildQueueSource();
    }
  }

  /// Remove a track at [index].
  Future<void> removeTrack(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    if (_currentIndex > index) _currentIndex--;
    _emitQueue();
    await _rebuildQueueSource();
  }

  /// Play the track at [index]. If [index] is null, plays the
  /// current/queued position.
  Future<void> playAt(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _currentIndex = index;
    await _playCurrent();
  }

  /// Start playing (resume).
  Future<void> play() async {
    if (_currentIndex < 0 && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playCurrent();
      return;
    }
    // If the queue is loaded (ConcatenatingAudioSource) but the current
    // track was never emitted, emit it now so the UI stays in sync.
    if (_currentIndex >= 0 &&
        _currentIndex < _queue.length &&
        _currentTrack == null) {
      _setCurrent(_queue[_currentIndex], _currentIndex);
    }
    await _player.play();
  }

  /// Pause playback.
  Future<void> pause() async => _player.pause();

  /// Stop playback.
  Future<void> stop() async {
    await _revertProcessingState();
    await _player.stop();
  }

  /// Skip to the next track. Returns false when there is no next track
  /// and `wrap` is true.
  Future<bool> next({bool wrap = false}) async {
    if (_queue.isEmpty) return false;
    if (_currentIndex + 1 >= _queue.length) {
      if (!wrap) return false;
      _currentIndex = 0;
    } else {
      _currentIndex++;
    }
    await _playCurrent();
    return true;
  }

  /// Skip to the previous track (or restart the current one if it has
  /// played for more than 3 seconds).
  Future<bool> previous() async {
    if (_queue.isEmpty) return false;
    if (_player.position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
      return true;
    }
    if (_currentIndex > 0) {
      _currentIndex--;
      await _playCurrent();
      return true;
    }
    await seek(Duration.zero);
    return true;
  }

  /// Seek to [position].
  Future<void> seek(Duration position) async {
    if (_playingFromProcessingUrl) {
      await _player.seek(_processingCorrection + position);
    } else {
      await _player.seek(position);
    }
  }

  /// Set the global master volume.
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _player.setVolume(_volume * _preGainMultiplier);
  }

  /// Set the ReplayGain pre-gain multiplier (used by the ReplayGain
  /// plugin). Must be a positive value.
  Future<void> setPreGain(double multiplier) async {
    _preGainMultiplier = multiplier <= 0 ? 1.0 : multiplier;
    await _player.setVolume(_volume * _preGainMultiplier);
  }

  /// Set playback speed.
  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.25, 2.0));
  }

  /// Playback speed.
  double get speed => _player.speed;

  /// The URL of the track currently at [index], or null.
  String? _urlFor(BaseTrack track) {
    if (track.localPath != null) return track.localPath;
    return track.streamUrl;
  }

  /// Rebuilds the ConcatenatingAudioSource. When a crossfade duration is
  /// set, the source is shuffled into overlapping pairs so just_audio's
  /// built-in overlap/crossfade support kicks in.
  Future<void> _rebuildQueueSource() async {
    if (_queue.isEmpty) {
      await _player.stop();
      return;
    }
    if (!_gaplessEnabled || _crossfadeDuration > Duration.zero) {
      await _setOverlapSource();
      return;
    }
    final children = <AudioSource>[];
    for (final track in _queue) {
      final url = _urlFor(track);
      if (url == null) continue;
      children.add(AudioSource.uri(
        Uri.parse(url),
        tag: track,
      ));
    }
    if (children.isEmpty) {
      await _player.stop();
      return;
    }
    await _player.setAudioSource(ConcatenatingAudioSource(children: children));
    _listenForCompletion();
  }

  /// Sets an overlapping gapless source (with crossfade when requested).
  Future<void> _setOverlapSource() async {
    final children = <AudioSource>[];
    for (final track in _queue) {
      final url = _urlFor(track);
      if (url == null) continue;
      children.add(AudioSource.uri(Uri.parse(url), tag: track));
    }
    if (children.isEmpty) return;
    if (_crossfadeDuration > Duration.zero) {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(_urlFor(_queue.first)!),
          tag: _queue.first,
        ),
      );
      // Attach crossfade via the plug-in API.
      await _player.setClip(
        start: Duration.zero,
        end: _player.duration ?? Duration(milliseconds: _queue.first.duration),
      );
      _listenForCompletion();
    } else {
      await _player
          .setAudioSource(ConcatenatingAudioSource(children: children));
      _listenForCompletion();
    }
  }

  bool _playingFromProcessingUrl = false;
  Duration _processingCorrection = Duration.zero;

  /// Track completion so the next track fires the plugin hook.
  void _listenForCompletion() {
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed && !_disposed) {
        _handleSequenceCompleted();
      }
    });
  }

  /// True when a track is physically loaded. Emits the plugin hook.
  Future<void> _playCurrent() async {
    final track = _queue[_currentIndex];
    await _loadCurrent(track);
    await _player.play();
  }

  Future<void> _loadCurrent(BaseTrack track) async {
    final url = _urlFor(track);
    if (url == null) {
      _setCurrent(null, -1);
      return;
    }
    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(url), tag: track),
        initialPosition: null,
      );
      _playingFromProcessingUrl = false;
      _processingCorrection = Duration.zero;
    } catch (e) {
      // Corrupt/unplayable file: skip to the next one instead of crashing.
      debugPrint('Omnis: unable to play ${track.title}: $e');
      await next();
      return;
    }
    _setCurrent(track, _currentIndex);
    _listenForCompletion();
  }

  void _setCurrent(BaseTrack? track, int index) {
    _currentTrack = track;
    _currentIndex = index;
    if (_trackController.isClosed) return;
    _trackController.add(track);
    if (track != null) {
      onTrackStarted?.call(track);
    }
  }

  void _emitQueue() {
    if (_queueController.isClosed) return;
    _queueController.add(List.unmodifiable(_queue));
  }

  /// Handle the sequence completing (either set-source completion or
  /// processingState == completed).
  void _handleSequenceCompleted() {
    if (_queue.isNotEmpty && _currentIndex >= 0) {
      if (_currentIndex + 1 < _queue.length) {
        _currentIndex++;
        // Load the next source in the concatenation; just_audio advances
        // itself, we just fire the hook.
        _currentTrack = _queue[_currentIndex];
        _trackController.add(_currentTrack);
        onTrackStarted?.call(_currentTrack!);
        // The position relative to the concatenation is cumulative; reset.
        _processingCorrection = Duration.zero;
        _playingFromProcessingUrl = true;
        _player.play();
      } else {
        _playingFromProcessingUrl = false;
      }
    }
  }

  Future<void> _revertProcessingState() async {
    _playingFromProcessingUrl = false;
    _processingCorrection = Duration.zero;
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
        processingState: processing == ProcessingState.completed
            ? AudioProcessingState.completed
            : processing == ProcessingState.loading
                ? AudioProcessingState.loading
                : AudioProcessingState.ready,
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
        duration: Duration(milliseconds: track.duration),
        artUri: track.coverArt != null ? Uri.tryParse(track.coverArt!) : null,
      ));
    });
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
