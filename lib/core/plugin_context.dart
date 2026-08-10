import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/library_repository.dart';
import 'package:omnis/core/permissions.dart';
import 'package:omnis/core/playlist_store.dart';
import 'package:omnis_plugin_api/base_track.dart';
import 'package:omnis_plugin_api/event_bus.dart';
import 'package:omnis_plugin_api/plugin_context.dart';
import 'package:omnis_plugin_api/service_registry.dart';

export 'package:omnis_plugin_api/plugin_context.dart' show PluginContext;

/// The Omnis app's one real implementation of `PluginContext` (the
/// abstract interface in `omnis_plugin_api`).
///
/// `PluginContext` used to be a concrete class living entirely in this
/// file. It's now an interface in `omnis_plugin_api` so `omnis_plugins`
/// (the bundled-plugin package) can depend on it without depending on
/// this app — this class is where that interface actually meets the real
/// `AudioEngine`/`AppSettings`/`OmnisPermissions`/`LibraryRepository`/
/// `PlaylistStore` singletons. `MainCore` builds exactly one of these and
/// hands it to every registered plugin via `PluginManager`/`attach`.
///
/// Deliberately a thin, complete pass-through — every stream, every
/// transport method, every playback toggle — not a hand-picked subset.
/// A hand-picked subset means "add a plugin that needs `next()`" (say)
/// turns into "add `next()` to `PluginContext` first," which is exactly
/// the kind of core-keeps-growing problem `lib/plugin_api/`'s doc
/// describes for capability interfaces.
class OmnisPluginContext implements PluginContext {
  /// The live audio engine. Not part of the abstract interface (a plugin
  /// depending on `omnis_plugin_api` alone can't name `AudioEngine`), but
  /// still available to any Omnis-app code that holds a concrete
  /// `OmnisPluginContext` rather than the `PluginContext` interface type.
  final AudioEngine audioEngine;

  @override
  final ServiceRegistry services;

  @override
  final EventBus events;

  const OmnisPluginContext({
    required this.audioEngine,
    required this.services,
    required this.events,
  });

  // --- Read-only observable state ---

  @override
  BaseTrack? get currentTrack => audioEngine.currentTrack;

  @override
  List<BaseTrack> get queue => audioEngine.queue;

  @override
  int get currentIndex => audioEngine.currentIndex;

  @override
  bool get isPlaying => audioEngine.isPlaying;

  // --- Streams ---

  @override
  Stream<BaseTrack?> get trackStream => audioEngine.trackStream;

  @override
  Stream<List<BaseTrack>> get queueStream => audioEngine.queueStream;

  @override
  Stream<Duration> get positionStream => audioEngine.positionStream;

  @override
  Stream<Duration?> get durationStream => audioEngine.durationStream;

  // --- Transport ---

  @override
  Future<void> pause() => audioEngine.pause();

  @override
  Future<void> play() => audioEngine.play();

  @override
  Future<void> stop() => audioEngine.stop();

  @override
  Future<bool> next({bool wrap = false}) => audioEngine.next(wrap: wrap);

  @override
  Future<bool> previous() => audioEngine.previous();

  @override
  Future<void> seek(Duration position) => audioEngine.seek(position);

  @override
  Future<void> playAt(int index) => audioEngine.playAt(index);

  @override
  Future<void> setQueue(List<BaseTrack> tracks, {int startIndex = 0}) =>
      audioEngine.setQueue(tracks, startIndex: startIndex);

  @override
  Future<void> addTrack(BaseTrack track) => audioEngine.addTrack(track);

  @override
  Future<void> removeTrack(int index) => audioEngine.removeTrack(index);

  // --- Volume / gain ---

  @override
  double get volume => audioEngine.volume;

  @override
  Future<void> setVolume(double volume) => audioEngine.setVolume(volume);

  @override
  Future<void> setGain(String source, double multiplier) =>
      audioEngine.setGainContribution(source, multiplier);

  @override
  Future<void> clearGain(String source) =>
      audioEngine.clearGainContribution(source);

  // --- Speed / pitch / silence ---

  @override
  double get speed => audioEngine.speed;

  @override
  Future<void> setSpeed(double speed) => audioEngine.setSpeed(speed);

  @override
  double get pitch => audioEngine.pitch;

  @override
  Future<void> setPitch(double pitch) => audioEngine.setPitch(pitch);

  @override
  bool get skipSilenceEnabled => audioEngine.skipSilenceEnabled;

  @override
  Future<void> setSkipSilenceEnabled(bool enabled) =>
      audioEngine.setSkipSilenceEnabled(enabled);

  // --- Shuffle / repeat ---

  @override
  bool get shuffleEnabled => audioEngine.shuffleEnabled;

  @override
  Future<void> setShuffleEnabled(bool enabled) =>
      audioEngine.setShuffleEnabled(enabled);

  @override
  RepeatMode get repeatMode => audioEngine.repeatMode;

  @override
  Future<void> setRepeatMode(RepeatMode mode) =>
      audioEngine.setRepeatMode(mode);

  // --- Crossfade / gapless ---

  @override
  Duration get crossfadeDuration => audioEngine.crossfadeDuration;

  @override
  bool get isCrossfading => audioEngine.isCrossfading;

  @override
  void setCrossfadeDuration(Duration duration) =>
      audioEngine.setCrossfadeDuration(duration);

  @override
  bool get gaplessEnabled => audioEngine.gaplessEnabled;

  @override
  void setGaplessEnabled(bool enabled) =>
      audioEngine.setGaplessEnabled(enabled);

  // --- A-B repeat ---

  @override
  (Duration a, Duration b)? get abRepeatRange => audioEngine.abRepeatRange;

  @override
  Duration? get loopAMarker => audioEngine.loopAMarker;

  @override
  void markLoopA([Duration? position]) => audioEngine.markLoopA(position);

  @override
  bool markLoopB([Duration? position]) => audioEngine.markLoopB(position);

  @override
  void clearLoop() => audioEngine.clearLoop();

  // --- Equalizer ---

  @override
  List<HardwareEqBand>? get hardwareEqBands => audioEngine.hardwareEqBands;

  @override
  Future<void> ensureHardwareEqLoaded() =>
      audioEngine.ensureHardwareEqLoaded();

  // --- Genuinely cross-cutting app state — see this interface's own doc
  // --- comment for why plugin-*private* persisted state (favorites,
  // --- lyrics, play history, auto-tag bookkeeping, EQ bands) is
  // --- deliberately not here; each of those plugins uses its own
  // --- PluginStorage instead.

  @override
  String get playerLayoutId => AppSettings.instance.playerLayoutId;

  @override
  Future<void> setPlayerLayoutId(String value) async {
    AppSettings.instance.playerLayoutId = value;
  }

  // --- OS permissions ---

  @override
  Future<bool> requestStorageWritePermission() =>
      OmnisPermissions.requestStorageWrite();

  @override
  Future<bool> requestBluetoothPermission() =>
      OmnisPermissions.requestBluetooth();

  @override
  Future<bool> requestLocationPermission({bool always = false}) =>
      OmnisPermissions.requestLocation(always: always);

  // --- Library / playlist read access ---

  @override
  Future<List<BaseTrack>> loadLibraryTracks() => LibraryRepository.instance.load();

  @override
  Future<List<Playlist>> loadPlaylists() => PlaylistStore.instance.load();
}
