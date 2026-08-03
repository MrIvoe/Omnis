import 'package:omnis/core/base_track.dart';

/// Abstract base class for all plugins in the Omnis music engine.
///
/// The Core never references a concrete plugin. It only knows about
/// this interface plus the [PluginDispatcher] hooks, so a crashing
/// plugin can never take the player down.
abstract class MusicPlugin {
  /// Unique identifier for the plugin.
  String get id;

  /// Human-readable name of the plugin.
  String get name;

  /// Plugin description.
  String get description;

  /// Plugin version.
  String get version;

  /// Plugin author.
  String get author;

  /// Called once when the plugin is registered and enabled.
  Future<void> initialize();

  /// Called when a track starts playing.
  ///
  /// Plugins that want to react to playback (metadata fetch, scrobbling,
  /// lyrics, replay-gain) implement this hook. It is always executed
  /// inside the [PluginManager] sandbox.
  Future<void> onTrackStart(BaseTrack track);

  /// Called once per file during a library scan.
  Future<void> onLibraryScan(String file);

  /// Provides UI injection points.
  ///
  /// [locationID] values the Core publishes:
  ///  - `now_playing_overlay`
  ///  - `now_playing_bottom`
  ///  - `library_header`
  ///  - `settings_page`
  ///  - `sidebar_item`
  ///
  /// Return `null` when the plugin has nothing to show at this slot.
  dynamic uiSlot(String locationID);

  /// Called when the plugin is shut down.
  Future<void> dispose();

  /// Enable the plugin (no-op by default).
  Future<void> enable() async {}

  /// Disable the plugin (no-op by default).
  Future<void> disable() async {}
}
