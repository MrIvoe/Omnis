import 'package:flutter/material.dart';
import 'package:omnis/core/plugin_health_summary.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';

/// Item 28's "no dedicated health-center page" gap — previously every
/// failure record rendered inline on `plugins_page.dart` itself, one
/// card per *failure*; this is the real dedicated page, one card per
/// *plugin* (via [summarizeHealth]), with the raw records available on
/// demand behind "View details" rather than always taking up space.
class PluginHealthPage extends StatefulWidget {
  final PluginManager pluginManager;
  final PluginSandbox sandbox;

  const PluginHealthPage({
    super.key,
    required this.pluginManager,
    required this.sandbox,
  });

  @override
  State<PluginHealthPage> createState() => _PluginHealthPageState();
}

class _PluginHealthPageState extends State<PluginHealthPage> {
  List<PluginHealthRecord> _records = [];
  late final void Function(List<PluginHealthRecord>) _healthListener;
  final Set<String> _expandedPluginIds = {};

  @override
  void initState() {
    super.initState();
    _records = widget.sandbox.healthRecords;
    _healthListener = (records) {
      if (mounted) setState(() => _records = records);
    };
    widget.sandbox.addHealthListener(_healthListener);
  }

  @override
  void dispose() {
    widget.sandbox.removeHealthListener(_healthListener);
    super.dispose();
  }

  /// Same "look up by id, reset, clear its history" shape
  /// `plugins_page.dart`'s own per-record Reset already used before this
  /// page existed — a health record only carries the plugin's id/name,
  /// not the `ManagedPlugin` object itself, so a fresh lookup is always
  /// needed.
  Future<void> _resetPlugin(String pluginId, String pluginName) async {
    final plugin = widget.pluginManager.byId(pluginId);
    if (plugin == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:
            Text('Can\'t reset — plugin "$pluginId" is no longer installed.'),
      ));
      return;
    }
    await widget.pluginManager.resetPlugin(plugin);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Reset ${plugin.name}.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaries = summarizeHealth(_records);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plugin Health'),
        actions: [
          if (_records.isNotEmpty)
            TextButton(
              onPressed: widget.sandbox.clearHealth,
              child: const Text('Dismiss all'),
            ),
        ],
      ),
      body: summaries.isEmpty
          ? Center(
              child: Text('No plugin failures. The Core is healthy.',
                  style: theme.textTheme.bodyMedium),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: summaries.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final summary = summaries[index];
                final expanded =
                    _expandedPluginIds.contains(summary.pluginId);
                final critical =
                    summary.severity == PluginHealthSeverity.critical;
                final pluginRecords = _records
                    .where((r) => r.pluginId == summary.pluginId)
                    .toList()
                  ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

                return Card(
                  color: theme.colorScheme.errorContainer
                      .withValues(alpha: critical ? 1.0 : 0.5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ListTile(
                        leading: Icon(
                          critical ? Icons.error : Icons.report,
                          color: theme.colorScheme.error,
                        ),
                        title: Text(summary.pluginName),
                        subtitle: Text(
                          '${summary.failureCount} failure'
                          '${summary.failureCount == 1 ? '' : 's'} total · '
                          '${summary.recentFailureCount} in the last 5 '
                          'minutes\n${summary.mostRecentReason}',
                        ),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(expanded
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                              tooltip:
                                  expanded ? 'Hide details' : 'View details',
                              onPressed: () => setState(() {
                                if (expanded) {
                                  _expandedPluginIds.remove(summary.pluginId);
                                } else {
                                  _expandedPluginIds.add(summary.pluginId);
                                }
                              }),
                            ),
                            TextButton(
                              onPressed: () => _resetPlugin(
                                  summary.pluginId, summary.pluginName),
                              child: const Text('Reset'),
                            ),
                          ],
                        ),
                      ),
                      if (expanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: pluginRecords
                                .map((rec) => Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
                                      child: Text(
                                        '${rec.hook} · '
                                        '${rec.timestamp.toLocal()}\n'
                                        '${rec.message}',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
