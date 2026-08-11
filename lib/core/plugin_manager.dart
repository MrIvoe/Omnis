import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/event_bus.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:omnis/core/plugin_manifest.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/core/plugin_sandbox_bridge.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/core/service_registry.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:path/path.dart' as p;

/// A plugin that is loaded at runtime.
///
/// Two kinds of plugins are unified here:
///  - [inProcess]: a [MusicPlugin] compiled into the app (the bundled
///    plugins in the separate `omnis_plugins` package).
///  - [external]: a plugin downloaded from GitHub and executed with
///    dart_eval. Its hooks receive JSON Maps (serialised tracks).
class ManagedPlugin {
  /// Plugin id.
  final String id;

  /// Display name.
  final String name;

  /// Description.
  final String description;

  /// Version.
  final String version;

  /// Author.
  final String author;

  /// Source URL the plugin was installed from (or `bundled`).
  final String sourceUrl;

  /// The in-process [MusicPlugin], if this is a compiled plugin.
  final MusicPlugin? inProcess;

  /// The external runtime, if this is a downloaded plugin.
  final PluginRuntime? external;

  /// Whether the plugin is currently enabled.
  bool enabled;

  /// Whether [MusicPlugin.initialize] has already run. Re-enabling an
  /// already-initialized plugin calls `enable()`, not `initialize()` again.
  bool initialized;

  /// Directory on disk (for external plugins).
  final String? directory;

  ManagedPlugin({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.author,
    required this.sourceUrl,
    this.inProcess,
    this.external,
    this.enabled = true,
    this.initialized = false,
    this.directory,
  });

  bool get isExternal => external != null;

  /// True for plugins compiled into the app (`lib/plugins/`).
  bool get isBundled => sourceUrl == 'bundled';
}

/// PluginManager is the heart of the micro-kernel plugin ecosystem.
///
/// It owns:
///  - registration of in-process [MusicPlugin]s
///  - installation of GitHub plugins via [PluginInstaller]
///  - runtime execution of downloaded plugins via [PluginRuntime]
///  - isolation of every hook call via [PluginSandbox] (crashes → health
///    dashboard, never the player)
///  - hot-swap: plugins can be enabled/disabled/uninstalled at runtime
class PluginManager {
  final PluginInstaller _installer;
  final PluginSandbox _sandbox;
  final List<ManagedPlugin> _plugins = [];
  final StreamController<List<ManagedPlugin>> _changes =
      StreamController.broadcast();

  /// Capability lookup by interface type (`ILyricsProvider`, ...) and
  /// event bus for plugin-to-plugin/plugin-to-UI announcements. Both are
  /// handed to every plugin via [PluginContext] (`context.services`/
  /// `context.events`) and are the *same* instances UI code reaches
  /// through this manager — a plugin registering a service and a page
  /// looking it up share one object, not two.
  final ServiceRegistry services = ServiceRegistry();
  final EventBus events = EventBus();

  /// Capabilities handed to every in-process plugin at registration.
  PluginContext? _context;

  bool _disposed = false;

  PluginManager({PluginInstaller? installer, PluginSandbox? sandbox})
      : _installer = installer ?? PluginInstaller(),
        _sandbox = sandbox ?? PluginSandbox() {
    _wireEventForwarding();
  }

  /// Forwards well-known app events to every enabled external plugin that
  /// declared `events` permission and a matching `onPluginEvent` hook —
  /// the "subscribe-only" half of the sandbox bridge (a plugin *emitting*
  /// its own events stays out of scope for now). Deliberately a small,
  /// explicit mapping of one known event type to one JSON shape, not a
  /// generic serializer — `FavoriteChangedEvent` is the only event type
  /// this app emits today (see its own doc comment in
  /// `packages/omnis_plugin_api/lib/events.dart`); adding a second means
  /// one more `on<T>().listen(...)` here, not new plumbing.
  void _wireEventForwarding() {
    events.on<FavoriteChangedEvent>().listen((event) {
      _forwardEvent({
        'type': 'FavoriteChanged',
        'trackId': event.trackId,
        'isFavorite': event.isFavorite,
      });
    });
  }

  void _forwardEvent(Map<String, dynamic> json) {
    for (final plugin in _enabled()) {
      final external = plugin.external;
      if (external == null) continue;
      if (!external.hasPermission(EventsPermission.domain)) continue;
      if (!external.hasHook('onPluginEvent')) continue;
      _sandbox.run(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'onPluginEvent',
        operation: () async {
          external.callHook('onPluginEvent', [json]);
          return null;
        },
      );
    }
  }

