import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/audio_engine.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/core/scrobble_plugin.dart';
import 'package:omnis/core/sandbox.dart';

class ColorIndicator extends StatelessWidget {
  final Color color;

  const ColorIndicator({super.key, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
    );
  }
}

class SliderListTile extends StatelessWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final String? label;
  final ValueChanged<double>? onChanged;

  const SliderListTile({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.label,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        onChanged: onChanged,
      ),
    );
  }
}

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
          final selected = color.value == _selectedColor.value;
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

/// Settings screen that hosts playback controls and plugin management.
class SettingsPage extends StatefulWidget {
  final AudioEngine engine;
  final PluginManager pluginManager;
  final PluginSandbox sandbox;

  const SettingsPage({
    super.key,
    required this.engine,
    required this.pluginManager,
    required this.sandbox,
  });

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  double _volume = 1.0;
  double _speed = 1.0;
  double _crossfadeSec = 0;
  bool _gapless = true;
  List<ManagedPlugin> _plugins = [];
  List<PluginHealthRecord> _health = [];
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    _plugins = widget.pluginManager.plugins;
    _health = widget.sandbox.healthRecords;
    widget.pluginManager.changes.listen((plugins) {
      if (mounted) setState(() => _plugins = plugins);
    });
    widget.sandbox.addHealthListener((records) {
      if (mounted) setState(() => _health = records);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Theme'),
            subtitle: const Text('Switch between light, dark, or system'),
            trailing: DropdownButton<ThemeMode>(
              value: settings.themeMode,
              items: const [
                DropdownMenuItem(
                    value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings.themeMode = value);
              },
            ),
          ),
          ListTile(
            title: const Text('Accent color'),
            subtitle: const Text('Set the main app accent color'),
            trailing: ColorIndicator(color: settings.accentColor),
            onTap: () async {
              final color = await showDialog<Color>(
                context: context,
                builder: (context) =>
                    _ColorPickerDialog(initialColor: settings.accentColor),
              );
              if (color != null) {
                setState(() => settings.accentColor = color);
              }
            },
          ),
          ListTile(
            title: const Text('Theme preset'),
            subtitle: const Text('Choose a more polished aesthetic palette'),
            trailing: DropdownButton<AppThemePreset>(
              value: settings.themePreset,
              items: const [
                DropdownMenuItem(
                    value: AppThemePreset.classic, child: Text('Classic')),
                DropdownMenuItem(
                    value: AppThemePreset.midnight, child: Text('Midnight')),
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
          SliderListTile(
            title: 'Album art scale',
            value: settings.albumArtScale,
            min: 0.7,
            max: 1.4,
            divisions: 14,
            label: settings.albumArtScale.toStringAsFixed(2),
            onChanged: (value) =>
                setState(() => settings.albumArtScale = value),
          ),
          SwitchListTile(
            title: const Text('Show album art'),
            value: settings.showAlbumArt,
            onChanged: (value) => setState(() => settings.showAlbumArt = value),
          ),
          const SizedBox(height: 16),
          Text('Playback', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Gapless playback'),
            subtitle: const Text(
                'Concatenate tracks seamlessly with no silence between them.'),
            value: _gapless,
            onChanged: (v) {
              setState(() => _gapless = v);
              widget.engine.setGaplessEnabled(v);
            },
          ),
          ListTile(
            title: const Text('Crossfade'),
            subtitle: Text(_crossfadeSec <= 0
                ? 'Off'
                : '${_crossfadeSec.toStringAsFixed(1)} seconds'),
            trailing: DropdownButton<double>(
              value: _crossfadeSec <= 0 ? 0 : _crossfadeSec,
              items: const [
                DropdownMenuItem(value: 0.0, child: Text('Off')),
                DropdownMenuItem(value: 3.0, child: Text('3 sec')),
                DropdownMenuItem(value: 5.0, child: Text('5 sec')),
                DropdownMenuItem(value: 8.0, child: Text('8 sec')),
              ],
              onChanged: (v) {
                if (v == null) return;
                setState(() => _crossfadeSec = v);
                widget.engine
                    .setCrossfadeDuration(Duration(seconds: v.round()));
              },
            ),
          ),
          ListTile(
            title: const Text('Volume'),
            subtitle: Slider(
              value: _volume,
              min: 0,
              max: 1,
              onChanged: (v) {
                setState(() => _volume = v);
                widget.engine.setVolume(v);
              },
            ),
          ),
          ListTile(
            title: const Text('Playback speed'),
            subtitle: Slider(
              value: _speed,
              min: 0.25,
              max: 2.0,
              divisions: 14,
              label: '${_speed.toStringAsFixed(2)}x',
              onChanged: (v) {
                setState(() => _speed = v);
                widget.engine.setSpeed(v);
              },
            ),
          ),
          const SizedBox(height: 16),
          Text('Controls & gestures', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Button layout'),
            subtitle:
                const Text('Choose how busy the player controls should be'),
            trailing: DropdownButton<ButtonLayout>(
              value: settings.buttonLayout,
              items: const [
                DropdownMenuItem(
                    value: ButtonLayout.standard, child: Text('Standard')),
                DropdownMenuItem(
                    value: ButtonLayout.compact, child: Text('Compact')),
                DropdownMenuItem(
                    value: ButtonLayout.minimal, child: Text('Minimal')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings.buttonLayout = value);
              },
            ),
          ),
          ListTile(
            title: const Text('Gesture mode'),
            subtitle: const Text(
                'Use gestures or tap controls for skipping and returning'),
            trailing: DropdownButton<GestureMode>(
              value: settings.gestureMode,
              items: const [
                DropdownMenuItem(
                    value: GestureMode.swipe, child: Text('Swipe')),
                DropdownMenuItem(value: GestureMode.taps, child: Text('Taps')),
                DropdownMenuItem(value: GestureMode.none, child: Text('None')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings.gestureMode = value);
              },
            ),
          ),
          SwitchListTile(
            title: const Text('Swipe gestures'),
            subtitle:
                const Text('Allow left/right swipes to skip or replay tracks'),
            value: settings.allowSwipeGestures,
            onChanged: (value) =>
                setState(() => settings.allowSwipeGestures = value),
          ),
          SwitchListTile(
            title: const Text('Lyrics view'),
            subtitle: const Text('Show lyric mode in the player screen'),
            value: settings.showLyrics,
            onChanged: (value) => setState(() => settings.showLyrics = value),
          ),
          SwitchListTile(
            title: const Text('Karaoke mode'),
            subtitle: const Text('Highlight the current lyric line'),
            value: settings.karaokeMode,
            onChanged: (value) => setState(() => settings.karaokeMode = value),
          ),
          const SizedBox(height: 16),
          Text('Library access', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            title: const Text('Library source'),
            subtitle: const Text(
                'Choose whether to scan the whole phone, a dedicated folder, or nothing'),
            trailing: DropdownButton<LibrarySource>(
              value: settings.librarySource,
              items: const [
                DropdownMenuItem(
                    value: LibrarySource.wholePhone,
                    child: Text('Whole phone')),
                DropdownMenuItem(
                    value: LibrarySource.dedicatedFolder,
                    child: Text('Dedicated folder')),
                DropdownMenuItem(
                    value: LibrarySource.none, child: Text('None')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => settings.librarySource = value);
              },
            ),
          ),
          ListTile(
            title: const Text('Folder for library scans'),
            subtitle:
                Text(settings.selectedFolderPath ?? 'Pick a folder to browse'),
            trailing: FilledButton.tonal(
              onPressed: () async {
                final result = await FilePicker.platform.getDirectoryPath();
                if (result != null) {
                  setState(() => settings.selectedFolderPath = result);
                }
              },
              child: const Text('Pick folder'),
            ),
          ),
          const SizedBox(height: 16),
          Text('Plugin activity', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Builder(builder: (context) {
            final scrobble = widget.pluginManager.plugins
                .whereType<ManagedPlugin>()
                .where((plugin) => plugin.id == 'scrobble')
                .toList();
            if (scrobble.isEmpty) {
              return const SizedBox.shrink();
            }
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Scrobble history'),
                    const SizedBox(height: 8),
                    Text(
                        'Recent plays are being recorded for future sync support.'),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          Text('Plugins', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_plugins.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No plugins installed yet.')))
          else
            ..._plugins.map((plugin) => Card(
                  child: ListTile(
                    title: Text(plugin.name),
                    subtitle: Text('${plugin.description}\nv${plugin.version}'),
                    trailing: Switch(
                      value: plugin.enabled,
                      onChanged: (value) => value
                          ? widget.pluginManager.enablePlugin(plugin)
                          : widget.pluginManager.disablePlugin(plugin),
                    ),
                  ),
                )),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('Plugin health', style: theme.textTheme.titleMedium),
              const Spacer(),
              if (_health.isNotEmpty)
                TextButton(
                    onPressed: widget.sandbox.clearHealth,
                    child: const Text('Dismiss all')),
            ],
          ),
          const SizedBox(height: 8),
          if (_health.isEmpty)
            const Card(
                child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No plugin failures.')))
          else
            ..._health.map((record) => Card(
                  color:
                      theme.colorScheme.errorContainer.withValues(alpha: 0.4),
                  child: ListTile(
                    title: Text('${record.pluginName} • ${record.hook}'),
                    subtitle: Text('${record.reason}\n${record.message}'),
                  ),
                )),
        ],
      ),
    );
  }
}
