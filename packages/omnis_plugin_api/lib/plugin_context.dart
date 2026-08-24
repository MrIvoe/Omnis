import 'package:omnis_plugin_api/base_track.dart';
import 'package:omnis_plugin_api/event_bus.dart';
import 'package:omnis_plugin_api/hardware_eq_band.dart';
import 'package:omnis_plugin_api/playlist.dart';
import 'package:omnis_plugin_api/repeat_mode.dart';
import 'package:omnis_plugin_api/service_registry.dart';

/// The capability surface the Core hands to every bundled plugin.
///
/// This is the seam that keeps the kernel plugin-agnostic. Before it
/// existed, a bundled plugin that needed to reach the audio engine had to
/// be handed a bespoke callback from `main_core.dart` (`ReplayGainPlugin`
/// and `EqualizerPlugin` each took their own `onGainChanged` closure), so
/// **adding a plugin meant editing the Core**. Now the Core builds one
/// concrete `PluginContext` (see the Omnis app's own
/// `lib/core/plugin_context.dart`), the `PluginManager` attaches it to
/// every registered plugin, and a new plugin reaches playback through
/// `context` without the kernel ever naming it.
///
/// **Abstract, not concrete** — unlike when this class lived in the app's
/// own `lib/core/`. A plugin that only ever calls `context!.foo()` never
/// needs to know or care that "foo" is implemented by forwarding to a
/// real `AudioEngine`/`AppSettings`/etc.; it only needs this interface to
/// compile, which is what lets `omnis_plugins` be a standalone package
/// with no dependency on the Omnis app at all. The Omnis app supplies the
/// one real implementation.
///
/// Deliberately a thin, complete pass-through of the engine's public API
/// — every stream, every transport method, every playback toggle — not a
/// hand-picked subset. A hand-picked subset means "add a plugin that
/// needs `next()`" (say) turns into "add `next()` to `PluginContext`
/// first," which is exactly the kind of core-keeps-growing problem
/// `lib/plugin_api/`'s doc describes for capability interfaces. Exposing
/// the whole surface once means it doesn't happen again.
///
/// [services] and [events] extend the same idea beyond playback: a
/// plugin can publish a capability under an interface
/// (`services.register(ILyricsProvider, this)`) instead of relying on
/// callers finding it by concrete type
/// (`pluginManager.bundled<LyricsPlugin>()`), and announce something
/// happened (`events.emit(...)`) without knowing who — if anyone — is
/// listening.
///
/// The `playerLayoutId` member, the four `request*Permission` methods,
/// and `loadLibraryTracks`/`loadPlaylists` exist because auditing every
/// bundled plugin found several reaching straight into the app's
/// `AppSettings`/`OmnisPermissions`/`LibraryStore`/`PlaylistStore`
/// singletons instead of going through this contract — a real gap, not
/// incidental. Each is here because it's genuinely cross-cutting state
/// (the active layout, an OS permission, the shared library/playlist
/// data) with no reasonable plugin-private alternative. Plugin-*private*
/// persisted state (a favorite-tracks set, cached lyrics, play history,
/// auto-tag bookkeeping, equalizer band gains) is deliberately **not**
/// here — each of those plugins already has its own `PluginStorage` (see
/// `MusicPlugin.storage`), which works even before a plugin is attached
/// to a context at all (handy in tests), and "this plugin's own state"
/// belongs in "this plugin's own storage," not funneled through a
/// shared interface that would otherwise keep growing forever.
abstract class PluginContext {
  /// Where a plugin publishes a capability under an interface type, and
  /// where anything (another plugin, a page) looks one up.
  ServiceRegistry get services;

  /// Where a plugin announces something happened, and where anything else
  /// can subscribe to hear about it, without either side knowing the
  /// other exists.
  EventBus get events;

  // --- Read-only observable state ---

  /// The track currently loaded, or `null` when the queue is empty.
  BaseTrack? get currentTrack;

  /// Read-only view of the current queue.
  List<BaseTrack> get queue;

  /// Current index into [queue]; `-1` when empty.
  int get currentIndex;

  /// Whether the player is currently playing.
  bool get isPlaying;

  // --- Streams ---

  /// Emits whenever the current track changes.
  Stream<BaseTrack?> get trackStream;

  /// Emits whenever the queue changes.
  Stream<List<BaseTrack>> get queueStream;

  /// Position stream (ticks at ~200ms).
  Stream<Duration> get positionStream;

  /// Duration stream.
  Stream<Duration?> get durationStream;

  // --- Transport ---

  /// Pause playback.
  Future<void> pause();

  /// Resume playback.
  Future<void> play();

  /// Stop playback.
  Future<void> stop();

  /// Skip to the next track, honouring shuffle/repeat. Returns `false`
  /// when there is no next track and [wrap] is `false`.
  Future<bool> next({bool wrap = false});

  /// Skip to the previous track (or restart the current one).
  Future<bool> previous();

  /// Seek within the current track.
  Future<void> seek(Duration position);

  /// Play the track at queue [index].
  Future<void> playAt(int index);

