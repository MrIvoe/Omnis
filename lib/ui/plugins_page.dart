import 'package:flutter/material.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';

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

  @override
  void initState() {
    super.initState();
    _plugins = widget.pluginManager.plugins;
    widget.pluginManager.changes.listen((p) {
      if (mounted) setState(() => _plugins = p);
    });
    _health = widget.sandbox.healthRecords;
    widget.sandbox.addHealthListener((records) {
      if (mounted) setState(() => _health = records);
    });
  }

  @override
  void dispose() {
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
    try {
      final plugin = await widget.pluginManager.installFromUrl(url);
      setState(
          () => _installResult = 'Installed ${plugin.name} v${plugin.version}');
    } catch (e) {
      setState(() => _installError = 'Install failed: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
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
