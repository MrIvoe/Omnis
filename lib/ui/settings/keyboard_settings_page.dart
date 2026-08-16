import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';

/// Keyboard: the on/off switch for `GlobalKeyboardShortcuts` plus a
/// reference list of what each shortcut does, surfaced as its own
/// first-class settings category per the UI spec's taxonomy (§45), the
/// same way Accessibility got pulled out of Appearance & Layout earlier
/// this session rather than being buried as a sub-section.
///
/// No per-shortcut remapping here — a real, separate feature (would need
/// its own conflict-detection UI, since e.g. reassigning Space to
/// something else risks colliding with a focused control's own
/// Space-to-activate binding) left for a future increment; this page's
/// job is turning the fixed set on/off and telling the user what it
/// does.
class KeyboardSettingsPage extends StatefulWidget {
  final String? highlightField;

  const KeyboardSettingsPage({super.key, this.highlightField});

  @override
  State<KeyboardSettingsPage> createState() => _KeyboardSettingsPageState();
}

class _KeyboardSettingsPageState extends State<KeyboardSettingsPage> {
  late AppSettings _settings;

  final Map<String, GlobalKey<SettingsHighlightState>> _keys = {
    for (final field in ['keyboard_shortcuts_enabled'])
      field: GlobalKey<SettingsHighlightState>(),
  };

  static const _shortcuts = [
    ('Space', 'Play / pause'),
    ('Media play/pause key', 'Play / pause'),
    ('Media next/previous track key', 'Next / previous track'),
    ('Ctrl + Right / Left arrow', 'Next / previous track'),
    ('Right / Left arrow', 'Seek forward / backward 10s'),
    ('Up / Down arrow', 'Volume up / down'),
    ('M', 'Mute / unmute'),
  ];

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    scrollToAndFlashSetting(_keys[widget.highlightField]);
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Keyboard')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsHighlight(
            key: _keys['keyboard_shortcuts_enabled'],
            child: SwitchListTile(
              title: const Text('Enable keyboard shortcuts'),
              subtitle: const Text(
                  'Global playback shortcuts, active whenever nothing else '
                  'has focus (typing in a text field is never intercepted)'),
              value: settings.keyboardShortcutsEnabled,
              onChanged: (value) =>
                  setState(() => settings.keyboardShortcutsEnabled = value),
            ),
          ),
          const SizedBox(height: 16),
          Text('Shortcuts', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final (key, action) in _shortcuts)
                  ListTile(
                    title: Text(action),
                    trailing: Text(key, style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
