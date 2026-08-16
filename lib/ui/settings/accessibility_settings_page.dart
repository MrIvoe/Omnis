import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';

/// Accessibility: motion sensitivity and input, surfaced as its own
/// first-class settings category per the UI spec's taxonomy (§45), not
/// buried a few rows into Appearance & Layout the way these previously
/// were. `AppSettings.reduceMotionEnabled`/`reduceTransparencyEnabled`/
/// `hapticFeedbackEnabled` are unchanged — this page only moves *where*
/// they're surfaced, not what they do or how they persist.
class AccessibilitySettingsPage extends StatefulWidget {
  /// Set when opened from `SettingsPage`'s search with a specific row in
  /// mind — that row scrolls into view and flashes once this page mounts.
  final String? highlightField;

  const AccessibilitySettingsPage({super.key, this.highlightField});

  @override
  State<AccessibilitySettingsPage> createState() =>
      _AccessibilitySettingsPageState();
}

class _AccessibilitySettingsPageState
    extends State<AccessibilitySettingsPage> {
  late AppSettings _settings;

  final Map<String, GlobalKey<SettingsHighlightState>> _keys = {
    for (final field in [
      'high_contrast',
      'reduce_motion',
      'reduce_transparency',
      'haptic_feedback',
    ])
      field: GlobalKey<SettingsHighlightState>(),
  };

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
      appBar: AppBar(title: const Text('Accessibility')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Display', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SettingsHighlight(
            key: _keys['high_contrast'],
            child: SwitchListTile(
              title: const Text('High contrast'),
              subtitle: const Text(
                  'Stronger borders and a higher-contrast color scheme'),
              value: settings.highContrastEnabled,
              onChanged: (value) =>
                  setState(() => settings.highContrastEnabled = value),
            ),
          ),
          const SizedBox(height: 16),
          Text('Motion', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
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
          Text('Input', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
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
        ],
      ),
    );
  }
}
