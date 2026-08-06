import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';

/// Controls & Gestures: how you interact with playback — button density,
/// swipe/tap behavior, and whether the bottom navigation bar stays out of
/// the way. Distinct from Appearance (what it looks like) even though
/// both affect the Now Playing screen.
class ControlsSettingsPage extends StatefulWidget {
  const ControlsSettingsPage({super.key});

  @override
  State<ControlsSettingsPage> createState() => _ControlsSettingsPageState();
}

class _ControlsSettingsPageState extends State<ControlsSettingsPage> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Controls & Gestures')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
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
            title: const Text('Enable player gestures'),
            subtitle: const Text(
                'Master switch for whichever gesture mode is selected above '
                '(swipe or tap zones)'),
            value: settings.allowSwipeGestures,
            onChanged: (value) =>
                setState(() => settings.allowSwipeGestures = value),
          ),
          SwitchListTile(
            title: const Text('Auto-hide bottom navigation'),
            subtitle: const Text(
                'Hides the tab bar in landscape and Car Mode so it never '
                'covers playback controls — swipe up from the bottom edge '
                'or tap the small handle to bring it back'),
            value: settings.bottomNavAutoHide,
            onChanged: (value) =>
                setState(() => settings.bottomNavAutoHide = value),
          ),
        ],
      ),
    );
  }
}
