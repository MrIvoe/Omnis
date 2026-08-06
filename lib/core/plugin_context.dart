import 'package:just_audio/just_audio.dart' show PlayerState;
import 'package:omnis/core/app_settings.dart' show RepeatMode;
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/event_bus.dart';
import 'package:omnis/core/service_registry.dart';

/// The capability surface the Core hands to every bundled plugin.
///
/// This is the seam that keeps the kernel plugin-agnostic. Before it
/// existed, a bundled plugin that needed to reach the audio engine had to
/// be handed a bespoke callback from `main_core.dart` (`ReplayGainPlugin`
/// and `EqualizerPlugin` each took their own `onGainChanged` closure), so
/// **adding a plugin meant editing the Core**. Now the Core builds one
/// [PluginContext], the [PluginManager] attaches it to every registered
/// plugin, and a new plugin reaches playback through `context` without the
/// kernel ever naming it.
///
/// Deliberately a thin, complete pass-through of [AudioEngine]'s public
/// API — every stream, every transport method, every playback toggle —
/// not a hand-picked subset. A hand-picked subset means "add a plugin
/// that needs `next()`" (say) turns into "add `next()` to `PluginContext`
/// first," which is exactly the kind of core-keeps-growing problem
/// `lib/plugin_api/`'s doc describes for capability interfaces. Exposing
/// the whole surface once means it doesn't happen again: a plugin nobody
/// has written yet that wants to react to position ticks, or drive
/// transport directly, already has what it needs today.
///
/// [services] and [events] extend the same idea beyond playback: a
/// plugin can publish a capability under an interface
/// (`services.register(ILyricsProvider, this)`) instead of relying on
/// callers finding it by concrete type
/// (`pluginManager.bundled<LyricsPlugin>()`), and announce something
/// happened (`events.emit(...)`) without knowing who — if anyone — is
/// listening. Both are the *same* registry/bus instance the
/// [PluginManager] exposes to UI code, so a plugin registering a service
/// and a page looking it up are talking to one shared object, not two.
class PluginContext {
  /// The live audio engine. Exposed directly too, for the rare case a
  /// plugin genuinely needs something below — everything below is just a
  /// documented, discoverable pass-through of this.
  final AudioEngine audioEngine;

  /// Where a plugin publishes a capability under an interface type, and
  /// where anything (another plugin, a page) looks one up.
  final ServiceRegistry services;

  /// Where a plugin announces something happened, and where anything else
  /// can subscribe to hear about it, without either side knowing the
  /// other exists.
  final EventBus events;

  const PluginContext({
    required this.audioEngine,
    required this.services,
    required this.events,
  });

  // --- Read-only observable state ---

  /// The track currently loaded, or `null` when the queue is empty.
  BaseTrack? get currentTrack => audioEngine.currentTrack;

  /// Read-only view of the current queue.
  List<BaseTrack> get queue => audioEngine.queue;

  /// Current index into [queue]; `-1` when empty.
  int get currentIndex => audioEngine.currentIndex;

  /// Whether the player is currently playing.
  bool get isPlaying => audioEngine.isPlaying;

  // --- Streams ---

  /// Emits whenever the current track changes.
  Stream<BaseTrack?> get trackStream => audioEngine.trackStream;

  /// Emits whenever the queue changes.
  Stream<List<BaseTrack>> get queueStream => audioEngine.queueStream;

  /// Position stream (ticks at ~200ms).
  Stream<Duration> get positionStream => audioEngine.positionStream;

  /// Duration stream.
  Stream<Duration?> get durationStream => audioEngine.durationStream;

  /// Playback state stream (just_audio's own `PlayerState`, the same type
  /// `AudioEngine.playerStateStream` already exposes — not re-wrapped).
  Stream<PlayerState> get playerStateStream => audioEngine.playerStateStream;

  // --- Transport ---

  /// Pause playback.
  Future<void> pause() => audioEngine.pause();

  /// Resume playback.
  Future<void> play() => audioEngine.play();

  /// Stop playback.
  Future<void> stop() => audioEngine.stop();

  /// Skip to the next track, honouring shuffle/repeat. Returns `false`
  /// when there is no next track and [wrap] is `false`.
  Future<bool> next({bool wrap = false}) => audioEngine.next(wrap: wrap);

  /// Skip to the previous track (or restart the current one).
  Future<bool> previous() => audioEngine.previous();

  /// Seek within the current track.
  Future<void> seek(Duration position) => audioEngine.seek(position);

  /// Play the track at queue [index].
  Future<void> playAt(int index) => audioEngine.playAt(index);

