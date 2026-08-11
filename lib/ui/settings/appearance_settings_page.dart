import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/player_layouts/declarative/declarative_layout.dart';
import 'package:omnis/ui/player_layouts/declarative/layout_installer.dart'
    show LayoutInstallException;
import 'package:omnis/ui/player_layouts/layout_manager.dart';
import 'package:omnis/ui/player_layouts/player_layout.dart';
import 'package:omnis/ui/settings/settings_widgets.dart';
import 'package:omnis/ui/theme/declarative/theme_installer.dart'
    show ThemeInstallException;
import 'package:omnis/ui/theme/declarative/theme_manager.dart';
import 'package:omnis/ui/theme/declarative/theme_manifest.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';

class _ColorPickerDialog extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerDialog({required this.initialColor});

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.deepPurple,
      Colors.blue,
      Colors.teal,
      Colors.green,
      Colors.orange,
      Colors.pink,
    ];

    return AlertDialog(
      title: const Text('Choose accent color'),
      content: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: colors.map((color) {
          final selected = color == _selectedColor;
          return GestureDetector(
            onTap: () => setState(() => _selectedColor = color),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: selected ? Colors.white : Colors.transparent,
                    width: 2),
              ),
            ),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _selectedColor),
            child: const Text('Apply')),
      ],
    );
  }
}

/// "Import a layout" card: paste a direct link to a layout's YAML/JSON
/// text (a GitHub "raw" file URL or a gist raw URL — not a repo page,
/// there's no archive to extract), or pick a local file. Mirrors the
/// Plugins tab's install flow, but simpler: a layout is one data file, so
/// there's no permission-confirmation step the way a downloaded plugin
/// needs — see `LayoutManifest`'s doc comment for why that's safe.
class _LayoutImportCard extends StatefulWidget {
  final LayoutManager layoutManager;

  const _LayoutImportCard({required this.layoutManager});

  @override
  State<_LayoutImportCard> createState() => _LayoutImportCardState();
}