  /// The sandbox used for all plugin calls.
  PluginSandbox get sandbox => _sandbox;

  /// The installer used to fetch plugins from GitHub.
  PluginInstaller get installer => _installer;

  /// Live list of managed plugins.
  List<ManagedPlugin> get plugins => List.unmodifiable(_plugins);

  /// Stream of plugin list changes (register/install/uninstall).
  Stream<List<ManagedPlugin>> get changes => _changes.stream;

  /// Attach the Core capability surface.
  ///
  /// Must be called before [register] so plugins can reach playback. Any
  /// plugin already registered is attached retroactively.
  void attachContext(PluginContext context) {
    _context = context;
    for (final plugin in _plugins) {
      plugin.inProcess?.attach(context);
    }
  }

  /// Register an in-process [MusicPlugin] (from the `omnis_plugins`
  /// package, or a plugin the caller constructed directly).
  void register(MusicPlugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) return;
    final context = _context;
    if (context != null) {
      // attach() is a plugin-authored override — sandbox it like every
      // other plugin hook, so a throwing attach() can't take registration
      // (and therefore app boot) down with it.
      _sandbox.runSync(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'attach',
        operation: () {
          plugin.attach(context);
          return null;
        },
      );
    }
    final managed = ManagedPlugin(
      id: plugin.id,
      name: plugin.name,
      description: plugin.description,
      version: plugin.version,
      author: plugin.author,
      sourceUrl: 'bundled',
      inProcess: plugin,
      // A plugin the user switched off previously must come back off.
      enabled: !AppSettings.instance.isPluginDisabled(plugin.id),
    );
    _plugins.add(managed);
    _emit();
  }

  /// Registers every plugin [factory] produces, without letting a
  /// throwing factory — or a single throwing plugin constructor inside
  /// it, since `factory` is typically a single list-literal expression
  /// like `createBundledPlugins` — take the rest down with it.
  ///
  /// This is the coarse, always-on safety net: even a bundled-plugins
  /// registry that changes shape later and reintroduces an unguarded
  /// throw can't crash app boot through this call site. It complements,
  /// rather than replaces, defensive construction inside `factory`
  /// itself (see `createBundledPlugins`), which additionally keeps one
  /// broken plugin from taking out the others in the same list.
  void registerAll(List<MusicPlugin> Function() factory) {
    final plugins = _sandbox.runSync(
      pluginId: 'bundled',
      pluginName: 'bundled plugins',
      hook: 'construct',
      operation: factory,
    );
    if (plugins == null) return;
    for (final plugin in plugins) {
      register(plugin);
    }
  }

  /// Find a registered in-process plugin by type.
  ///
  /// This is how the UI binds to the *shared* instance of a bundled plugin.
  /// Pages used to construct their own (`EqualizerPlugin()`,
  /// `VisualizerPlugin()`, `SleepTimerPlugin()`), which were never
  /// registered, never received hooks, and never reached the audio engine —
  /// so the controls wired to them did nothing.
  ///
  /// When [onlyEnabled] is true, a disabled plugin resolves to `null`, so
  /// switching a plugin off in Settings actually removes its UI.
  T? bundled<T extends MusicPlugin>({bool onlyEnabled = false}) {
    for (final managed in _plugins) {
      final plugin = managed.inProcess;
      if (plugin is T) {
        if (onlyEnabled && !managed.enabled) return null;
        return plugin;
      }
    }
    return null;
  }

  /// Look up a managed plugin by its id.
  ManagedPlugin? byId(String id) {
    for (final plugin in _plugins) {
      if (plugin.id == id) return plugin;
    }
    return null;
  }

  /// Initialize all enabled plugins (in-process and external).
  ///
  /// Each plugin is initialised inside the sandbox: a failing plugin does
  /// not block the rest.
  Future<void> initializeAll() async {
    for (final plugin in List<ManagedPlugin>.from(_plugins)) {
      if (plugin.enabled) await initPlugin(plugin);
    }
  }

  /// Initialize a single plugin.
  Future<void> initPlugin(ManagedPlugin plugin) async {
    if (!plugin.enabled || plugin.initialized) return;
    plugin.initialized = true;
    await _sandbox.run(
      pluginId: plugin.id,
      pluginName: plugin.name,
      hook: 'initialize',
      operation: () async {
        if (plugin.inProcess != null) {
          // Warm the plugin's storage before its own initialize() runs, so
          // it can read persisted state from the very first line of it.
          await plugin.inProcess!.storage.initialize();
          await plugin.inProcess!.initialize();
        } else if (plugin.external != null &&
            plugin.external!.hasHook('initialize')) {
          plugin.external!.callHook('initialize', const []);
        }
        return null;
      },
    );
  }

  /// Install a plugin from a GitHub (or direct .zip) URL.
  ///
  /// Downloads, extracts, validates the manifest, then loads and executes
  /// the entrypoint immediately. Returns the new [ManagedPlugin], or
  /// throws [PluginInstallException].
  ///
  /// Prefer the two-step [PluginInstaller.installFromUrl] +
  /// [registerInstalled] flow when a human is present (see
  /// `plugins_page.dart`) — that lets the UI show the plugin's declared
  /// `permissions:` before its code actually runs. This one-step version
  /// exists for programmatic callers (tests, `loadInstalled()` at startup)
  /// where there's no user to ask.
  Future<ManagedPlugin> installFromUrl(String url) async {
    final installed = await _installer.installFromUrl(url);
    return registerInstalled(installed, sourceUrl: url);
  }

  /// Registers and executes an already-downloaded plugin (the manifest has
  /// already been parsed and validated by [PluginInstaller.installFromUrl],
  /// but its Dart source has not been compiled or run yet). Splitting this
  /// out from [installFromUrl] is what lets the install UI show a
  /// permission-confirmation step before any plugin code executes.
  Future<ManagedPlugin> registerInstalled(
    InstalledPlugin installed, {
    required String sourceUrl,
  }) {
    return _registerInstalledPlugin(
      directory: installed.directory,
      sourceUrl: sourceUrl,
      manifest: installed.manifest,
    );
  }

  /// Install a plugin directly from a local directory on disk.
  ///
  /// This is useful for development, tests, and the built-in plugin store.
  Future<ManagedPlugin> installFromPath(String directory,
      {required String sourceUrl}) async {
    final manifestFile = File(p.join(directory, 'omnis_plugin.yaml'));
    if (!await manifestFile.exists()) {
      throw PluginInstallException(
        'Plugin is missing omnis_plugin.yaml manifest.',
      );
    }

    final manifestText = await manifestFile.readAsString();
    final manifest = PluginManifest.parse(manifestText, sourceUrl: sourceUrl);
    if (manifest == null) {
      throw PluginInstallException('Invalid omnis_plugin.yaml manifest.');
    }

    return _registerInstalledPlugin(
      directory: directory,
      sourceUrl: sourceUrl,
      manifest: manifest,
    );
  }

  Future<ManagedPlugin> _registerInstalledPlugin({
    required String directory,
    required String sourceUrl,
    required PluginManifest manifest,
  }) async {
    final source = await _installer.readEntrypoint(directory);
    if (source.trim().isEmpty) {
      throw PluginInstallException(
        'Plugin ${manifest.id} has an empty entrypoint.',
      );
    }

    final runtime = PluginRuntime.create(
      source,
      declaredPermissions: manifest.permissions,
    );
    final id = runtime.id.isNotEmpty && runtime.id != 'unknown'
        ? runtime.id
        : manifest.id;
    final managed = ManagedPlugin(
      id: id,
      name: runtime.name,
      description: runtime.description,
      version: runtime.version,
      author: runtime.author,
      sourceUrl: sourceUrl,
      external: runtime,
      directory: directory,
      enabled: !AppSettings.instance.isPluginDisabled(id),
    );

    _plugins.removeWhere((p) => p.id == managed.id);
    _plugins.add(managed);
    _emit();
    await initPlugin(managed);
    return managed;
  }

  /// Load all plugins that were previously installed on disk.
  Future<void> loadInstalled() async {
    final installed = await _installer.listInstalled();
    for (final info in installed) {
      await _loadPluginInfo(info);
    }
  }

  Future<void> _loadPluginInfo(InstalledPluginInfo info) async {
    final manifest = info.manifest;
    final directory = info.directory;
    try {
      final source = await _installer.readEntrypoint(directory);
      if (source.trim().isEmpty) return;
      final runtime = PluginRuntime.create(
        source,
        declaredPermissions: manifest.permissions,
      );
      if (_plugins.any((p) => p.id == runtime.id)) return;
      final managed = ManagedPlugin(
        id: runtime.id,
        name: runtime.name,
        description: runtime.description,
        version: runtime.version,
        author: runtime.author,
        sourceUrl: manifest.sourceUrl,
        external: runtime,
        directory: directory,
        enabled: !AppSettings.instance.isPluginDisabled(runtime.id),
      );
      _plugins.add(managed);
      _emit();
      // Previously this used `_plugins.last`, which is only correct as long
      // as nothing else touches the list in between.
      await initPlugin(managed);
    } catch (e) {
      debugPrint('Omnis: failed to load plugin ${manifest.name}: $e');
    }
  }

  /// Trigger the onTrackStart hook across all enabled plugins.
  ///
  /// In-process plugins receive the full [BaseTrack]; external plugins
  /// receive a JSON-serialisable Map. Every call is sandboxed.
  Future<void> onTrackStart(BaseTrack track) async {
    Map<String, dynamic>? json;
    for (final plugin in _enabled()) {
      if (plugin.inProcess != null) {
        await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'onTrackStart',
          operation: () async {
            await plugin.inProcess!.onTrackStart(track);
            return null;
          },
        );
      } else if (plugin.external!.hasHook('onTrackStart')) {
        // Serialise once, not once per external plugin.
        json ??= track.toJson();
        await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'onTrackStart',
          operation: () async {
            plugin.external!.callHook('onTrackStart', [json]);
            return null;
          },
        );
      }
    }
  }

  /// Trigger the onLibraryScan hook across all enabled plugins.
  Future<void> onLibraryScan(String file) async {
    for (final plugin in _enabled()) {
      if (plugin.inProcess != null) {
        await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'onLibraryScan',
          operation: () async {
            await plugin.inProcess!.onLibraryScan(file);
            return null;
          },
        );
      } else if (plugin.external!.hasHook('onLibraryScan')) {
        await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'onLibraryScan',
          operation: () async {
            plugin.external!.callHook('onLibraryScan', [file]);
            return null;
          },
        );
      }
    }
  }

  /// Collect UI widgets injected by plugins at [locationID].
  Future<List<dynamic>> uiSlot(String locationID) async {
    final widgets = <dynamic>[];
    for (final plugin in _enabled()) {
      if (plugin.inProcess != null) {
        final result = await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'uiSlot',
          operation: () async => plugin.inProcess!.uiSlot(locationID),
        );
        if (result != null) widgets.add(result);
      } else if (plugin.external!.hasHook('uiSlot')) {
        final result = await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'uiSlot',
          operation: () async => plugin.external!.callHook('uiSlot', [
            locationID,
          ]),
        );
        if (result != null) {
          // Stamped after the call returns, unconditionally — so a
          // guest-supplied '_pluginId' key (if any) is always clobbered
          // with the real one and can't be spoofed. Lets an interactive
          // item (a 'button'/'toggle' PluginSlotView renders) call back
          // into exactly the plugin that produced it, since the aggregate
          // dispatch here otherwise loses that association.
          if (result is Map) result['_pluginId'] = plugin.id;
          widgets.add(result);
        }
      }
    }
    return widgets;
  }

  /// Calls a named hook on exactly one external plugin by id, for a
  /// `uiSlot` item's interactive callback (a 'button'/'toggle' payload's
  /// `hook` field) — the guest-defined-function-by-name mechanism
  /// [PluginRuntime.callHook] already provides. A no-op for a bundled
  /// (in-process) plugin: those already return real [Widget]s from
  /// `uiSlot()` with their own real closures wired directly, so there is
  /// no hook-name indirection to call back into — Dart has no dynamic
  /// dispatch mechanism to invoke an arbitrary named method on a compiled
  /// [MusicPlugin] the way `callHook` does for interpreted guest code.
  ///
  /// Emits on [changes] once the call completes (success or sandboxed
  /// failure alike) so every live `PluginSlotView` re-fetches and reflects
  /// whatever the hook changed — coarse-grained, matching how `changes`
  /// already fires on install/enable/disable rather than tracking
  /// per-widget invalidation.
  Future<void> callPluginHook(
    String pluginId,
    String hook,
    List<dynamic> args,
  ) async {
    final plugin = byId(pluginId);
    final external = plugin?.external;
    if (external == null || !external.hasHook(hook)) return;
    await _sandbox.run(
      pluginId: plugin!.id,
      pluginName: plugin.name,
      hook: hook,
      operation: () async {
        external.callHook(hook, args);
        return null;
      },
    );
    _emit();
  }

  /// Calls [MusicPlugin.uiSlot] for exactly one [plugin], not the
  /// aggregate dispatch [uiSlot] does across every enabled plugin.
  ///
  /// Used for a plugin's own settings page (`locationID: 'plugin_settings'`),
  /// reached by tapping it in the Plugins list — showing exactly one
  /// plugin's UI, not everyone's, is the whole point there. Works
  /// regardless of [ManagedPlugin.enabled] so a disabled plugin's settings
  /// can still be viewed (and re-enabled from the same page); every other
  /// hook only reaches enabled plugins.
  Future<dynamic> uiSlotForPlugin(ManagedPlugin plugin, String locationID) {
    if (plugin.inProcess != null) {
      return _sandbox.run(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'uiSlot',
        operation: () async => plugin.inProcess!.uiSlot(locationID),
      );
    } else if (plugin.external != null && plugin.external!.hasHook('uiSlot')) {
      return _sandbox.run(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'uiSlot',
        operation: () async =>
            plugin.external!.callHook('uiSlot', [locationID]),
      );
    }
    return Future.value(null);
  }

  /// Disable a plugin (hot-swap: it stays loaded but stops receiving hooks).
  Future<void> disablePlugin(ManagedPlugin plugin) async {
    if (!plugin.enabled) return;
    plugin.enabled = false;
    await AppSettings.instance.setPluginEnabled(plugin.id, false);
    await _sandbox.run(
      pluginId: plugin.id,
      pluginName: plugin.name,
      hook: 'disable',
      operation: () async {
        if (plugin.inProcess != null) {
          await plugin.inProcess!.disable();
        } else if (plugin.external != null &&
            plugin.external!.hasHook('disable')) {
          plugin.external!.callHook('disable', const []);
        }
        return null;
      },
    );
    _emit();
  }

  /// Enable a plugin.
  ///
  /// A plugin that has never run is initialized; one that was merely
  /// switched off gets its [MusicPlugin.enable] hook. That hook existed on
  /// the interface but nothing ever called it — re-enabling always went
  /// through `initialize()` instead.
  Future<void> enablePlugin(ManagedPlugin plugin) async {
    if (plugin.enabled) return;
    plugin.enabled = true;
    await AppSettings.instance.setPluginEnabled(plugin.id, true);
    if (!plugin.initialized) {
      await initPlugin(plugin);
    } else {
      await _sandbox.run(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'enable',
        operation: () async {
          if (plugin.inProcess != null) {
            await plugin.inProcess!.enable();
          } else if (plugin.external != null &&
              plugin.external!.hasHook('enable')) {
            plugin.external!.callHook('enable', const []);
          }
          return null;
        },
      );
    }
    _emit();
  }

  /// Switches off every currently-enabled bundled plugin that reaches the
  /// network ([MusicPlugin.usesNetwork]) — a one-tap version of disabling
  /// each one by hand, for a user who wants nothing to phone out without
  /// auditing the plugin list themselves. External (downloaded) plugins
  /// aren't included: `usesNetwork` is only meaningful on the
  /// [MusicPlugin] interface, and an external plugin's actual network
  /// use isn't something this can verify either way.
  Future<void> disableAllNetworkPlugins() async {
    for (final plugin in List<ManagedPlugin>.from(_plugins)) {
      if (plugin.enabled && (plugin.inProcess?.usesNetwork ?? false)) {
        await disablePlugin(plugin);
      }
    }
  }

  /// Uninstall an external plugin (removes files from disk).
  Future<void> uninstallPlugin(ManagedPlugin plugin) async {
    await disablePlugin(plugin);
    _plugins.remove(plugin);
    if (plugin.directory != null && plugin.directory!.isNotEmpty) {
      try {
        await _installer.uninstall(plugin.directory!);
      } catch (e) {
        debugPrint('Omnis: failed to uninstall ${plugin.name}: $e');
      }
    }
    // An uninstalled plugin should not stay on the disabled list forever.
    await AppSettings.instance.forgetPluginState(plugin.id);
    _emit();
  }

  /// Dispose all plugins and streams.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    for (final plugin in _plugins.where((p) => p.initialized)) {
      await _sandbox.run(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'dispose',
        operation: () async {
          if (plugin.inProcess != null) {
            await plugin.inProcess!.dispose();
          } else if (plugin.external != null &&
              plugin.external!.hasHook('dispose')) {
            plugin.external!.callHook('dispose', const []);
          }
          return null;
        },
      );
    }
    await services.dispose();
    await events.dispose();
    await _changes.close();
  }

  /// Enabled plugins that actually have something to dispatch to.
  Iterable<ManagedPlugin> _enabled() => List<ManagedPlugin>.from(_plugins)
      .where((p) => p.enabled && (p.inProcess != null || p.external != null));

  void _emit() {
    if (!_changes.isClosed) {
      _changes.add(List.unmodifiable(_plugins));
    }
  }
}
