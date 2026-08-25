import 'dart:async';

import 'package:flutter/material.dart';
import 'package:omnis/core/app_settings.dart';
import 'package:omnis/core/platform_capabilities.dart';
import 'package:omnis/core/plugin_manager.dart';
import 'package:omnis/plugin_api/plugin_destination.dart';
import 'package:omnis/ui/widgets/settings_highlight.dart';

/// The four fixed core destinations' ids and display labels, in the same
/// order `home_page.dart`'s own `_coreDestinationIds`/`destinations`
/// lists pair them. Duplicated here rather than imported — Dart's
/// leading-underscore privacy keeps `home_page.dart`'s versions scoped to
/// that file — so this page's launch-tab picker can list every
/// destination a user might choose as their default. Kept in sync by
/// hand, the same tradeoff `settings_page.dart`'s own `_SearchableSetting`
/// index already accepts for the same "no runtime introspection
/// mechanism exists for this" reason.
///
/// No `('home', 'Home')` entry (Tier 2 task 3) and no `('moods', 'Moods')`
/// entry (Tier 2 task 4) — neither is a reserved core id any more; both
/// are now only reachable via `_pluginDestinations` below, contributed by
/// the bundled `HomeDashboardPlugin`/`MoodsPlugin` like any other plugin
/// destination. Leaving either here would put a *duplicate* entry in the
/// dropdown whenever the contributing plugin is enabled — a real
/// `DropdownButton` assertion crash, not just a cosmetic repeat.
const _coreLaunchTabOptions = <(String, String)>[
  ('library', 'Library'),
  ('playlist', 'Playlist'),
  ('online', 'Online'),
  ('settings', 'Settings'),
];

/// Controls & Gestures: how you interact with playback — button density,
/// swipe/tap behavior, and whether the bottom navigation bar stays out of
/// the way. Distinct from Appearance (what it looks like) even though
/// both affect the Now Playing screen.
class ControlsSettingsPage extends StatefulWidget {
  final PluginManager pluginManager;

  /// Set when opened from `SettingsPage`'s search with a specific row in
  /// mind — that row scrolls into view and flashes once this page mounts.
  final String? highlightField;

  const ControlsSettingsPage(
      {super.key, required this.pluginManager, this.highlightField});

  @override
  State<ControlsSettingsPage> createState() => _ControlsSettingsPageState();
}

class _ControlsSettingsPageState extends State<ControlsSettingsPage> {
  late AppSettings _settings;

  /// Plugin-contributed destinations, kept live the same way
  /// `_HomePageState._pluginDestinations` is — read once here in
  /// `initState`/on `changes` rather than from `build()`, since
  /// `PluginManager.homeDestinations` runs every plugin's hook through
  /// `Sandbox.runSync`, whose failure path can notify listeners
  /// synchronously (see that field's own doc comment in `home_page.dart`
  /// for the "setState during build" failure mode this avoids).
  List<PluginDestination> _pluginDestinations = const [];
  StreamSubscription<List<ManagedPlugin>>? _pluginManagerSub;

  final Map<String, GlobalKey<SettingsHighlightState>> _keys = {
    for (final field in [
      'button_layout',
      'gesture_mode',
      'enable_gestures',
      'auto_hide_nav',
      'default_launch_tab',
    ])
      field: GlobalKey<SettingsHighlightState>(),
  };

  @override
  void initState() {
    super.initState();
    _settings = AppSettings.instance;
    _pluginDestinations = widget.pluginManager.homeDestinations;
    _pluginManagerSub = widget.pluginManager.changes.listen((_) {
      if (mounted) {
        setState(() {
          _pluginDestinations = widget.pluginManager.homeDestinations;
        });
      }
    });
    scrollToAndFlashSetting(_keys[widget.highlightField]);
  }

  @override
  void dispose() {
    _pluginManagerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    // Core destinations first, then whatever plugins currently contribute
    // a tab — mirrors the order `home_page.dart`'s own `destinationIds`
    // list builds in (core ids, then `pluginDestinations`), so this
    // dropdown's order matches where each entry actually renders in the
    // nav bar.
    final launchTabOptions = <(String, String)>[
      ..._coreLaunchTabOptions,
      for (final d in _pluginDestinations) (d.id, d.label),
    ];
    final currentLaunchTabId = settings.defaultLaunchTabId;
    final isCurrentLaunchTabAvailable =
        launchTabOptions.any((o) => o.$1 == currentLaunchTabId);
    return Scaffold(
      appBar: AppBar(title: const Text('Controls & Gestures')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SettingsHighlight(
            key: _keys['button_layout'],
            child: ListTile(
              title: const Text('Button layout'),
              subtitle: const Text(
                  'Choose how busy the player controls should be'),
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
          ),
          if (!PlatformCapabilities.isDesktopPrimary) ...[
            SettingsHighlight(
              key: _keys['gesture_mode'],
              child: ListTile(
                title: const Text('Gesture mode'),
                subtitle: const Text(
                    'Use gestures or tap controls for skipping and returning'),
                trailing: DropdownButton<GestureMode>(
                  value: settings.gestureMode,
                  items: const [
                    DropdownMenuItem(
                        value: GestureMode.swipe, child: Text('Swipe')),
                    DropdownMenuItem(
                        value: GestureMode.taps, child: Text('Taps')),
                    DropdownMenuItem(
                        value: GestureMode.none, child: Text('None')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => settings.gestureMode = value);
                  },
                ),
              ),
            ),
            SettingsHighlight(
              key: _keys['enable_gestures'],
              child: SwitchListTile(
                title: const Text('Enable player gestures'),
                subtitle: const Text(
                    'Master switch for whichever gesture mode is selected '
                    'above (swipe or tap zones)'),
                value: settings.allowSwipeGestures,
                onChanged: (value) =>
                    setState(() => settings.allowSwipeGestures = value),
              ),
            ),
          ],
          SettingsHighlight(
            key: _keys['auto_hide_nav'],
            child: SwitchListTile(
              title: const Text('Auto-hide bottom navigation'),
              subtitle: const Text(
                  'Hides the tab bar in landscape and Car Mode so it never '
                  'covers playback controls — swipe up from the bottom edge '
                  'or tap the small handle to bring it back'),
              value: settings.bottomNavAutoHide,
              onChanged: (value) =>
                  setState(() => settings.bottomNavAutoHide = value),
            ),
          ),
          SettingsHighlight(
            key: _keys['default_launch_tab'],
            child: ListTile(
              title: const Text('Default launch tab'),
              subtitle: const Text(
                  'Which tab Omnis opens to on startup — a disabled '
                  "plugin's tab falls back to the first available one"),
              trailing: DropdownButton<String>(
                // `null` rather than an unrecognised id: `DropdownButton`
                // asserts that a non-null `value` matches exactly one
                // `item`, which a stale id (a since-disabled plugin's tab)
                // would violate. `HomePage`'s own build() falls back to
                // the first destination for the same "no longer exists"
                // case; this dropdown just shows no selection instead.
                value:
                    isCurrentLaunchTabAvailable ? currentLaunchTabId : null,
                hint: const Text('First available'),
                items: [
                  for (final (id, label) in launchTabOptions)
                    DropdownMenuItem(value: id, child: Text(label)),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => settings.defaultLaunchTabId = value);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
