import 'package:omnis_plugin_api/base_track.dart';
import 'package:omnis_plugin_api/plugin_context.dart';
import 'package:omnis_plugin_api/plugin_destination.dart';
import 'package:omnis_plugin_api/plugin_storage.dart';

/// Abstract base class for all plugins in the Omnis music engine.
///
/// The Core never references a concrete plugin. It only knows about
/// this interface plus the `PluginManager` hooks, so a crashing
/// plugin can never take the player down.
abstract class MusicPlugin {
  PluginContext? _context;
  PluginStorage? _storage;

  /// The Core capabilities available to this plugin.
  ///
  /// `null` until the plugin is registered with a `PluginManager` that has
  /// a context attached — and in unit tests that construct the plugin
  /// directly. Always call through `context?.` so a detached plugin
  /// degrades to a no-op instead of throwing.
  PluginContext? get context => _context;

  /// This plugin's own namespaced key-value store. Unlike [context], never
  /// `null` — safe to use from a plugin constructed directly in a test,
  /// with no `PluginManager` involved at all. See [PluginStorage].
  PluginStorage get storage => _storage ??= PluginStorage(id);

  /// Called by the `PluginManager` at registration, before [initialize].
  ///
  /// This is what lets a plugin reach the audio engine without the Core
  /// knowing the plugin exists. Override it only to react to attachment;
  /// always call `super.attach(context)`.
  void attach(PluginContext context) {
    _context = context;
  }

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

  /// Whether this plugin makes its own outbound network requests (an API
  /// lookup, OAuth, streaming playback) — as opposed to one that only
  /// touches local files/storage. Defaults `false`; a plugin that does
  /// reach the network overrides this to `true`. Drives the "disable
  /// every plugin with network access" privacy control on the Plugins
  /// page — a bulk, one-tap version of switching each one off by hand.
  bool get usesNetwork => false;

  /// Whether this plugin's [initialize] depends on another bundled
  /// plugin having already initialized first — e.g. reading a
  /// `ServiceRegistry` interface that other plugin registers inside its
  /// own `initialize()`. Defaults `false`; most plugins have no such
  /// dependency and stay eligible for parallel initialization. Only
  /// override this for a plugin with a *documented* dependency (see
  /// `Omnis-Plugins`' `bundled_plugins.dart` for the two known today) —
  /// don't set it defensively "just in case," since every plugin flagged
  /// `true` delays app launch by moving it out of the parallel round.
  bool get requiresSequentialInit => false;

  /// Called once when the plugin is registered and enabled.
  Future<void> initialize();

  /// Called when a track starts playing.
  ///
  /// Plugins that want to react to playback (metadata fetch, scrobbling,
  /// lyrics, replay-gain) implement this hook. It is always executed
  /// inside the `PluginManager` sandbox.
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
  ///  - `plugin_settings` — this plugin's own configuration UI, shown on
  ///    a dedicated page reached by tapping it in the Plugins list (see
  ///    `PluginSettingsPage`). Unlike every other location, which every
  ///    enabled plugin is asked about at once and whose results are
  ///    combined, this one is only ever asked of a single plugin — the
  ///    one the user tapped — so a plugin can own settings that used to
  ///    require adding a section to the shared Settings page.
  ///
  /// Return `null` when the plugin has nothing to show at this slot.
  dynamic uiSlot(String locationID);

  /// Optional. A plugin that wants a persistent top-level tab (not
  /// just an injected slot) returns one or more [PluginDestination]s
  /// here. Default: none — most plugins have nothing to add at this
  /// level and stay purely `uiSlot`-based.
  ///
  /// Called once per `PluginManager.homeDestinations` read (today:
  /// every time `home_page.dart` rebuilds), sandboxed the same as
  /// every other hook — a throwing override degrades to "this plugin
  /// contributes no destinations this time," never a crash.
  List<PluginDestination> homeDestinations() => const [];

  /// Called when the plugin is shut down.
  Future<void> dispose();

  /// Called when the user re-enables a plugin that was already initialized.
  Future<void> enable() async {}

  /// Called when the user disables the plugin. Use this to release any
  /// effect the plugin has on playback (e.g. drop a gain contribution) so
  /// a disabled plugin leaves no trace behind.
  Future<void> disable() async {}

  /// Periodic liveness check for background heartbeat monitoring
  /// (item 28). Override to prove the plugin is still genuinely
  /// responsive — e.g. a server-backed provider plugin pinging its
  /// configured host. Default is a no-op: a plugin that doesn't override
  /// this is simply never flagged unresponsive, the same "opt-in, zero
  /// behavior change until an author asks for it" stance external
  /// plugins' manifest `hooks: [heartbeat]` declaration already takes.
  /// Called through `PluginSandbox.run` by `PluginManager.runHeartbeats`,
  /// so a throw or a call that doesn't return within its timeout produces
  /// an ordinary health record tagged `heartbeat`, feeding the existing
  /// auto-disable/health-page machinery for free.
  Future<void> heartbeat() async {}
}