class _LayoutImportCardState extends State<_LayoutImportCard> {
  final _urlController = TextEditingController();
  bool _installing = false;
  String? _error;
  String? _result;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _installFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Paste a link to a layout file first.');
      return;
    }
    await _runInstall(() => widget.layoutManager.installFromUrl(url));
  }

  Future<void> _installFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml', 'json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await _runInstall(() => widget.layoutManager.installFromFile(path));
  }

  Future<void> _runInstall(
    Future<DeclarativeLayout> Function() install,
  ) async {
    setState(() {
      _installing = true;
      _error = null;
      _result = null;
    });
    try {
      final layout = await install();
      if (!mounted) return;
      setState(() => _result = 'Imported "${layout.name}".');
      _urlController.clear();
    } on LayoutInstallException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import a layout', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Link to a layout file',
                hintText: 'A raw .yaml/.json URL — not a repo page',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _installFromUrl(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 8),
              Text(_result!, style: TextStyle(color: theme.colorScheme.primary)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _installing ? null : _installFromFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Pick file'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _installing ? null : _installFromUrl,
                  icon: _installing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(_installing ? 'Importing…' : 'Import'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// "Import a theme" card: paste a direct link to a theme's YAML/JSON
/// text, or pick a local file. Exactly the `_LayoutImportCard` pattern,
/// applied to [ThemeManager] instead of `LayoutManager` — same reasoning
/// for why no permission-confirmation step is needed (see
/// `ThemeManifest`'s doc comment).
class _ThemeImportCard extends StatefulWidget {
  final ThemeManager themeManager;

  const _ThemeImportCard({required this.themeManager});

  @override
  State<_ThemeImportCard> createState() => _ThemeImportCardState();
}

class _ThemeImportCardState extends State<_ThemeImportCard> {
  final _urlController = TextEditingController();
  bool _installing = false;
  String? _error;
  String? _result;

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _installFromUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Paste a link to a theme file first.');
      return;
    }
    await _runInstall(() => widget.themeManager.installFromUrl(url));
  }

  Future<void> _installFromFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['yaml', 'yml', 'json'],
    );
    final path = result?.files.single.path;
    if (path == null) return;
    await _runInstall(() => widget.themeManager.installFromFile(path));
  }

  Future<void> _runInstall(
    Future<ThemeManifest> Function() install,
  ) async {
    setState(() {
      _installing = true;
      _error = null;
      _result = null;
    });
    try {
      final theme = await install();
      if (!mounted) return;
      setState(() => _result = 'Imported "${theme.name}".');
      _urlController.clear();
    } on ThemeInstallException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Import failed: $e');
    } finally {
      if (mounted) setState(() => _installing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Import a theme', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Link to a theme file',
                hintText: 'A raw .yaml/.json URL — not a repo page',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              onSubmitted: (_) => _installFromUrl(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (_result != null) ...[
              const SizedBox(height: 8),
              Text(_result!, style: TextStyle(color: theme.colorScheme.primary)),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _installing ? null : _installFromFile,
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Pick file'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _installing ? null : _installFromUrl,
                  icon: _installing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download),
                  label: Text(_installing ? 'Importing…' : 'Import'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Appearance & Layout: theme, colors, and the arrangement of the Now
/// Playing screen — everything about how the app *looks*, as opposed to
/// how it plays audio (Playback & Audio) or how you interact with it
/// (Controls & Gestures).
class AppearanceSettingsPage extends StatefulWidget {
  final LayoutManager layoutManager;
  final ThemeManager themeManager;

  /// Set when opened from `SettingsPage`'s search with a specific row in
  /// mind — that row scrolls into view and flashes once this page mounts.
  final String? highlightField;

  const AppearanceSettingsPage({
    super.key,
    required this.layoutManager,
    required this.themeManager,
    this.highlightField,
  });

  @override
  State<AppearanceSettingsPage> createState() =>
      _AppearanceSettingsPageState();
}

class _AppearanceSettingsPageState extends State<AppearanceSettingsPage> {
  late AppSettings _settings;
  List<PlayerLayout> _layouts = [];
  StreamSubscription<List<PlayerLayout>>? _layoutsSub;
  List<ThemeManifest> _themes = [];
  StreamSubscription<List<ThemeManifest>>? _themesSub;

  final Map<String, GlobalKey<SettingsHighlightState>> _keys = {
    for (final field in [
      'theme_mode',
      'accent_color',
      'theme_preset',
      'custom_themes',
      'album_art_scale',
      'now_playing_background',
      'dynamic_color',
      'haptic_feedback',
      'reduce_motion',
      'reduce_transparency',
      'player_layout',
      'karaoke_mode',
      'lyrics_text_size',
    ])
      field: GlobalKey<SettingsHighlightState>(),
  };

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    _layouts = widget.layoutManager.allLayouts;
    _layoutsSub = widget.layoutManager.changes.listen((layouts) {
      if (mounted) setState(() => _layouts = layouts);
    });
    _themes = widget.themeManager.allThemes;
    _themesSub = widget.themeManager.changes.listen((themes) {
      if (mounted) setState(() => _themes = themes);
    });
    scrollToAndFlashSetting(_keys[widget.highlightField]);
  }

  @override
  void dispose() {
    _layoutsSub?.cancel();
    _themesSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Appearance & Layout')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Theme', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SettingsHighlight(
            key: _keys['theme_mode'],
            child: ListTile(
              title: const Text('Theme'),
              subtitle: const Text('Switch between light, dark, or system'),
              trailing: DropdownButton<ThemeMode>(
                value: settings.themeMode,
                items: const [
                  DropdownMenuItem(
                      value: ThemeMode.system, child: Text('System')),
                  DropdownMenuItem(
                      value: ThemeMode.light, child: Text('Light')),
                  DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => settings.themeMode = value);
                },
              ),
            ),
          ),
          SettingsHighlight(
            key: _keys['accent_color'],
            child: ListTile(
              title: const Text('Accent color'),
              subtitle: const Text('Set the main app accent color'),
              trailing: ColorIndicator(color: settings.accentColor),
              onTap: () async {
                final color = await showDialog<Color>(
                  context: context,
                  builder: (context) =>
                      _ColorPickerDialog(initialColor: settings.accentColor),
                );
                if (color != null && mounted) {
                  setState(() => settings.accentColor = color);
                }
              },
            ),
          ),
          SettingsHighlight(
            key: _keys['theme_preset'],
            child: ListTile(
              title: const Text('Theme preset'),
              subtitle:
                  const Text('Choose a more polished aesthetic palette'),
              trailing: DropdownButton<AppThemePreset>(
                value: settings.themePreset,
                items: const [
                  DropdownMenuItem(
                      value: AppThemePreset.classic, child: Text('Classic')),
                  DropdownMenuItem(
                      value: AppThemePreset.midnight,
                      child: Text('Midnight')),
                  DropdownMenuItem(
                      value: AppThemePreset.aurora, child: Text('Aurora')),
                  DropdownMenuItem(
                      value: AppThemePreset.sunset, child: Text('Sunset')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => settings.themePreset = value);
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Custom themes', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'An imported theme replaces the accent color and theme preset '
            'above with its own full color/font/shape scheme. Select '
            '"Built-in preset" to go back to those.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SettingsHighlight(
            key: _keys['custom_themes'],
            child: Card(
              child: Column(
                children: [
                  RadioListTile<String?>(
                    value: null,
                    groupValue: settings.customThemeId,
                    onChanged: (_) =>
                        setState(() => settings.customThemeId = null),
                    title: const Text('Built-in preset'),
                    subtitle: const Text('Uses the theme preset and accent '
                        'color set above'),
                  ),
                  for (final custom in _themes)
                    RadioListTile<String?>(
                      value: custom.id,
                      groupValue: settings.customThemeId,
                      onChanged: (_) =>
                          setState(() => settings.customThemeId = custom.id),
                      title: Text(custom.name),
                      subtitle: Text('${custom.description}\nImported · '
                          '${custom.author}'),
                      isThreeLine: true,
                      secondary: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: 'Remove imported theme',
                        onPressed: () async {
                          if (settings.customThemeId == custom.id) {
                            settings.customThemeId = null;
                          }
                          await widget.themeManager.uninstall(custom);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _ThemeImportCard(themeManager: widget.themeManager),
          const SizedBox(height: 8),
          SettingsHighlight(
            key: _keys['album_art_scale'],
            child: SliderListTile(
              title: 'Album art scale',
              value: settings.albumArtScale,
              min: 0.7,
              max: 1.4,
              divisions: 14,
              label: settings.albumArtScale.toStringAsFixed(2),
              onChanged: (value) =>
                  setState(() => settings.albumArtScale = value),
            ),
          ),
          SwitchListTile(
            title: const Text('Show album art'),
            value: settings.showAlbumArt,
            onChanged: (value) => setState(() => settings.showAlbumArt = value),
          ),
          SwitchListTile(
            title: const Text('Lyrics view'),
            subtitle: const Text('Show lyric mode in the player screen'),
            value: settings.showLyrics,
            onChanged: (value) => setState(() => settings.showLyrics = value),
          ),
          SettingsHighlight(
            key: _keys['karaoke_mode'],
            child: SwitchListTile(
              title: const Text('Karaoke mode'),
              subtitle: const Text('Highlight the current lyric line'),
              value: settings.karaokeMode,
              onChanged: (value) =>
                  setState(() => settings.karaokeMode = value),
            ),
          ),
          SettingsHighlight(
            key: _keys['lyrics_text_size'],
            child: ListTile(
              title: const Text('Lyrics text size'),
              subtitle: const Text(
                  'How large lyrics render in the player screen'),
              trailing: SegmentedButton<LyricsTextSize>(
                segments: const [
                  ButtonSegment(
                      value: LyricsTextSize.small, label: Text('S')),
                  ButtonSegment(
                      value: LyricsTextSize.medium, label: Text('M')),
                  ButtonSegment(
                      value: LyricsTextSize.large, label: Text('L')),
                  ButtonSegment(
                      value: LyricsTextSize.extraLarge, label: Text('XL')),
                ],
                selected: {settings.lyricsTextSize},
                onSelectionChanged: (value) =>
                    setState(() => settings.lyricsTextSize = value.first),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Motion & effects', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SettingsHighlight(
            key: _keys['now_playing_background'],
            child: ListTile(
            title: const Text('Now Playing background'),
            subtitle: const Text('What renders behind the controls'),
            trailing: DropdownButton<NowPlayingBackgroundStyle>(
              value: settings.nowPlayingBackgroundStyle,
              items: const [
                DropdownMenuItem(
                    value: NowPlayingBackgroundStyle.solid,
                    child: Text('Solid')),
                DropdownMenuItem(
                    value: NowPlayingBackgroundStyle.blurredArt,
                    child: Text('Blurred art')),
                DropdownMenuItem(
                    value: NowPlayingBackgroundStyle.gradient,
                    child: Text('Gradient')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings.nowPlayingBackgroundStyle = value);
              },
            ),
            ),
          ),
          SettingsHighlight(
            key: _keys['dynamic_color'],
            child: SwitchListTile(
              title: const Text('Dynamic color from album art'),
              subtitle: const Text(
                  'Tint Now Playing to match the current track\'s artwork'),
              value: settings.dynamicColorFromArtEnabled,
              onChanged: (value) => setState(
                  () => settings.dynamicColorFromArtEnabled = value),
            ),
          ),
          SettingsHighlight(
            key: _keys['haptic_feedback'],
            child: SwitchListTile(
              title: const Text('Haptic feedback'),
              subtitle: const Text('A light tap for scrubbing, favoriting, '
                  'and reordering the queue'),
              value: settings.hapticFeedbackEnabled,
              onChanged: (value) =>
                  setState(() => settings.hapticFeedbackEnabled = value),
            ),
          ),
          SettingsHighlight(
            key: _keys['reduce_motion'],
            child: SwitchListTile(
              title: const Text('Reduce motion'),
              subtitle: const Text(
                  'Skip or shorten animations throughout the app'),
              value: settings.reduceMotionEnabled,
              onChanged: (value) =>
                  setState(() => settings.reduceMotionEnabled = value),
            ),
          ),
          SettingsHighlight(
            key: _keys['reduce_transparency'],
            child: SwitchListTile(
              title: const Text('Reduce transparency'),
              subtitle: const Text(
                  'Turn off blur/backdrop effects, independent of motion'),
              value: settings.reduceTransparencyEnabled,
              onChanged: (value) => setState(
                  () => settings.reduceTransparencyEnabled = value),
            ),
          ),
          const SizedBox(height: 16),
          Text('Player layout', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Changes how the whole Now Playing screen is arranged — not '
            'just colors. Pick a gesture-only layout to hide buttons '
            'entirely, or Car Mode for oversized controls on one edge. '
            'Import more below.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          SettingsHighlight(
            key: _keys['player_layout'],
            child: Card(
              child: Column(
                children: [
                  for (final layout in _layouts)
                    RadioListTile<String>(
                      value: layout.id,
                      groupValue: settings.playerLayoutId,
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => settings.playerLayoutId = value);
                      },
                      title: Text(layout.name),
                      subtitle: Text(
                        layout is DeclarativeLayout
                            ? '${layout.description}\nImported · '
                                '${layout.manifest.author}'
                            : layout.description,
                      ),
                      isThreeLine: layout is DeclarativeLayout,
                      secondary: layout is DeclarativeLayout
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: 'Remove imported layout',
                              onPressed: () async {
                                if (settings.playerLayoutId == layout.id) {
                                  settings.playerLayoutId = 'standard';
                                }
                                await widget.layoutManager.uninstall(layout);
                              },
                            )
                          : Icon(layout.icon),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _LayoutImportCard(layoutManager: widget.layoutManager),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Auto-switch to Landscape when rotated'),
            subtitle: const Text(
                'Applies to Standard and Top Controls only — Landscape, the '
                'gesture layouts, and Car Mode already suit a wide screen'),
            value: settings.autoLandscapeLayout,
            onChanged: (value) =>
                setState(() => settings.autoLandscapeLayout = value),
          ),
          SwitchListTile(
            title: const Text('Car Mode controls on the right'),
            subtitle: const Text(
                'Only affects the Car Mode layout — off puts the control '
                'rail on the left instead'),
            value: settings.carModeControlsOnRight,
            onChanged: (value) =>
                setState(() => settings.carModeControlsOnRight = value),
          ),
        ],
      ),
    );
  }
}