  /// Replace the queue and optionally start at [startIndex].
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) =>
      audioEngine.setQueue(tracks, startIndex: startIndex);

  /// Add a track to the end of the queue, preserving current playback.
  Future<void> addTrack(BaseTrack track) => audioEngine.addTrack(track);

  /// Remove the track at [index].
  Future<void> removeTrack(int index) => audioEngine.removeTrack(index);

  // --- Volume / gain ---

  /// Master volume (0..1), before plugin gain contributions.
  double get volume => audioEngine.volume;

  /// Set the global master volume.
  Future<void> setVolume(double volume) => audioEngine.setVolume(volume);

  /// Contribute a named multiplicative gain factor.
  ///
  /// Every plugin uses its own [source] key, so contributions compose
  /// instead of overwriting one another. See
  /// [AudioEngine.setGainContribution].
  Future<void> setGain(String source, double multiplier) =>
      audioEngine.setGainContribution(source, multiplier);

  /// Drop this plugin's gain contribution (e.g. when it is disabled).
  Future<void> clearGain(String source) =>
      audioEngine.clearGainContribution(source);

  // --- Speed / pitch / silence ---

  /// Playback speed multiplier.
  double get speed => audioEngine.speed;

  /// Set playback speed. Also shifts pitch unless [setPitch] compensates
  /// — see [AudioEngine.setSpeed]'s doc.
  Future<void> setSpeed(double speed) => audioEngine.setSpeed(speed);

  /// Current pitch factor.
  double get pitch => audioEngine.pitch;

  /// Set pitch independently of speed (1.0 = unshifted).
  Future<void> setPitch(double pitch) => audioEngine.setPitch(pitch);

  /// Whether skip-silence is on.
  bool get skipSilenceEnabled => audioEngine.skipSilenceEnabled;

  /// Skip-silence toggle: shortens silent gaps instead of playing through
  /// them at normal speed.
  Future<void> setSkipSilenceEnabled(bool enabled) =>
      audioEngine.setSkipSilenceEnabled(enabled);

  // --- Shuffle / repeat ---

  /// Shuffle playback toggle.
  bool get shuffleEnabled => audioEngine.shuffleEnabled;

  /// Enable/disable shuffle.
  Future<void> setShuffleEnabled(bool enabled) =>
      audioEngine.setShuffleEnabled(enabled);

  /// Repeat mode (off / repeat whole queue / repeat current track).
  RepeatMode get repeatMode => audioEngine.repeatMode;

  /// Set the repeat mode.
  Future<void> setRepeatMode(RepeatMode mode) =>
      audioEngine.setRepeatMode(mode);

  // --- Crossfade / gapless ---

  /// Crossfade duration (0 = disabled).
  Duration get crossfadeDuration => audioEngine.crossfadeDuration;

  /// Whether a crossfade transition is in progress right now.
  bool get isCrossfading => audioEngine.isCrossfading;

  /// Set the crossfade duration (0 disables it).
  void setCrossfadeDuration(Duration duration) =>
      audioEngine.setCrossfadeDuration(duration);

  /// Gapless mode flag.
  bool get gaplessEnabled => audioEngine.gaplessEnabled;

  /// Enable/disable gapless concatenation.
  void setGaplessEnabled(bool enabled) =>
      audioEngine.setGaplessEnabled(enabled);

  // --- A-B repeat ---

  /// The current A-B loop points, or `null` if A-B repeat is off.
  (Duration a, Duration b)? get abRepeatRange => audioEngine.abRepeatRange;

  /// Point A, once marked (even before B is marked).
  Duration? get loopAMarker => audioEngine.loopAMarker;

  /// Marks point A at [position] (defaults to the current position).
  void markLoopA([Duration? position]) => audioEngine.markLoopA(position);

  /// Marks point B and starts looping if it's after A.
  bool markLoopB([Duration? position]) => audioEngine.markLoopB(position);

  /// Clears A-B repeat.
  void clearLoop() => audioEngine.clearLoop();

  // --- Equalizer ---

  /// Real per-band hardware equalizer bands, when the platform provides
  /// them (Android only, populated once a queue has loaded). `null`
  /// elsewhere — a plugin using this must fall back to its own virtual
  /// model when it is.
  List<HardwareEqBand>? get hardwareEqBands => audioEngine.hardwareEqBands;

  /// Best-effort attempt to load [hardwareEqBands] sooner (e.g. before any
  /// track has played). Safe to call repeatedly; never throws.
  Future<void> ensureHardwareEqLoaded() => audioEngine.ensureHardwareEqLoaded();
}
