import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/plugin_catalog.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/plugin_health_summary.dart';
import 'package:omnis/core/plugin_manifest.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/ui/plugin_health_page.dart';
import 'package:omnis/ui/plugin_settings_page.dart';
import 'package:omnis/ui/theme/omnis_motion.dart';

export 'package:omnis/core/plugin_catalog.dart'
    show
        CatalogPluginEntry,
        officialPluginCatalog,
        omnisPluginsRepoUrl,
        findCatalogEntryForPluginId;

/// Plugins screen.
///
/// - Official catalog: one-tap install for anything published at
///   [omnisPluginsRepoUrl], Omnis's own plugin repo.
/// - "Insert link" field: paste a GitHub URL (or direct .zip) to install a
///   plugin → downloaded, extracted, validated, executed at runtime.
/// - Installed plugin list with enable/disable/uninstall (hot-swap).
/// - Plugin Health dashboard: every sandboxed crash appears here, the
///   music never stops.
class PluginsPage extends StatefulWidget {
  final PluginManager pluginManager;
  final PluginSandbox sandbox;

  const PluginsPage({
    super.key,
    required this.pluginManager,
    required this.sandbox,
  });

  @override
  State<PluginsPage> createState() => _PluginsPageState();
}

class _PluginsPageState extends State<PluginsPage> {
  final _urlController = TextEditingController();
  final _catalogSearchController = TextEditingController();
  String _catalogQuery = '';
  bool _installing = false;
  String? _installError;
  List<ManagedPlugin> _plugins = [];
  List<PluginHealthRecord> _health = [];
  String _installResult = '';
  StreamSubscription<List<ManagedPlugin>>? _pluginsSub;
  late final void Function(List<PluginHealthRecord>) _healthListener;

  /// Updates found by the last [_checkForUpdates] run, keyed by plugin id
  /// — cleared whenever a plugin is actually updated (that entry, not the
  /// whole map) or a fresh check replaces it. `null` until a check has
  /// ever run, distinct from "checked, found nothing."
  Map<String, PluginUpdateInfo>? _availableUpdates;
  bool _checkingUpdates = false;
  final Set<String> _updatingPluginIds = {};

  /// Starts as the hardcoded fallback so the catalog card always shows
  /// *something* immediately, then replaced with the real, live
  /// `catalog.json` fetch's result once it resolves — see
  /// [_loadCatalog]. Never left empty: a failed fetch just means this
  /// stays the fallback.
  List<CatalogPluginEntry> _catalog = officialPluginCatalog;

  @override
  void initState() {
    super.initState();
    _plugins = widget.pluginManager.plugins;
    _health = widget.sandbox.healthRecords;
    // Both subscriptions used to outlive the page.
    _pluginsSub = widget.pluginManager.changes.listen((p) {
      if (mounted) setState(() => _plugins = p);
    });
    _healthListener = (records) {
      if (mounted) setState(() => _health = records);
    };
    widget.sandbox.addHealthListener(_healthListener);
    // Item 29's automatic-checking gap: a background check (see
    // MainCore.maybeCheckForUpdatesAutomatically) may already have run
    // before this page ever opened — priming from its cached result here
    // means the update banner can show up immediately instead of staying
    // blank until the user taps "Check for updates" themselves. Left
    // `null` (the pre-existing "never checked" state) when the cache is
    // still empty, so this never fakes a "checked, found nothing" state
    // that didn't really happen.
    final cached = widget.pluginManager.lastKnownUpdates;
    if (cached.isNotEmpty) {
      _availableUpdates = {for (final u in cached) u.pluginId: u};
    }
    _loadCatalog();
  }

  /// Item 30's "nothing queries GitHub to discover plugins
  /// automatically" gap — fetches the real, published `catalog.json`
  /// via `PluginInstaller.fetchCatalog()`. Silently keeps the hardcoded
  /// [officialPluginCatalog] fallback already showing on any failure
  /// (offline, GitHub unreachable) rather than surfacing an error for
  /// what is, from the user's perspective, just a browsable list that
  /// still works — never blocks or delays the rest of this page.
  Future<void> _loadCatalog() async {
    final fetched = await widget.pluginManager.installer.fetchCatalog();
    if (!mounted || fetched == null || fetched.isEmpty) return;
    setState(() => _catalog = fetched);
  }

