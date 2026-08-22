import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/event_bus.dart';
import 'package:omnis/core/plugin_context.dart';
import 'package:omnis/core/plugin_heartbeat_scheduler.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:omnis/core/omnis_version.dart';
import 'package:omnis/core/plugin_manifest.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/core/plugin_sandbox_bridge.dart';
import 'package:omnis/core/plugin_sandbox_services.dart';
import 'package:omnis/core/plugin_update_scheduler.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/core/semver.dart';
import 'package:omnis/core/service_registry.dart';
import 'package:omnis/plugin_api/events.dart';
import 'package:omnis/plugin_api/service_interfaces.dart';
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

  /// This plugin's manifest-declared `provides:` capabilities (e.g.
  /// `lyrics`, `queue_builder`) — empty for a bundled plugin, which
  /// registers its own services directly rather than through this
  /// manifest-gated path. See `PluginManager._registerProvidedServices`.
  final List<String> provides;

  /// This plugin's manifest-declared `dependencies:` — other plugin ids
  /// it needs installed to function. Empty for a bundled plugin (bundled
  /// ordering uses the separate `requiresSequentialInit` mechanism, not
  /// this manifest-driven one — see item 26's doc note on
  /// [PluginManifest.dependencies]).
  final List<String> dependencies;

  /// Service adapters registered on this plugin's behalf, keyed by the
  /// interface `Type` they're registered under — see
  /// `PluginManager._registerProvidedServices`. Kept so
  /// `_unregisterProvidedServices` can unregister the *exact* instance
  /// that was registered (`ServiceRegistry.unregister` matches by
  /// identity/`==`, and these adapters don't override `==`).
  final Map<Type, Object> providedServices = {};

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
    this.provides = const [],
    this.dependencies = const [],
  });

  bool get isExternal => external != null;

  /// True for plugins compiled into the app (`lib/plugins/`).
  bool get isBundled => sourceUrl == 'bundled';
}

/// A newer version is available for an installed external plugin — the
/// result of [PluginManager.checkForUpdates].
class PluginUpdateInfo {
  final String pluginId;
  final String currentVersion;
  final String latestVersion;

  const PluginUpdateInfo({
    required this.pluginId,
    required this.currentVersion,
    required this.latestVersion,
  });
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

  /// The result of the most recent [checkForUpdates] call — either a
  /// manual "Check for updates" tap or [maybeCheckForUpdatesAutomatically]
  /// — cached here so a UI that opens *after* an automatic background
  /// check ran doesn't show a blank "no updates" state until the user
  /// taps the button again themselves. Starts empty (never checked).
  List<PluginUpdateInfo> lastKnownUpdates = const [];

  /// Capabilities handed to every in-process plugin at registration.
  PluginContext? _context;

  bool _disposed = false;

  PluginManager({PluginInstaller? installer, PluginSandbox? sandbox})
      : _installer = installer ?? PluginInstaller(),
        _sandbox = sandbox ?? PluginSandbox() {
    _wireEventForwarding();
    _sandbox.addHealthListener(_checkAutoDisable);
  }

  /// A plugin failing this many times within [_autoDisableWindow] gets
  /// disabled automatically — item 28's "no auto-disable/auto-retry on
  /// repeated failure" gap. Without this, a plugin stuck in a genuine
  /// failure loop (a bad server response it mishandles on every track
  /// change, a corrupted piece of its own persisted state) kept getting
  /// re-invoked forever: harmless to playback (the sandbox always
  /// isolates the throw), but a real, ongoing cost — every hook call
  /// wasted, every health-dashboard entry more noise burying a genuine
  /// one-off failure from some other plugin.
  ///
  /// Counts by *time window*, not true consecutive-since-last-success
  /// the way `PlaybackWatchdog`'s `_consecutiveFailures` does — deliberately
  /// different, not an oversight: `PluginHealthRecord`s only exist for
  /// failures, there is no corresponding "this hook call succeeded"
  /// event recorded anywhere to reset a true consecutive counter against.
  /// A rolling window over real failure timestamps is the honest signal
  /// actually available from `PluginSandbox.healthRecords` today.
  static const _autoDisableFailureThreshold = 5;
  static const _autoDisableWindow = Duration(minutes: 5);

