import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/keyboard_shortcut_remap.dart';
import 'package:omnis/ui/settings/shortcut_capture_dialog.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';

/// Keyboard: the on/off switch for `GlobalKeyboardShortcuts`, plus
/// item 48's per-shortcut remapping (each row opens
/// [showShortcutCaptureDialog]) with conflict detection and a
/// non-blocking warning for a reserved activation key
/// ([isReservedActivationKey]) — previously just a static reference
/// list, this page's own doc comment used to name exactly this as
/// deliberately deferred. Surfaced as its own first-class settings
/// category per the UI spec's taxonomy (§45), the same way
/// Accessibility got pulled out of Appearance & Layout earlier this
/// session rather than being buried as a sub-section.
///
/// The three hardware media-key bindings (play/pause, next, previous)
/// aren't remappable here — see [GlobalKeyboardShortcuts]'s own doc —
/// shown as plain, non-tappable reference rows instead.
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

  static const _hardwareKeyRows = [
    ('Media play/pause key', 'Play / pause'),
    ('Media next/previous track key', 'Next / previous track'),
  ];

  static const _actionLabels = {
    ShortcutAction.togglePlayPause: 'Play / pause',
    ShortcutAction.nextTrack: 'Next track',
    ShortcutAction.previousTrack: 'Previous track',
    ShortcutAction.seekForward: 'Seek forward 10s',
    ShortcutAction.seekBackward: 'Seek backward 10s',
    ShortcutAction.volumeUp: 'Volume up',
    ShortcutAction.volumeDown: 'Volume down',
    ShortcutAction.toggleMute: 'Mute / unmute',
  };

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    scrollToAndFlashSetting(_keys[widget.highlightField]);
  }

  Future<void> _remap(ShortcutAction action) async {
    final changed = await showShortcutCaptureDialog(context, action);
    if (changed == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    final theme = Theme.of(context);
    final bindings = settings.shortcutBindings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keyboard'),
        actions: [
          TextButton(
            onPressed: () async {
              await settings.resetAllShortcutBindings();
              if (mounted) setState(() {});
            },
            child: const Text('Reset all'),
          ),
        ],
      ),
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
          const SizedBox(height: 4),
          Text(
            'Tap a shortcut to remap it.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final action in ShortcutAction.values)
                  ListTile(
                    title: Text(_actionLabels[action]!),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(bindings[action]!.displayLabel,
                            style: theme.textTheme.bodySmall),
                        if (bindings[action] !=
                            defaultShortcutBindings[action])
                          IconButton(
                            icon: const Icon(Icons.restore, size: 18),
                            tooltip: 'Reset to default',
                            onPressed: () async {
                              await settings.resetShortcutBinding(action);
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                    onTap: () => _remap(action),
                  ),
                for (final (key, actionLabel) in _hardwareKeyRows)
                  ListTile(
                    title: Text(actionLabel),
                    subtitle: const Text('Hardware key, not remappable'),
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
