import 'package:flutter/material.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/ui/about_page.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/sandbox.dart';
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/plugin_health_page.dart';
import 'package:omnis/ui/plugin_slot_view.dart';
import 'package:omnis/ui/plugins_page.dart';
import 'package:omnis/ui/settings/accessibility_settings_page.dart';
import 'package:omnis/ui/settings/appearance_settings_page.dart';
import 'package:omnis/ui/settings/backup_settings_page.dart';
import 'package:omnis/ui/settings/controls_settings_page.dart';
import 'package:omnis/ui/settings/keyboard_settings_page.dart';
import 'package:omnis/ui/settings/library_settings_page.dart';
import 'package:omnis/ui/settings/playback_schedule_page.dart';
import 'package:omnis/ui/settings/playback_settings_page.dart';
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis/ui/theme/omnis_spacing.dart';

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
/// toggle/picker within one. [navigate] pushes that setting's category
/// page and, when [highlightField] is set, scrolls straight to that row
/// and flashes it (see `settings_highlight.dart`) — search gets you to
/// the exact control now, not just the right page.
class _SearchableSetting {
  final String title;
  final String category;
  final IconData categoryIcon;
  final void Function(BuildContext context) navigate;

  /// Matches the target page's own `highlightField` identifier for this
  /// row (e.g. `'volume'`). `null` for the handful of entries that don't
  /// point at a single fixed row — the Plugins category's search results,
  /// where the destination is a dynamic list, not a static settings page.
  final String? highlightField;

  const _SearchableSetting({
    required this.title,
    required this.category,
    required this.categoryIcon,
    required this.navigate,
    this.highlightField,
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

  void _openAppearance(BuildContext context, {String? highlightField}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AppearanceSettingsPage(
            layoutManager: widget.layoutManager,
            themeManager: widget.themeManager,
            highlightField: highlightField),
      ));

  void _openPlayback(BuildContext context, {String? highlightField}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PlaybackSettingsPage(
            engine: widget.engine, highlightField: highlightField),
      ));