  /// Replace the queue and optionally start at [startIndex].
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0});

  /// Add a track to the end of the queue, preserving current playback.
  Future<void> addTrack(BaseTrack track);

  /// Insert a track to play immediately after the current one — §7's
  /// "play next," distinct from [addTrack]'s "add to queue" (which
  /// appends to the end). Preserves current playback, exactly like
  /// [addTrack]; with nothing currently playing, "next" is the front of
  /// the queue, so it behaves the same as [addTrack] in that case.
  Future<void> playNext(BaseTrack track);

  /// Remove the track at [index].
  Future<void> removeTrack(int index);

  // --- Volume / gain ---

  /// Master volume (0..1), before plugin gain contributions.
  double get volume;

  /// Set the global master volume.
  Future<void> setVolume(double volume);

  /// Contribute a named multiplicative gain factor.
  ///
  /// Every plugin uses its own [source] key, so contributions compose
  /// instead of overwriting one another.
  Future<void> setGain(String source, double multiplier);

  /// Drop this plugin's gain contribution (e.g. when it is disabled).
  Future<void> clearGain(String source);

  // --- Speed / pitch / silence ---

  /// Playback speed multiplier.
  double get speed;

  /// Set playback speed. Also shifts pitch unless [setPitch] compensates.
  Future<void> setSpeed(double speed);

  /// Current pitch factor.
  double get pitch;

  /// Set pitch independently of speed (1.0 = unshifted).
  Future<void> setPitch(double pitch);

  /// Whether skip-silence is on.
  bool get skipSilenceEnabled;

  /// Skip-silence toggle: shortens silent gaps instead of playing through
  /// them at normal speed.
  Future<void> setSkipSilenceEnabled(bool enabled);

  // --- Shuffle / repeat ---

  /// Shuffle playback toggle.
  bool get shuffleEnabled;

  /// Enable/disable shuffle.
  Future<void> setShuffleEnabled(bool enabled);

  /// Repeat mode (off / repeat whole queue / repeat current track).
  RepeatMode get repeatMode;

  /// Set the repeat mode.
  Future<void> setRepeatMode(RepeatMode mode);

  // --- Crossfade / gapless ---

  /// Crossfade duration (0 = disabled).
  Duration get crossfadeDuration;

  /// Whether a crossfade transition is in progress right now.
  bool get isCrossfading;

  /// Set the crossfade duration (0 disables it).
  void setCrossfadeDuration(Duration duration);

  /// Gapless mode flag.
  bool get gaplessEnabled;

  /// Enable/disable gapless concatenation.
  void setGaplessEnabled(bool enabled);

  // --- A-B repeat ---

  /// The current A-B loop points, or `null` if A-B repeat is off.
  (Duration a, Duration b)? get abRepeatRange;

  /// Point A, once marked (even before B is marked).
  Duration? get loopAMarker;

  /// Marks point A at [position] (defaults to the current position).
  void markLoopA([Duration? position]);

  /// Marks point B and starts looping if it's after A.
  bool markLoopB([Duration? position]);

  /// Clears A-B repeat.
  void clearLoop();

  // --- Equalizer ---

  /// Real per-band hardware equalizer bands, when the platform provides
  /// them (Android only, populated once a queue has loaded). `null`
  /// elsewhere — a plugin using this must fall back to its own virtual
  /// model when it is.
  List<HardwareEqBand>? get hardwareEqBands;

  /// Best-effort attempt to load [hardwareEqBands] sooner (e.g. before any
  /// track has played). Safe to call repeatedly; never throws.
  Future<void> ensureHardwareEqLoaded();

  /// The id of the currently selected Now Playing layout — used by
  /// `DrivingModePlugin` to switch to `'car_mode'` and back without
  /// touching the app's settings singleton directly.
  String get playerLayoutId;
  Future<void> setPlayerLayoutId(String value);

  // --- OS permissions — narrow, purpose-specific requests, matching
  // --- `OmnisPermissions`' real signatures in the Omnis app exactly.

  /// Requests broad storage write access, needed before a plugin can
  /// modify a local file's own tags. Returns whether it was granted.
  Future<bool> requestStorageWritePermission();

  /// Requests Bluetooth permissions, for a plugin that detects/controls a
  /// connected Bluetooth audio device. Returns whether every permission
  /// requested was granted.
  Future<bool> requestBluetoothPermission();

  /// Requests location access, for a plugin that needs speed/position.
  /// [always] additionally requests background location.
  Future<bool> requestLocationPermission({bool always = false});

  /// Requests microphone access, for a plugin that taps system audio via
  /// an API the OS gates behind this permission even when it isn't
  /// actually recording from the physical mic (e.g. Android's Visualizer
  /// API). Returns whether it was granted.
  Future<bool> requestMicrophonePermission();

  // --- Library / playlist read access — closes the gap that had
  // --- `BluetoothPlaybackPlugin` reaching into `LibraryStore`/
  // --- `PlaylistStore` directly to offer "play the whole library" /
  // --- "play a saved playlist."

  /// The full local library, same shape `LibraryStore.load()` already
  /// returns.
  Future<List<BaseTrack>> loadLibraryTracks();

  /// Every saved playlist, same shape `PlaylistStore.load()` already
  /// returns.
  Future<List<Playlist>> loadPlaylists();
}
