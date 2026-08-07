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
import 'package:omnis/ui/theme/declarative/theme_manager.dart';

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
/// One individually-searchable setting — not a whole category, a single
/// toggle/picker within one. [navigate] pushes that setting's *category*
/// page (there's no per-widget deep link/scroll-to, so search gets you to
/// the right page, not the exact pixel — see [_SettingsSearchResults]).
class _SearchableSetting {
  final String title;
  final String category;
  final IconData categoryIcon;
  final void Function(BuildContext context) navigate;

  const _SearchableSetting({
    required this.title,
    required this.category,
    required this.categoryIcon,
    required this.navigate,
  });
}

class SettingsPage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;
  final PluginSandbox sandbox;
  final LayoutManager layoutManager;
  final ThemeManager themeManager;

  const SettingsPage({
    super.key,
    required this.engine,
    required this.pluginManager,
    required this.sandbox,
    required this.layoutManager,
    required this.themeManager,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAppearance(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AppearanceSettingsPage(
            layoutManager: widget.layoutManager,
            themeManager: widget.themeManager),
      ));

  void _openPlayback(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaybackSettingsPage(engine: widget.engine),
      ));

  void _openControls(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ControlsSettingsPage(),
      ));

  void _openLibrary(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const LibrarySettingsPage(),
      ));

  void _openPlugins(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PluginsPage(
          pluginManager: widget.pluginManager,
          sandbox: widget.sandbox,
        ),
      ));

  /// The individual settings a search can match, each pointing back at
  /// its own category page. Kept as one flat list here rather than
  /// scattered doc-comments across five files — the tradeoff `docs/
  /// PLUGIN_GUIDE.md`'s catalog-entry reminder makes too: a manually
  /// maintained index is honest about needing upkeep as settings are
  /// added or renamed, in exchange for not needing a runtime
  /// widget-tree-introspection scheme this app has no other use for.
  List<_SearchableSetting> _buildIndex() => [
        _SearchableSetting(
            title: 'Theme mode',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Accent color',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Theme preset',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Custom themes',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Album art scale',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Now Playing background',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Dynamic color from album art',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Haptic feedback',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Reduce motion',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Reduce transparency',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Player layout',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Karaoke mode',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            navigate: _openAppearance),
        _SearchableSetting(
            title: 'Gapless playback',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            navigate: _openPlayback),
        _SearchableSetting(
            title: 'Crossfade',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            navigate: _openPlayback),
        _SearchableSetting(
            title: 'Volume',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            navigate: _openPlayback),
        _SearchableSetting(
            title: 'Playback speed',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            navigate: _openPlayback),
        _SearchableSetting(
            title: 'Pitch',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            navigate: _openPlayback),
        _SearchableSetting(
            title: 'Skip silence',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            navigate: _openPlayback),
        _SearchableSetting(
            title: 'Button layout',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            navigate: _openControls),
        _SearchableSetting(
            title: 'Gesture mode',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            navigate: _openControls),
        _SearchableSetting(
            title: 'Enable player gestures',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            navigate: _openControls),
        _SearchableSetting(
            title: 'Auto-hide bottom navigation',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            navigate: _openControls),
        _SearchableSetting(
            title: 'Library source',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            navigate: _openLibrary),
        _SearchableSetting(
            title: 'Folder for library scans',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            navigate: _openLibrary),
        _SearchableSetting(
            title: 'List density',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            navigate: _openLibrary),
        _SearchableSetting(
            title: 'Short-track threshold',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            navigate: _openLibrary),
        _SearchableSetting(
            title: 'Install a plugin',
            category: 'Plugins',
            categoryIcon: Icons.extension_outlined,
            navigate: _openPlugins),
        _SearchableSetting(
            title: 'Plugin catalog',
            category: 'Plugins',
            categoryIcon: Icons.extension_outlined,
            navigate: _openPlugins),
      ];

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final matches = query.isEmpty
        ? const <_SearchableSetting>[]
        : _buildIndex()
            .where((s) =>
                s.title.toLowerCase().contains(query) ||
                s.category.toLowerCase().contains(query))
            .toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search settings',
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 12),
          if (query.isNotEmpty) ...[
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('No settings match "$_query".',
                    style: Theme.of(context).textTheme.bodyMedium),
              )
            else
              ...matches.map((s) => Card(
                    child: ListTile(
                      leading: Icon(s.categoryIcon,
                          color: Theme.of(context).colorScheme.primary),
                      title: Text(s.title),
                      subtitle: Text(s.category),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => s.navigate(context),
                    ),
                  )),
          ] else ...[
            _CategoryCard(
              icon: Icons.palette_outlined,
              title: 'Appearance & Layout',
              subtitle:
                  'Theme, colors, and the Now Playing screen arrangement',
              onTap: () => _openAppearance(context),
            ),
            _CategoryCard(
              icon: Icons.tune,
              title: 'Playback & Audio',
              subtitle:
                  'Gapless, crossfade, volume, speed, pitch, skip-silence',
              onTap: () => _openPlayback(context),
            ),
            _CategoryCard(
              icon: Icons.touch_app_outlined,
              title: 'Controls & Gestures',
              subtitle:
                  'Button layout, swipe/tap gestures, bottom nav auto-hide',
              onTap: () => _openControls(context),
            ),
            _CategoryCard(
              icon: Icons.folder_outlined,
              title: 'Library',
              subtitle: 'Scan source, folder, duplicate/short-track cleanup',
              onTap: () => _openLibrary(context),
            ),
            _CategoryCard(
              icon: Icons.extension_outlined,
              title: 'Plugins',
              subtitle: 'Install, enable/disable, and configure every plugin',
              onTap: () => _openPlugins(context),
            ),
            const SizedBox(height: 8),
            // A generic extension point: any plugin can inject something
            // directly onto the Settings home page via
            // `uiSlot('settings_page')`, without needing its own dedicated
            // category card — used for something small enough not to
            // warrant a whole settings page of its own.
            PluginSlotView(
              pluginManager: widget.pluginManager,
              locationId: 'settings_page',
              direction: Axis.vertical,
            ),
          ],
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
