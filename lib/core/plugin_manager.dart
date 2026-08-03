import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:omnis/core/plugin_manifest.dart';
import 'package:omnis/core/plugin_runtime.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:path/path.dart' as p;

/// A plugin that is loaded at runtime.
///
/// Two kinds of plugins are unified here:
///  - [inProcess]: a [MusicPlugin] compiled into the app (e.g. bundled
///    plugins like ReplayGain or the visualizer).
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
    this.directory,
  });

  bool get isExternal => external != null;
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

  PluginManager({PluginInstaller? installer, PluginSandbox? sandbox})
      : _installer = installer ?? PluginInstaller(),
        _sandbox = sandbox ?? PluginSandbox();

  /// The sandbox used for all plugin calls.
  PluginSandbox get sandbox => _sandbox;

  /// The installer used to fetch plugins from GitHub.
  PluginInstaller get installer => _installer;

  /// Live list of managed plugins.
  List<ManagedPlugin> get plugins => List.unmodifiable(_plugins);

  /// Stream of plugin list changes (register/install/uninstall).
  Stream<List<ManagedPlugin>> get changes => _changes.stream;

  /// Register an in-process [MusicPlugin] (bundled plugin).
  void register(MusicPlugin plugin) {
    if (_plugins.any((p) => p.id == plugin.id)) return;
    final managed = ManagedPlugin(
      id: plugin.id,
      name: plugin.name,
      description: plugin.description,
      version: plugin.version,
      author: plugin.author,
      sourceUrl: 'bundled',
      inProcess: plugin,
    );
    _plugins.add(managed);
    _emit();
  }

  /// Initialize all enabled plugins (in-process and external).
  ///
  /// Each plugin is initialised inside the sandbox: a failing plugin does
  /// not block the rest.
  Future<void> initializeAll() async {
    for (final plugin in _plugins.where((p) => p.enabled)) {
      await initPlugin(plugin);
    }
  }

  /// Initialize a single plugin.
  Future<void> initPlugin(ManagedPlugin plugin) async {
    if (plugin.enabled) {
      await _sandbox.run(
        pluginId: plugin.id,
        pluginName: plugin.name,
        hook: 'initialize',
        operation: () async {
          if (plugin.inProcess != null) {
            await plugin.inProcess!.initialize();
          } else if (plugin.external != null) {
            // external plugins expose optional lifecycle hooks
            plugin.external!.callHook('initialize', const []);
          }
          return null;
        },
      );
    }
  }

  /// Install a plugin from a GitHub (or direct .zip) URL.
  ///
  /// Downloads, extracts, validates the manifest, then loads and executes
  /// the entrypoint. Returns the new [ManagedPlugin], or throws
  /// [PluginInstallException].
  Future<ManagedPlugin> installFromUrl(String url) async {
    final installed = await _installer.installFromUrl(url);
    return _registerInstalledPlugin(
      directory: installed.directory,
      sourceUrl: url,
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

    final runtime = PluginRuntime.create(source);
    final managed = ManagedPlugin(
      id: runtime.id.isNotEmpty && runtime.id != 'unknown'
          ? runtime.id
          : manifest.id,
      name: runtime.name,
      description: runtime.description,
      version: runtime.version,
      author: runtime.author,
      sourceUrl: sourceUrl,
      external: runtime,
      directory: directory,
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
    final source = await _installer.readEntrypoint(directory);
    if (source.trim().isEmpty) return;
    try {
      final runtime = PluginRuntime.create(source);
      if (_plugins.any((p) => p.id == runtime.id)) return;
      _plugins.add(ManagedPlugin(
        id: runtime.id,
        name: runtime.name,
        description: runtime.description,
        version: runtime.version,
        author: runtime.author,
        sourceUrl: manifest.sourceUrl,
        external: runtime,
        directory: directory,
      ));
      _emit();
      await initPlugin(_plugins.last);
    } catch (e) {
      debugPrint('Omnis: failed to load plugin ${manifest.name}: $e');
    }
  }

  /// Trigger the onTrackStart hook across all enabled plugins.
  ///
  /// In-process plugins receive the full [BaseTrack]; external plugins
  /// receive a JSON-serialisable Map. Every call is sandboxed.
  Future<void> onTrackStart(BaseTrack track) async {
    for (final plugin in _plugins.where((p) => p.enabled)) {
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
      } else if (plugin.external != null &&
          plugin.external!.hasHook('onTrackStart')) {
        await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'onTrackStart',
          operation: () async {
            plugin.external!.callHook('onTrackStart', [track.toJson()]);
            return null;
          },
        );
      }
    }
  }

  /// Trigger the onLibraryScan hook across all enabled plugins.
  Future<void> onLibraryScan(String file) async {
    for (final plugin in _plugins.where((p) => p.enabled)) {
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
      } else if (plugin.external != null &&
          plugin.external!.hasHook('onLibraryScan')) {
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
    for (final plugin in _plugins.where((p) => p.enabled)) {
      if (plugin.inProcess != null) {
        final result = await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'uiSlot',
          operation: () async => plugin.inProcess!.uiSlot(locationID),
        );
        if (result != null) widgets.add(result);
      } else if (plugin.external != null &&
          plugin.external!.hasHook('uiSlot')) {
        final result = await _sandbox.run(
          pluginId: plugin.id,
          pluginName: plugin.name,
          hook: 'uiSlot',
          operation: () async => plugin.external!.callHook('uiSlot', [
            locationID,
          ]),
        );
        if (result != null) widgets.add(result);
      }
    }
    return widgets;
  }

  /// Disable a plugin (hot-swap: it stays loaded but stops receiving hooks).
  Future<void> disablePlugin(ManagedPlugin plugin) async {
    if (!plugin.enabled) return;
    plugin.enabled = false;
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
  Future<void> enablePlugin(ManagedPlugin plugin) async {
    if (plugin.enabled) return;
    plugin.enabled = true;
    await initPlugin(plugin);
    _emit();
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
    _emit();
  }

  /// Dispose all plugins and streams.
  Future<void> dispose() async {
    for (final plugin in _plugins.where((p) => p.enabled)) {
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
    await _changes.close();
  }

  void _emit() {
    if (!_changes.isClosed) {
      _changes.add(List.unmodifiable(_plugins));
    }
  }
}