  /// [_catalog] filtered by [_catalogQuery] against a plugin's name and
  /// description, case-insensitively — item 30's "not browsable/
  /// searchable" gap. A blank query (the common case, and always true
  /// while the catalog only has a handful of entries) returns the whole
  /// list unchanged, matching `library_search.dart`'s own "no search
  /// term means no filtering" convention rather than something bespoke
  /// here.
  List<CatalogPluginEntry> get _filteredCatalog {
    final query = _catalogQuery.trim().toLowerCase();
    if (query.isEmpty) return _catalog;
    return _catalog
        .where((entry) =>
            entry.name.toLowerCase().contains(query) ||
            entry.description.toLowerCase().contains(query))
        .toList();
  }

  @override
  void dispose() {
    _pluginsSub?.cancel();
    widget.sandbox.removeHealthListener(_healthListener);
    _urlController.dispose();
    _catalogSearchController.dispose();
    super.dispose();
  }

  /// Fills the URL field from [entry] and installs immediately — the
  /// one-tap path for anything in [_catalog], as opposed to
  /// the user having to already know and paste a plugin's URL.
  Future<void> _installFromCatalog(CatalogPluginEntry entry) async {
    _urlController.text = entry.installUrl;
    await _install();
  }

  Future<void> _install() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _installError = 'Paste a GitHub repository URL first.');
      return;
    }
    setState(() {
      _installing = true;
      _installError = null;
      _installResult = '';
    });

    InstalledPlugin? installed;
    try {
      // Step 1: download, extract, and parse the manifest. No plugin code
      // has executed yet at this point.
      installed = await widget.pluginManager.installer.installFromUrl(url);

      // Step 2: show the user what the plugin is asking for *before* its
      // code runs. Previously this page installed and executed arbitrary
      // downloaded code with zero disclosure — the manifest's
      // `permissions:` list existed and was validated, but nobody ever
      // showed it to a human before the code actually ran.
      final proceed = await _confirmPermissions(installed.manifest);
      if (!proceed) {
        await widget.pluginManager.installer.uninstall(installed.directory);
        // Each of these awaits (download, the permission dialog,
        // uninstall) is long enough for the user to have navigated away
        // and disposed this page before it resolves — every setState
        // below must check first.
        if (mounted) setState(() => _installResult = 'Install cancelled.');
        return;
      }

      // Step 3: only now compile and execute the plugin's entrypoint.
      final plugin = await widget.pluginManager.registerInstalled(
        installed,
        sourceUrl: url,
      );
      if (mounted) {
        OmnisHaptics.mediumImpact();
        setState(
            () => _installResult = 'Installed ${plugin.name} v${plugin.version}');
      }
    } catch (e) {
      // Clean up a partially-downloaded plugin directory on failure so it
      // doesn't linger on disk as an orphaned, unregistered folder.
      if (installed != null) {
        try {
          await widget.pluginManager.installer.uninstall(installed.directory);
        } catch (_) {}
      }
      if (mounted) setState(() => _installError = 'Install failed: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  /// Checks every installed external plugin's own source URL for a
  /// newer published version — see `PluginManager.checkForUpdates`'s doc
  /// comment for what "best-effort" means here (a plugin whose source
  /// doesn't support this, or that can't be reached right now, is
  /// silently skipped, not reported as an error).
  Future<void> _checkForUpdates() async {
    setState(() => _checkingUpdates = true);
    try {
      final updates = await widget.pluginManager.checkForUpdates();
      if (!mounted) return;
      setState(() {
        _availableUpdates = {for (final u in updates) u.pluginId: u};
      });
    } finally {
      if (mounted) setState(() => _checkingUpdates = false);
    }
  }

  Future<void> _updatePlugin(ManagedPlugin plugin) async {
    setState(() => _updatingPluginIds.add(plugin.id));
    try {
      final updated = await widget.pluginManager.updatePlugin(plugin.id);
      if (!mounted) return;
      setState(() {
        _availableUpdates?.remove(plugin.id);
      });
      OmnisHaptics.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Updated ${updated.name} to v${updated.version}.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Update failed: $e'),
      ));
    } finally {
      if (mounted) {
        setState(() => _updatingPluginIds.remove(plugin.id));
      }
    }
  }

  /// Shows what the plugin declares in its manifest and asks for
  /// confirmation before any of its code executes. Always shown — even
  /// with an empty permission list — so "this plugin asks for nothing" is
  /// as visible as "this plugin wants network + storage".
  Future<bool> _confirmPermissions(PluginManifest manifest) async {
    if (!mounted) return false;
    final permissions = manifest.permissions;
    final provides = manifest.provides;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Install "${manifest.name}"?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${manifest.description}\nv${manifest.version} · '
                '${manifest.author}'),
            const SizedBox(height: 16),
            Text(
              permissions.isEmpty
                  ? 'This plugin does not declare any special permissions.'
                  : 'This plugin declares the following permissions:',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (permissions.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final perm in permissions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, size: 18),
                      const SizedBox(width: 6),
                      Text(_permissionLabel(perm)),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              const Text(
                'Only install plugins from sources you trust — downloaded '
                'plugin code runs inside the app.',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ],
            // Separate from "wants access to" above — this is the reverse
            // direction: what the plugin will *supply* to the app (other
            // plugins/pages reading it through the normal service lookup),
            // not what it needs from it.
            if (provides.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'This plugin will provide:',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              for (final capability in provides)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.upload_outlined, size: 18),
                      const SizedBox(width: 6),
                      Text(_providesLabel(capability)),
                    ],
                  ),
                ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Install'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  String _permissionLabel(String perm) {
    if (perm.startsWith('network:')) {
      final host = perm.substring('network:'.length).trim();
      return host.isEmpty
          ? 'Network — can make internet requests'
          : 'Network access to $host — can make internet requests to that '
              'host only';
    }
    switch (perm) {
      case 'storage':
      case 'filesystem':
        return 'Storage — can read/write files on this device';
      case 'network':
        return 'Network — can make internet requests to any host';
      case 'library':
        return 'Library — can read your music library (titles, artists, '
            'albums — read-only)';
      case 'events':
        return 'Events — can be notified when things like favorites change';
      case 'playback':
        return 'Playback control — can play, pause, skip, and seek';
      default:
        return perm;
    }
  }

  String _providesLabel(String capability) {
    switch (capability) {
      case 'lyrics':
        return 'Lyrics — supplies lyric text for your tracks';
      case 'queue_builder':
        return 'Queue suggestions — can build a playback queue for a mood '
            'or preset';
      case 'play_history':
        return 'Play history — can supply recently/most played track data';
      case 'artist_image':
        return 'Artist photos — can supply a photo URL for an artist';
      default:
        return capability;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Plugins')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // --- Official catalog ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.storefront, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text('Omnis plugin catalog',
                          style: theme.textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Install directly from Omnis\'s own plugin repository — '
                    'no URL to find or paste.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _catalogSearchController,
                    decoration: const InputDecoration(
                      labelText: 'Search plugins',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (value) =>
                        setState(() => _catalogQuery = value),
                  ),
                  const SizedBox(height: 8),
                  if (_filteredCatalog.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('No plugins match "$_catalogQuery".',
                          style: theme.textTheme.bodySmall),
                    )
                  else
                    for (final entry in _filteredCatalog)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.extension_outlined),
                        title: Text(entry.name),
                        subtitle: Text(entry.description),
                        trailing: FilledButton.tonal(
                          onPressed: _installing
                              ? null
                              : () => _installFromCatalog(entry),
                          child: const Text('Install'),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Installer ---
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Install a plugin', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'Insert link (GitHub repo or .zip)',
                      hintText: 'https://github.com/user/plugin-repo',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.link),
                    ),
                    onSubmitted: (_) => _install(),
                  ),
                  if (_installError != null) ...[
                    const SizedBox(height: 8),
                    Text(_installError!,
                        style: TextStyle(color: theme.colorScheme.error)),
                  ],
                  if (_installResult.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(_installResult,
                        style: TextStyle(color: theme.colorScheme.primary)),
                  ],
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _installing ? null : _install,
                      icon: _installing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download),
                      label: Text(_installing ? 'Installing…' : 'Install'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // --- Installed plugins ---
          Row(
            children: [
              Text('Installed plugins', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_plugins.any((p) => p.isExternal))
                TextButton.icon(
                  onPressed: _checkingUpdates ? null : _checkForUpdates,
                  icon: _checkingUpdates
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.update, size: 18),
                  label: Text(
                      _checkingUpdates ? 'Checking…' : 'Check for updates'),
                ),
              if (_plugins.any(
                  (p) => p.enabled && (p.inProcess?.usesNetwork ?? false)))
                TextButton.icon(
                  onPressed: () => widget.pluginManager.disableAllNetworkPlugins(),
                  icon: const Icon(Icons.wifi_off, size: 18),
                  label: const Text('Disable all network plugins'),
                ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Automatic update checks'),
            subtitle: const Text(
                'Periodically check for plugin updates in the background'),
            value: AppSettings.instance.autoUpdateCheckEnabled,
            onChanged: (value) => setState(
                () => AppSettings.instance.autoUpdateCheckEnabled = value),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Heartbeat monitoring'),
            subtitle: const Text(
                'Periodically ping plugins in the background to detect '
                'ones that have silently stopped responding'),
            value: AppSettings.instance.pluginHeartbeatEnabled,
            onChanged: (value) => setState(
                () => AppSettings.instance.pluginHeartbeatEnabled = value),
          ),
          if (_availableUpdates != null && _availableUpdates!.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Everything is up to date.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 8),
          if (_plugins.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No plugins installed yet.'),
              ),
            )
          else
            ..._plugins.map((p) {
              final update = _availableUpdates?[p.id];
              final updating = _updatingPluginIds.contains(p.id);
              final missingDeps =
                  widget.pluginManager.missingDependenciesFor(p);
              return Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        p.isExternal ? Icons.extension : Icons.build_circle,
                        color: theme.colorScheme.primary,
                      ),
                      title: Text(p.name),
                      subtitle: Text(
                          '${p.description}\nv${p.version} · ${p.author}'),
                      isThreeLine: true,
                      // Tapping the plugin opens its own settings page — the
                      // RuneLite-style "click the plugin to configure it"
                      // model, so a plugin's settings never need a section
                      // added to the shared Settings page.
                      onTap: () =>
                          Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PluginSettingsPage(
                          pluginManager: widget.pluginManager,
                          plugin: p,
                        ),
                      )),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: p.enabled,
                            onChanged: (v) => v
                                ? widget.pluginManager.enablePlugin(p)
                                : widget.pluginManager.disablePlugin(p),
                          ),
                          if (p.isExternal)
                            IconButton(
                              icon: const Icon(Icons.delete),
                              tooltip: 'Uninstall',
                              onPressed: () =>
                                  widget.pluginManager.uninstallPlugin(p),
                            ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                    ),
                    if (missingDeps.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.warning_amber,
                                    size: 18, color: theme.colorScheme.error),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    missingDeps.length == 1
                                        ? 'Missing dependency: ${missingDeps.single}'
                                        : 'Missing dependencies: ${missingDeps.join(", ")}',
                                    style: TextStyle(
                                        color: theme.colorScheme.error),
                                  ),
                                ),
                              ],
                            ),
                            // Only offer a one-tap install for a missing
                            // dependency this catalog actually knows about —
                            // anything else stays warning-only, since
                            // there's no safe URL to install from.
                            for (final depId in missingDeps)
                              if (findCatalogEntryForPluginId(
                                      depId, _catalog) !=
                                  null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: TextButton(
                                    onPressed: () => _installFromCatalog(
                                      findCatalogEntryForPluginId(
                                          depId, _catalog)!,
                                    ),
                                    child: Text('Install $depId'),
                                  ),
                                ),
                          ],
                        ),
                      ),
                    if (update != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        child: Row(
                          children: [
                            Icon(Icons.new_releases_outlined,
                                size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Update available: v${update.latestVersion}',
                                style: TextStyle(
                                    color: theme.colorScheme.primary),
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed:
                                  updating ? null : () => _updatePlugin(p),
                              child: updating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    )
                                  : const Text('Update'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),

          // --- Health dashboard ---
          // Item 28's "no dedicated health-center page" gap: this used
          // to render every raw failure record inline, one card per
          // failure. Now it's just a summary — the real detail (one
          // card per plugin, expandable raw records, Reset) lives on
          // PluginHealthPage, the same "link out rather than keep
          // growing inline" shape library_page.dart already uses for
          // its own statistics/cleanup-report pages.
          Text('Plugin Health', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final summaries = summarizeHealth(_health);
            if (summaries.isEmpty) {
              return const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No plugin failures. The Core is healthy.'),
                ),
              );
            }
            final anyCritical = summaries
                .any((s) => s.severity == PluginHealthSeverity.critical);
            return Card(
              color: theme.colorScheme.errorContainer
                  .withValues(alpha: anyCritical ? 1.0 : 0.5),
              child: ListTile(
                leading: Icon(
                  anyCritical ? Icons.error : Icons.report,
                  color: theme.colorScheme.error,
                ),
                title: Text(
                  '${summaries.length} plugin'
                  '${summaries.length == 1 ? '' : 's'} with failures',
                ),
                subtitle: const Text(
                    'Tap to view details and reset affected plugins.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => PluginHealthPage(
                    pluginManager: widget.pluginManager,
                    sandbox: widget.sandbox,
                  ),
                )),
              ),
            );
          }),
        ],
      ),
    );
  }
}
