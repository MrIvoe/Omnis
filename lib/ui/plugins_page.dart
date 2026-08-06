import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/plugin_installer.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/plugin_manifest.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/ui/plugin_settings_page.dart';

/// Plugins screen.
///
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
  bool _installing = false;
  String? _installError;
  List<ManagedPlugin> _plugins = [];
  List<PluginHealthRecord> _health = [];
  String _installResult = '';
  StreamSubscription<List<ManagedPlugin>>? _pluginsSub;
  late final void Function(List<PluginHealthRecord>) _healthListener;

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
  }

  @override
  void dispose() {
    _pluginsSub?.cancel();
    widget.sandbox.removeHealthListener(_healthListener);
    _urlController.dispose();
    super.dispose();
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

  /// Shows what the plugin declares in its manifest and asks for
  /// confirmation before any of its code executes. Always shown — even
  /// with an empty permission list — so "this plugin asks for nothing" is
  /// as visible as "this plugin wants network + storage".
  Future<bool> _confirmPermissions(PluginManifest manifest) async {
    if (!mounted) return false;
    final permissions = manifest.permissions;
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
    switch (perm) {
      case 'storage':
      case 'filesystem':
        return 'Storage — can read/write files on this device';
      case 'network':
        return 'Network — can make internet requests';
      default:
        return perm;
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
          Text('Installed plugins', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_plugins.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No plugins installed yet.'),
              ),
            )
          else
            ..._plugins.map((p) => Card(
                  child: ListTile(
                    leading: Icon(
                      p.isExternal ? Icons.extension : Icons.build_circle,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(p.name),
                    subtitle:
                        Text('${p.description}\nv${p.version} · ${p.author}'),
                    isThreeLine: true,
                    // Tapping the plugin opens its own settings page — the
                    // RuneLite-style "click the plugin to configure it"
                    // model, so a plugin's settings never need a section
                    // added to the shared Settings page.
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
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
                )),
          const SizedBox(height: 24),

          // --- Health dashboard ---
          Row(
            children: [
              Text('Plugin Health', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_health.isNotEmpty)
                TextButton(
                  onPressed: widget.sandbox.clearHealth,
                  child: const Text('Dismiss all'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_health.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No plugin failures. The Core is healthy.'),
              ),
            )
          else
            ..._health.map((rec) => Card(
                  color:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.5),
                  child: ListTile(
                    leading: Icon(Icons.report, color: theme.colorScheme.error),
                    title: Text('${rec.pluginName} · ${rec.hook}'),
                    subtitle: Text(
                        '${rec.reason}\n${rec.message}\n${rec.timestamp.toLocal()}'),
                    isThreeLine: true,
                  ),
                )),
        ],
      ),
    );
  }
}
