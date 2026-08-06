import 'package:flutter/material.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/ui/plugin_slot_view.dart';

/// A single plugin's own settings — reached by tapping it in the Plugins
/// list, the same way RuneLite opens a plugin's config panel from its
/// entry in the plugin list.
///
/// This is what makes "settings live in the plugin, not the Core" actually
/// true rather than aspirational: before this page existed, a plugin that
/// needed configuration (an API key, a service URL, an editable list) had
/// no home for it except a hand-written section inside
/// `settings_page.dart` — which meant Settings had to import and know
/// about that plugin. `PluginSettingsPage` calls exactly one plugin's
/// `uiSlot('plugin_settings')` (via [PluginManager.uiSlotForPlugin], not
/// the aggregate [PluginManager.uiSlot] every other location uses) and
/// renders whatever it returns. A plugin with nothing to configure simply
/// returns `null` and this page says so — the page works for every
/// plugin, present or future, with zero Core changes required to add one.
class PluginSettingsPage extends StatefulWidget {
  final PluginManager pluginManager;
  final ManagedPlugin plugin;

  const PluginSettingsPage({
    super.key,
    required this.pluginManager,
    required this.plugin,
  });

  @override
  State<PluginSettingsPage> createState() => _PluginSettingsPageState();
}

class _PluginSettingsPageState extends State<PluginSettingsPage> {
  dynamic _content;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final result = await widget.pluginManager
        .uiSlotForPlugin(widget.plugin, 'plugin_settings');
    if (mounted) {
      setState(() {
        _content = result;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plugin = widget.plugin;
    return Scaffold(
      appBar: AppBar(title: Text(plugin.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plugin.description),
                  const SizedBox(height: 4),
                  Text(
                    'v${plugin.version} · ${plugin.author}',
                    style: theme.textTheme.bodySmall,
                  ),
                  if (!plugin.enabled) ...[
                    const SizedBox(height: 8),
                    Text(
                      'This plugin is disabled — enable it from the Plugins '
                      'list to have its settings take effect.',
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_loaded)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (renderPluginSlotItem(context, _content)
              case final Widget rendered)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: rendered,
              ),
            )
          else
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('This plugin has no configurable settings.'),
              ),
            ),
        ],
      ),
    );
  }
}
