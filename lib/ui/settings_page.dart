import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/plugin_slot_view.dart';
import 'package:omnis/ui/plugins_page.dart';
import 'package:omnis/ui/settings/appearance_settings_page.dart';
import 'package:omnis/ui/settings/controls_settings_page.dart';
import 'package:omnis/ui/settings/library_settings_page.dart';
import 'package:omnis/ui/settings/playback_settings_page.dart';

/// Settings home page: a category list, each entry pushing its own
/// focused page, rather than one long scroll mixing theme, playback,
/// gestures, and library settings together.
///
/// **This is also the fix for a real bug**: `PluginsPage` — install,
/// enable/disable, the health dashboard, and every plugin's own settings
/// page (`PluginSettingsPage`, reached by tapping a plugin there) — was
/// never actually navigated to from anywhere in the running app. It
/// existed, compiled, and was covered by tests, but nothing on any real
/// screen ever pushed it, so it was completely unreachable. The "Plugins"
/// entry below is the fix.
class SettingsPage extends StatelessWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;
  final PluginSandbox sandbox;
  final LayoutManager layoutManager;

  const SettingsPage({
    super.key,
    required this.engine,
    required this.pluginManager,
    required this.sandbox,
    required this.layoutManager,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CategoryCard(
            icon: Icons.palette_outlined,
            title: 'Appearance & Layout',
            subtitle: 'Theme, colors, and the Now Playing screen arrangement',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  AppearanceSettingsPage(layoutManager: layoutManager),
            )),
          ),
          _CategoryCard(
            icon: Icons.tune,
            title: 'Playback & Audio',
            subtitle: 'Gapless, crossfade, volume, speed, pitch, skip-silence',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PlaybackSettingsPage(engine: engine),
            )),
          ),
          _CategoryCard(
            icon: Icons.touch_app_outlined,
            title: 'Controls & Gestures',
            subtitle: 'Button layout, swipe/tap gestures, bottom nav auto-hide',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ControlsSettingsPage(),
            )),
          ),
          _CategoryCard(
            icon: Icons.folder_outlined,
            title: 'Library',
            subtitle: 'Scan source, folder, duplicate/short-track cleanup',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const LibrarySettingsPage(),
            )),
          ),
          _CategoryCard(
            icon: Icons.extension_outlined,
            title: 'Plugins',
            subtitle: 'Install, enable/disable, and configure every plugin',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => PluginsPage(
                pluginManager: pluginManager,
                sandbox: sandbox,
              ),
            )),
          ),
          const SizedBox(height: 8),
          // A generic extension point: any plugin can inject something
          // directly onto the Settings home page via
          // `uiSlot('settings_page')`, without needing its own dedicated
          // category card — used for something small enough not to
          // warrant a whole settings page of its own.
          PluginSlotView(
            pluginManager: pluginManager,
            locationId: 'settings_page',
            direction: Axis.vertical,
          ),
        ],
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