  void _checkAutoDisable(List<PluginHealthRecord> records) {
    final now = DateTime.now();
    final recentFailureCounts = <String, int>{};
    for (final record in records) {
      if (now.difference(record.timestamp) > _autoDisableWindow) continue;
      recentFailureCounts[record.pluginId] =
          (recentFailureCounts[record.pluginId] ?? 0) + 1;
    }
    for (final entry in recentFailureCounts.entries) {
      if (entry.value < _autoDisableFailureThreshold) continue;
      final plugin = byId(entry.key);
      // Already disabled (including by this exact check, moments ago —
      // disablePlugin() sets `enabled = false` *before* invoking the
      // plugin's own `disable()` hook, so even a `disable()` that itself
      // throws and adds one more health record can't re-trigger this).
      if (plugin == null || !plugin.enabled) continue;
      unawaited(disablePlugin(plugin));
    }
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
  ///
  /// Runs in two batched rounds rather than one plugin at a time: most
  /// plugins have no dependency on another plugin's initialization, so
  /// round one runs every enabled plugin whose
  /// [MusicPlugin.requiresSequentialInit] isn't `true` concurrently via
  /// `Future.wait`. Round two — plugins that documented a dependency (see
  /// `Omnis-Plugins`' `bundled_plugins.dart`) — only starts once round one
  /// has fully completed, so any `ServiceRegistry` registration a round-two
  /// plugin reads is guaranteed to already be there, without round two
  /// needing to know *which* round-one plugin provided it. External
  /// (sandboxed) plugins have no equivalent flag today, so they're treated
  /// as round-one-eligible by default, same as any unflagged bundled
  /// plugin. `initPlugin` itself is unchanged — this only reorders/
  /// parallelizes the calls into it.
  Future<void> initializeAll() async {
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    final enabled =
        List<ManagedPlugin>.from(_plugins).where((p) => p.enabled).toList();
    final roundOne =
        enabled.where((p) => p.inProcess?.requiresSequentialInit != true);
    final roundTwo =
        enabled.where((p) => p.inProcess?.requiresSequentialInit == true);

    await Future.wait(roundOne.map(initPlugin));
    await Future.wait(roundTwo.map(initPlugin));

    if (stopwatch != null) {
      debugPrint('Omnis: initializeAll() initialised ${enabled.length} '
          'plugin(s) in ${stopwatch.elapsedMilliseconds}ms');
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
          // Awaited, not fire-and-forget — an external plugin backing a
          // provides: capability with the scoped `state` storage bridge
          // (itself always async) needs its own initialize() to actually
          // finish warming an in-memory cache before
          // _registerProvidedServices below wires that cache up as a
          // synchronous ServiceRegistry adapter; a discarded Future here
          // would let registration race ahead of a guest that hasn't
          // read its persisted state yet.
          final result = plugin.external!.callHook('initialize', const []);
          if (result is Future) await result;
        }
        return null;
      },
    );
    _registerProvidedServices(plugin);
  }

  /// Registers a host-authored adapter (see `plugin_sandbox_services.dart`)
  /// under `services` for each of [ManagedPlugin.provides] that this
  /// external plugin both declared in its manifest *and* actually
  /// implements the matching guest hook(s) for — a manifest claiming a
  /// capability the plugin's own code never implements is silently
  /// skipped, never registered half-broken. A fixed `switch` over the
  /// small, reviewed `providedCapabilityHooks` catalog — never a
  /// dynamically-resolved `Type`, since `ServiceRegistry` keys off the
  /// compile-time generic and a sandboxed guest cannot produce one.
  /// No-op for a bundled plugin (registers its own services directly) or
  /// a plugin with nothing in `provides`.
  void _registerProvidedServices(ManagedPlugin plugin) {
    final runtime = plugin.external;
    if (runtime == null || plugin.provides.isEmpty) return;
    for (final capability in plugin.provides) {
      if (plugin.providedServices.containsKey(_capabilityType(capability))) {
        continue; // already registered (e.g. re-enabling)
      }
      final requiredHooks = providedCapabilityHooks[capability];
      if (requiredHooks == null) continue;
      if (!requiredHooks.every(runtime.hasHook)) continue;
      switch (capability) {
        case 'lyrics':
          final adapter = SandboxedLyricsProvider(runtime);
          services.register(ILyricsProvider, adapter);
          plugin.providedServices[ILyricsProvider] = adapter;
        case 'queue_builder':
          final queries = SandboxedQueueBuilder.fetchSupportedQueries(runtime);
          final adapter = SandboxedQueueBuilder(runtime, queries);
          services.register(IQueueBuilder, adapter);
          plugin.providedServices[IQueueBuilder] = adapter;
        case 'play_history':
          final adapter = SandboxedPlayHistoryProvider(runtime);
          services.register(IPlayHistoryProvider, adapter);
          plugin.providedServices[IPlayHistoryProvider] = adapter;
        case 'artist_image':
          final adapter = SandboxedArtistImageProvider(runtime);
          services.register(IArtistImageProvider, adapter);
          plugin.providedServices[IArtistImageProvider] = adapter;
        case 'favorites':
          final adapter = SandboxedFavoritesProvider(runtime);
          services.register(IFavoritesProvider, adapter);
          plugin.providedServices[IFavoritesProvider] = adapter;
        case 'ratings':
          final adapter = SandboxedRatingsProvider(runtime);
          services.register(IRatingsProvider, adapter);
          plugin.providedServices[IRatingsProvider] = adapter;
        case 'thumbs':
          final adapter = SandboxedThumbsProvider(runtime);
          services.register(IThumbsProvider, adapter);
          plugin.providedServices[IThumbsProvider] = adapter;
        case 'online_search':
          final adapter = SandboxedOnlineSearchProvider(runtime);
          services.register(IOnlineSearchProvider, adapter);
          plugin.providedServices[IOnlineSearchProvider] = adapter;
      }
    }
  }

  /// The reverse of [_registerProvidedServices] — unregisters every
  /// adapter this plugin has registered, using the exact instances kept in
  /// [ManagedPlugin.providedServices] (`ServiceRegistry.unregister` matches
  /// by identity, and these adapters don't override `==`).
  void _unregisterProvidedServices(ManagedPlugin plugin) {
    for (final entry in plugin.providedServices.entries) {
      services.unregister(entry.key, entry.value);
    }
    plugin.providedServices.clear();
  }

  /// Maps a `provides:` catalog key to the interface `Type` it registers
  /// under — used only to check "did we already register this one" in
  /// [_registerProvidedServices]; the actual registration above is a
  /// fixed `switch`, not driven by this lookup.
  Type? _capabilityType(String capability) => switch (capability) {
        'lyrics' => ILyricsProvider,
        'queue_builder' => IQueueBuilder,
        'play_history' => IPlayHistoryProvider,
        'artist_image' => IArtistImageProvider,
        'favorites' => IFavoritesProvider,
        'ratings' => IRatingsProvider,
        'thumbs' => IThumbsProvider,
        'online_search' => IOnlineSearchProvider,
        _ => null,
      };

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

  /// Checks every installed *external* (downloaded) plugin's source URL
  /// for a newer published version than what's currently installed.
  /// Bundled plugins are never checked — they ship with the app itself,
  /// updated by an app update, not this mechanism.
  ///
  /// Best-effort per plugin: a plugin whose source URL isn't a
  /// resolvable GitHub repo (a direct `.zip` link), or whose manifest
  /// can't be fetched right now (network failure, repo gone private/
  /// renamed), is silently skipped rather than aborting the whole check
  /// — see [PluginInstaller.fetchRemoteManifest].
  Future<List<PluginUpdateInfo>> checkForUpdates() async {
    final updates = <PluginUpdateInfo>[];
    for (final plugin in List<ManagedPlugin>.from(_plugins)) {
      if (!plugin.isExternal) continue;
      final remote = await _installer.fetchRemoteManifest(plugin.sourceUrl);
      if (remote == null) continue;
      if (compareVersions(remote.version, plugin.version) > 0) {
        updates.add(PluginUpdateInfo(
          pluginId: plugin.id,
          currentVersion: plugin.version,
          latestVersion: remote.version,
        ));
      }
    }
    return updates;
  }

  /// Runs [checkForUpdates] automatically if [settings] (defaults to
  /// [AppSettings.instance]) says it's enabled and due (via
  /// [PluginUpdateScheduler.isDue]) — item 29's "no automatic/background
  /// checking" gap: previously [checkForUpdates] only ever ran from the
  /// Plugins page's manual "Check for updates" button, with no timer or
  /// interval anywhere. A no-op when disabled or not yet due. On a real
  /// check, caches the result into [lastKnownUpdates] and stamps
  /// [AppSettings.lastPluginUpdateCheckAt] regardless of whether any
  /// update was actually found — "checked and found nothing" is still a
  /// completed check, the same as [BackupService.maybeRunAutomaticBackup]
  /// stamping its own timestamp whether or not pruning had anything to
  /// do. Never throws — a failure here must never block startup, the
  /// same "denial degrades, never blocks boot" contract this app's
  /// other background tasks already follow.
  Future<void> maybeCheckForUpdatesAutomatically({
    AppSettings? settings,
    DateTime? now,
  }) async {
    final appSettings = settings ?? AppSettings.instance;
    if (!appSettings.autoUpdateCheckEnabled) return;
    final effectiveNow = now ?? DateTime.now();
    final due = PluginUpdateScheduler.isDue(
      appSettings.lastPluginUpdateCheckAt,
      Duration(days: appSettings.autoUpdateCheckIntervalDays),
      effectiveNow,
    );
    if (!due) return;

    try {
      lastKnownUpdates = await checkForUpdates();
    } catch (_) {
      // Best-effort; a failed check must never crash the app.
    } finally {
      appSettings.lastPluginUpdateCheckAt = effectiveNow;
    }
  }

  /// Item 28's "no heartbeat for a silently-hung plugin" gap — pings
  /// every enabled plugin, both kinds, through [PluginSandbox.run] with
  /// [timeout]. A plugin whose heartbeat throws, or doesn't return within
  /// [timeout], produces a [PluginHealthRecord] exactly the same way any
  /// other failing hook call would — so it automatically feeds
  /// [_checkAutoDisable] too, no changes needed there.
  ///
  /// Bundled (in-process) plugins call [MusicPlugin.heartbeat] directly —
  /// unconditionally, with no "does it declare this" gate, since compiled
  /// Dart has no manifest to introspect the way an external plugin's
  /// `hooks: [...]` list does. The default no-op body (see that method's
  /// own doc) makes this cheap enough that unconditionally calling it
  /// every [PluginHeartbeatScheduler] tick for every bundled plugin that
  /// hasn't opted in is a non-issue — the same reasoning [onTrackStart]/
  /// [onLibraryScan] already apply to every in-process call above.
  ///
  /// External (downloaded, dart_eval-sandboxed) plugins only get pinged
  /// when their manifest declares a `heartbeat` hook — silently skipped
  /// otherwise, zero behavior change for the entire existing external
  /// plugin ecosystem until an author opts in. Deliberately awaits
  /// `callHook`'s result when it's a `Future` — unlike `onTrackStart`/
  /// `_forwardEvent` above, which fire external hooks without awaiting
  /// their async body (a slow "listener" plugin shouldn't block dispatch
  /// to everyone else). A heartbeat's entire purpose is detecting whether
  /// a plugin actually finishes in time, so dropping the returned Future
  /// here would make [timeout] almost meaningless for anything but a
  /// hook that throws synchronously.
  Future<void> runHeartbeats({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    for (final plugin in _enabled()) {
      if (plugin.inProcess != null) {
        await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'heartbeat',
          timeout: timeout,
          operation: () async {
            await plugin.inProcess!.heartbeat();
            return null;
          },
        );
      } else if (plugin.external != null &&
          plugin.external!.hasHook('heartbeat')) {
        final external = plugin.external!;
        await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'heartbeat',
          timeout: timeout,
          operation: () async {
            final result = external.callHook('heartbeat', const []);
            if (result is Future) await result;
            return null;
          },
        );
      }
    }
  }

  /// Runs [runHeartbeats] automatically if [settings] (defaults to
  /// [AppSettings.instance]) says it's enabled and due (via
  /// [PluginHeartbeatScheduler.isDue]) — the background-check half of
  /// item 28's heartbeat gap. A no-op when disabled or not yet due.
  /// Stamps [AppSettings.lastPluginHeartbeatAt] regardless of whether any
  /// plugin actually failed to respond — "checked and found nothing
  /// wrong" is still a completed check, the same reasoning
  /// [maybeCheckForUpdatesAutomatically] already documents. Never throws
  /// — a failure here must never block startup, the same "denial
  /// degrades, never blocks boot" contract this app's other background
  /// tasks already follow.
  Future<void> maybeRunHeartbeatsAutomatically({
    AppSettings? settings,
    DateTime? now,
  }) async {
    final appSettings = settings ?? AppSettings.instance;
    if (!appSettings.pluginHeartbeatEnabled) return;
    final effectiveNow = now ?? DateTime.now();
    final due = PluginHeartbeatScheduler.isDue(
      appSettings.lastPluginHeartbeatAt,
      Duration(minutes: appSettings.pluginHeartbeatIntervalMinutes),
      effectiveNow,
    );
    if (!due) return;

    try {
      await runHeartbeats();
    } catch (_) {
      // Best-effort; a failed check must never crash the app.
    } finally {
      appSettings.lastPluginHeartbeatAt = effectiveNow;
    }
  }

  /// Updates an installed external plugin to whatever is currently
  /// published at its own source URL — a fresh download, not just a
  /// version-string swap, so this also picks up any code/manifest
  /// change alongside a version bump.
  ///
  /// Tears down the old instance's live registrations first (its
  /// `dispose` hook, its `ServiceRegistry` entries) without touching
  /// [AppSettings]'s persisted enabled/disabled choice for this plugin
  /// id — this is a replace, not a real disable, so a previously
  /// disabled plugin stays disabled after updating and a previously
  /// enabled one stays enabled, exactly as [disablePlugin] would *not*
  /// preserve (it explicitly persists "disabled," which an update must
  /// never do on the user's behalf).
  ///
  /// Backs up the currently-installed directory before attempting the
  /// download — item 29's "no backup-before-update/rollback" gap.
  /// `PluginInstaller.installFromUrl` resolves a plugin's directory
  /// name deterministically from its source URL, so re-installing the
  /// same plugin targets the *same* directory and unconditionally wipes
  /// it before extracting the new version; without a snapshot taken
  /// first, a download that fails partway (network drop, a corrupt zip,
  /// an invalid manifest) previously left the plugin's files gone or
  /// partially written while its [ManagedPlugin] record stayed in
  /// [_plugins] with its services already unregistered above — installed
  /// in name only, silently broken. On failure now, the snapshot is
  /// restored and the plugin re-registered from it before the error is
  /// rethrown, so a failed update leaves the previous working version
  /// running exactly as before, not a corpse.
  Future<ManagedPlugin> updatePlugin(String pluginId) async {
    final existing = byId(pluginId);
    if (existing == null) {
      throw PluginInstallException('Plugin "$pluginId" is not installed.');
    }
    if (!existing.isExternal) {
      throw PluginInstallException('Only downloaded plugins can be updated.');
    }
    final directory = existing.directory;
    final sourceUrl = existing.sourceUrl;

    if (existing.initialized) {
      await _sandbox.run(
        pluginId: existing.id,
        pluginName: existing.name,
        hook: 'dispose',
        operation: () async {
          if (existing.external != null &&
              existing.external!.hasHook('dispose')) {
            existing.external!.callHook('dispose', const []);
          }
          return null;
        },
      );
    }
    _unregisterProvidedServices(existing);

    final backupPath = directory != null
        ? await _installer.backupPluginDirectory(directory)
        : null;

    try {
      final updated = await installFromUrl(sourceUrl);
      if (backupPath != null) {
        await _installer.discardPluginBackup(backupPath);
      }
      return updated;
    } catch (e) {
      if (backupPath == null || directory == null) rethrow;
      Object? rollbackError;
      try {
        await _installer.restorePluginBackup(backupPath, directory);
        await installFromPath(directory, sourceUrl: sourceUrl);
      } catch (err) {
        rollbackError = err;
      }
      if (rollbackError != null) {
        throw PluginInstallException(
          'Update failed ($e) and the automatic rollback also failed '
          '($rollbackError) — the plugin may need to be reinstalled.',
        );
      }
      throw PluginInstallException(
        'Update failed and was rolled back to the previous working '
        'version: $e',
      );
    }
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
    final minVersion = manifest.minOmnisVersion;
    if (minVersion != null &&
        compareVersions(omnisCoreVersion, minVersion) < 0) {
      throw PluginInstallException(
        'Plugin ${manifest.id} requires Omnis $minVersion or newer '
        '(this is $omnisCoreVersion). Update Omnis before installing it.',
      );
    }
    if (manifest.dependencies.isNotEmpty) {
      final installedIds = _plugins.map((p) => p.id).toSet();
      final missing = manifest.dependencies
          .where((dep) => !installedIds.contains(dep))
          .toList();
      if (missing.isNotEmpty) {
        throw PluginInstallException(
          'Plugin ${manifest.id} depends on ${missing.join(", ")}, which '
          '${missing.length == 1 ? "isn't" : "aren't"} installed yet. '
          'Install ${missing.length == 1 ? "it" : "them"} first.',
        );
      }
    }
    final source = await _installer.readEntrypoint(directory);
    if (source.trim().isEmpty) {
      throw PluginInstallException(
        'Plugin ${manifest.id} has an empty entrypoint.',
      );
    }

    final runtime = PluginRuntime.create(
      source,
      declaredPermissions: manifest.permissions,
      getContext: () => _context,
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
      provides: manifest.provides,
      dependencies: manifest.dependencies,
    );

    _plugins.removeWhere((p) => p.id == managed.id);
    _plugins.add(managed);
    _emit();
    await initPlugin(managed);
    return managed;
  }

  /// [plugin]'s declared dependency ids that aren't currently installed
  /// — empty when every dependency is still present, or when [plugin]
  /// declares none. The install-time check in
  /// [_registerInstalledPlugin] only guarantees dependencies were
  /// present *at install time*; this closes item 26's other named gap
  /// ("no detection... of a dependency disappearing") by re-checking
  /// against the *current* installed set on demand — the Plugins page
  /// calls this for every installed plugin to show a warning if one of
  /// its dependencies has since been uninstalled.
  List<String> missingDependenciesFor(ManagedPlugin plugin) {
    if (plugin.dependencies.isEmpty) return const [];
    final installedIds = _plugins.map((p) => p.id).toSet();
    return plugin.dependencies
        .where((dep) => !installedIds.contains(dep))
        .toList();
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
        getContext: () => _context,
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
        dependencies: manifest.dependencies,
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

  /// Like [callPluginHook], but returns the hook's own result instead of
  /// discarding it — a `nav_item` payload's tap (see `plugin_slot_view.dart`)
  /// needs the hook's *return value* (another small declarative payload to
  /// show in a bottom sheet), not just to fire the call. A no-op
  /// (returns `null`) for a bundled (in-process) plugin, same as
  /// [callPluginHook] — bundled plugins have no hook-name-by-string
  /// dispatch mechanism to call back into.
  ///
  /// Deliberately does *not* call [_emit] the way [callPluginHook] does:
  /// a `nav_item` tap is a read ("what panel do I show"), not a mutation —
  /// any actual state change a panel's own nested toggle/button triggers
  /// goes back through [callPluginHook], which does emit.
  Future<dynamic> callPluginHookForResult(
    String pluginId,
    String hook,
    List<dynamic> args,
  ) async {
    final plugin = byId(pluginId);
    final external = plugin?.external;
    if (external == null || !external.hasHook(hook)) return null;
    return _sandbox.run<dynamic>(
      pluginId: plugin!.id,
      pluginName: plugin.name,
      hook: hook,
      operation: () async => external.callHook(hook, args),
    );
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

  /// Gives a plugin a fresh start after it's been misbehaving — item 28's
  /// "no per-plugin retry/reset action" gap. A plain `disable()` +
  /// `enable()` cycle (not a full re-`initialize()`, which would need
  /// tearing down and rebuilding the `ManagedPlugin` entry itself): most
  /// sandboxed failures are bad *runtime* state a well-behaved plugin's
  /// own `enable()` already resets (`ScrobblePlugin` re-reads its
  /// storage, `EqualizerPlugin` re-registers its gain contribution,
  /// etc.), not corruption in the plugin object itself. Clears that
  /// plugin's health records afterward so the dashboard reflects its
  /// fresh state, not its pre-reset failure history.
  Future<void> resetPlugin(ManagedPlugin plugin) async {
    await disablePlugin(plugin);
    await enablePlugin(plugin);
    _sandbox.clearHealthFor(plugin.id);
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
    _unregisterProvidedServices(plugin);
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
      _registerProvidedServices(plugin);
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
    _sandbox.removeHealthListener(_checkAutoDisable);
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