  void _openControls(BuildContext context, {String? highlightField}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ControlsSettingsPage(highlightField: highlightField),
      ));

  void _openAccessibility(BuildContext context, {String? highlightField}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) =>
            AccessibilitySettingsPage(highlightField: highlightField),
      ));

  void _openLibrary(BuildContext context, {String? highlightField}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LibrarySettingsPage(highlightField: highlightField),
      ));

  void _openKeyboard(BuildContext context, {String? highlightField}) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => KeyboardSettingsPage(highlightField: highlightField),
      ));

  void _openPlugins(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PluginsPage(
          pluginManager: widget.pluginManager,
          sandbox: widget.sandbox,
        ),
      ));

  void _openBackup(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const BackupSettingsPage(),
      ));

  void _openPlaybackSchedule(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const PlaybackSchedulePage(),
      ));

  void _openAbout(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const AboutPage(),
      ));

  void _openPluginHealth(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PluginHealthPage(
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
            highlightField: 'theme_mode',
            navigate: (c) => _openAppearance(c, highlightField: 'theme_mode')),
        _SearchableSetting(
            title: 'Accent color',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'accent_color',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'accent_color')),
        _SearchableSetting(
            title: 'Theme preset',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'theme_preset',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'theme_preset')),
        _SearchableSetting(
            title: 'Custom themes',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'custom_themes',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'custom_themes')),
        _SearchableSetting(
            title: 'Album art scale',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'album_art_scale',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'album_art_scale')),
        _SearchableSetting(
            title: 'Now Playing background',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'now_playing_background',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'now_playing_background')),
        _SearchableSetting(
            title: 'Dynamic color from album art',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'dynamic_color',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'dynamic_color')),
        _SearchableSetting(
            title: 'High contrast',
            category: 'Accessibility',
            categoryIcon: Icons.accessibility_new_outlined,
            highlightField: 'high_contrast',
            navigate: (c) =>
                _openAccessibility(c, highlightField: 'high_contrast')),
        _SearchableSetting(
            title: 'Text size',
            category: 'Accessibility',
            categoryIcon: Icons.accessibility_new_outlined,
            highlightField: 'text_size',
            navigate: (c) =>
                _openAccessibility(c, highlightField: 'text_size')),
        _SearchableSetting(
            title: 'Haptic feedback',
            category: 'Accessibility',
            categoryIcon: Icons.accessibility_new_outlined,
            highlightField: 'haptic_feedback',
            navigate: (c) =>
                _openAccessibility(c, highlightField: 'haptic_feedback')),
        _SearchableSetting(
            title: 'Reduce motion',
            category: 'Accessibility',
            categoryIcon: Icons.accessibility_new_outlined,
            highlightField: 'reduce_motion',
            navigate: (c) =>
                _openAccessibility(c, highlightField: 'reduce_motion')),
        _SearchableSetting(
            title: 'Reduce transparency',
            category: 'Accessibility',
            categoryIcon: Icons.accessibility_new_outlined,
            highlightField: 'reduce_transparency',
            navigate: (c) =>
                _openAccessibility(c, highlightField: 'reduce_transparency')),
        _SearchableSetting(
            title: 'Player layout',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'player_layout',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'player_layout')),
        _SearchableSetting(
            title: 'Karaoke mode',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'karaoke_mode',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'karaoke_mode')),
        _SearchableSetting(
            title: 'Lyrics text size',
            category: 'Appearance & Layout',
            categoryIcon: Icons.palette_outlined,
            highlightField: 'lyrics_text_size',
            navigate: (c) =>
                _openAppearance(c, highlightField: 'lyrics_text_size')),
        _SearchableSetting(
            title: 'Gapless playback',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'gapless',
            navigate: (c) => _openPlayback(c, highlightField: 'gapless')),
        _SearchableSetting(
            title: 'Crossfade',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'crossfade',
            navigate: (c) => _openPlayback(c, highlightField: 'crossfade')),
        _SearchableSetting(
            title: 'Queue continuation',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'queue_continuation',
            navigate: (c) =>
                _openPlayback(c, highlightField: 'queue_continuation')),
        _SearchableSetting(
            title: 'Queue rules',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'queue_rules',
            navigate: (c) => _openPlayback(c, highlightField: 'queue_rules')),
        _SearchableSetting(
            title: 'Skip forward/backward',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'seek_increment',
            navigate: (c) =>
                _openPlayback(c, highlightField: 'seek_increment')),
        _SearchableSetting(
            title: 'Volume',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'volume',
            navigate: (c) => _openPlayback(c, highlightField: 'volume')),
        _SearchableSetting(
            title: 'Playback speed',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'playback_speed',
            navigate: (c) =>
                _openPlayback(c, highlightField: 'playback_speed')),
        _SearchableSetting(
            title: 'Pitch',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'pitch',
            navigate: (c) => _openPlayback(c, highlightField: 'pitch')),
        _SearchableSetting(
            title: 'Skip silence',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'skip_silence',
            navigate: (c) => _openPlayback(c, highlightField: 'skip_silence')),
        _SearchableSetting(
            title: 'Output devices',
            category: 'Playback & Audio',
            categoryIcon: Icons.tune,
            highlightField: 'output_devices',
            navigate: (c) =>
                _openPlayback(c, highlightField: 'output_devices')),
        _SearchableSetting(
            title: 'Enable keyboard shortcuts',
            category: 'Keyboard',
            categoryIcon: Icons.keyboard_outlined,
            highlightField: 'keyboard_shortcuts_enabled',
            navigate: (c) =>
                _openKeyboard(c, highlightField: 'keyboard_shortcuts_enabled')),
        _SearchableSetting(
            title: 'Button layout',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            highlightField: 'button_layout',
            navigate: (c) => _openControls(c, highlightField: 'button_layout')),
        _SearchableSetting(
            title: 'Gesture mode',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            highlightField: 'gesture_mode',
            navigate: (c) => _openControls(c, highlightField: 'gesture_mode')),
        _SearchableSetting(
            title: 'Enable player gestures',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            highlightField: 'enable_gestures',
            navigate: (c) =>
                _openControls(c, highlightField: 'enable_gestures')),
        _SearchableSetting(
            title: 'Auto-hide bottom navigation',
            category: 'Controls & Gestures',
            categoryIcon: Icons.touch_app_outlined,
            highlightField: 'auto_hide_nav',
            navigate: (c) => _openControls(c, highlightField: 'auto_hide_nav')),
        _SearchableSetting(
            title: 'Library source',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            highlightField: 'library_source',
            navigate: (c) => _openLibrary(c, highlightField: 'library_source')),
        _SearchableSetting(
            title: 'Folder for library scans',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            highlightField: 'library_folder',
            navigate: (c) => _openLibrary(c, highlightField: 'library_folder')),
        _SearchableSetting(
            title: 'Watch folder for changes',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            highlightField: 'library_watcher',
            navigate: (c) =>
                _openLibrary(c, highlightField: 'library_watcher')),
        _SearchableSetting(
            title: 'List density',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            highlightField: 'list_density',
            navigate: (c) => _openLibrary(c, highlightField: 'list_density')),
        _SearchableSetting(
            title: 'Group Artists view by album artist',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            highlightField: 'group_by_album_artist',
            navigate: (c) =>
                _openLibrary(c, highlightField: 'group_by_album_artist')),
        _SearchableSetting(
            title: 'Short-track threshold',
            category: 'Library',
            categoryIcon: Icons.folder_outlined,
            highlightField: 'short_track_threshold',
            navigate: (c) =>
                _openLibrary(c, highlightField: 'short_track_threshold')),
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
        _SearchableSetting(
            title: 'Backup Omnis',
            category: 'Backup',
            categoryIcon: Icons.backup_outlined,
            navigate: _openBackup),
        _SearchableSetting(
            title: 'Restore Omnis',
            category: 'Backup',
            categoryIcon: Icons.backup_outlined,
            navigate: _openBackup),
        _SearchableSetting(
            title: 'Scheduled Playback',
            category: 'Scheduled Playback',
            categoryIcon: Icons.schedule_outlined,
            navigate: _openPlaybackSchedule),
        _SearchableSetting(
            title: 'Plugin health',
            category: 'Plugins',
            categoryIcon: Icons.extension_outlined,
            navigate: _openPluginHealth),
        _SearchableSetting(
            title: 'About',
            category: 'About',
            categoryIcon: Icons.info_outline,
            navigate: _openAbout),
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
        padding: OmnisSpacing.paddingMd,
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
                      tooltip: 'Clear search',
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          OmnisSpacing.gapMd,
          if (query.isNotEmpty) ...[
            if (matches.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: OmnisSpacing.md),
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
              subtitle: 'Theme, colors, and the Now Playing screen arrangement',
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
              icon: Icons.accessibility_new_outlined,
              title: 'Accessibility',
              subtitle: 'Reduce motion, reduce transparency, haptic feedback',
              onTap: () => _openAccessibility(context),
            ),
            _CategoryCard(
              icon: Icons.keyboard_outlined,
              title: 'Keyboard',
              subtitle: 'Global playback shortcuts — play/pause, seek, '
                  'volume, next/previous',
              onTap: () => _openKeyboard(context),
            ),
            _CategoryCard(
              icon: Icons.extension_outlined,
              title: 'Plugins',
              subtitle: 'Install, enable/disable, and configure every plugin',
              onTap: () => _openPlugins(context),
            ),
            _CategoryCard(
              icon: Icons.backup_outlined,
              title: 'Backup',
              subtitle: 'Save or restore your library, playlists, and history',
              onTap: () => _openBackup(context),
            ),
            _CategoryCard(
              icon: Icons.schedule_outlined,
              title: 'Scheduled Playback',
              subtitle: 'Start playback automatically at a set time, on '
                  'chosen days',
              onTap: () => _openPlaybackSchedule(context),
            ),
            _CategoryCard(
              icon: Icons.info_outline,
              title: 'About',
              subtitle: 'Version, updates, GitHub, Discord, and support',
              onTap: () => _openAbout(context),
            ),
            OmnisSpacing.gapSm,
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
