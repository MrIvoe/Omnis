// Omnis example plugin — a small, complete, real bundled plugin.
//
// This file is not wired into the running app — bundled plugins are
// registered in `lib/bundled_plugins.dart` in the separate
// [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) repo, not
// here. It lives inside the `omnis` package and is checked by `flutter
// analyze`/compiles like any other file, so it can never silently rot
// out of date with the real API. To actually run it: move it into your
// Omnis-Plugins checkout, change its `omnis` imports below to
// `omnis_plugin_api` ones, add one line to that repo's own
// `bundled_plugins.dart`, and bump this app's `omnis_plugins:` pubspec
// ref once it's published — see docs/PLUGIN_GUIDE.md for the full
// workflow.
//
// Walks through every piece a real plugin typically touches:
//  - the MusicPlugin lifecycle (initialize/enable/disable/dispose)
//  - PluginContext: reading playback state, a composable gain contribution
//  - PluginStorage: persisted, namespaced per-plugin settings
//  - uiSlot('now_playing_overlay'): a small widget injected into a real page
//  - uiSlot('plugin_settings'): this plugin's own settings page, reached
//    by tapping it in the Plugins list
//
// See docs/PLUGIN_GUIDE.md for the full walkthrough this file accompanies.

import 'package:flutter/material.dart';
import 'package:omnis/core/base_track.dart';
import 'package:omnis/core/plugin_interface.dart';

/// Counts how many tracks have played since the app started, and
/// optionally applies a small volume boost — deliberately two unrelated
/// toy features in one file so it touches both halves of [PluginContext]
/// (reading state via [onTrackStart], writing playback via [setGain]).
class ExamplePlugin extends MusicPlugin {
  static const _gainSource = 'example_plugin';
  static const _boostEnabledKey = 'boost_enabled';
  static const _sessionTrackCountKey = 'lifetime_track_count';

  int _sessionCount = 0;

  /// Tracks played since the app started (not persisted — a "this session"
  /// stat is a reasonable thing to keep purely in memory).
  int get sessionTrackCount => _sessionCount;

  /// Whether the volume boost is currently on. Persisted via [storage], so
  /// it survives a restart — see [PluginStorage].
  bool get boostEnabled => storage.getBool(_boostEnabledKey) ?? false;

  Future<void> setBoostEnabled(bool value) async {
    await storage.setBool(_boostEnabledKey, value);
    if (value) {
      // Every plugin uses its own gain-source key, so contributions from
      // different plugins compose instead of overwriting one another —
      // see ReplayGainPlugin/EqualizerPlugin for the real thing.
      await context?.setGain(_gainSource, 1.1);
    } else {
      await context?.clearGain(_gainSource);
    }
  }

  @override
  String get id => 'example_plugin';

  @override
  String get name => 'Example Plugin';

  @override
  String get description =>
      'Counts tracks played this session; docs/PLUGIN_GUIDE.md reference.';

  @override
  String get version => '1.0.0';

  @override
  String get author => 'Omnis Team';

  @override
  Future<void> initialize() async {
    // storage is warmed by PluginManager before this runs, so a synchronous
    // read here already sees whatever a previous session persisted.
    final lifetimeCount = storage.getInt(_sessionTrackCountKey) ?? 0;
    debugPrint('ExamplePlugin: $lifetimeCount tracks played across all '
        'previous sessions');
    if (boostEnabled) {
      await context?.setGain(_gainSource, 1.1);
    }
  }

  @override
  Future<void> onTrackStart(BaseTrack track) async {
    _sessionCount++;
    final lifetimeCount = (storage.getInt(_sessionTrackCountKey) ?? 0) + 1;
    await storage.setInt(_sessionTrackCountKey, lifetimeCount);
  }

  @override
  Future<void> onLibraryScan(String file) async {}

  @override
  Future<void> disable() async => context?.clearGain(_gainSource);

  @override
  dynamic uiSlot(String locationID) => switch (locationID) {
        'now_playing_overlay' => _SessionCountBadge(plugin: this),
        'plugin_settings' => _ExampleSettings(plugin: this),
        _ => null,
      };

  @override
  Future<void> dispose() async {}
}

/// Small badge shown on the Now Playing screen (`uiSlot('now_playing_overlay')`).
/// Rebuilds itself on every track start via `context.trackStream` rather
/// than relying on the host page to poll it.
class _SessionCountBadge extends StatefulWidget {
  final ExamplePlugin plugin;

  const _SessionCountBadge({required this.plugin});

  @override
  State<_SessionCountBadge> createState() => _SessionCountBadgeState();
}

class _SessionCountBadgeState extends State<_SessionCountBadge> {
  @override
  void initState() {
    super.initState();
    widget.plugin.context?.trackStream.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '${widget.plugin.sessionTrackCount} played this session',
        style: TextStyle(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

/// This plugin's own settings page (`uiSlot('plugin_settings')`), reached
/// by tapping it in the Plugins list — see docs/PLUGIN_GUIDE.md.
class _ExampleSettings extends StatefulWidget {
  final ExamplePlugin plugin;

  const _ExampleSettings({required this.plugin});

  @override
  State<_ExampleSettings> createState() => _ExampleSettingsState();
}

class _ExampleSettingsState extends State<_ExampleSettings> {
  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: const Text('Volume boost'),
      subtitle: const Text('Apply a small +10% gain while this plugin is on'),
      value: widget.plugin.boostEnabled,
      onChanged: (value) async {
        await widget.plugin.setBoostEnabled(value);
        if (mounted) setState(() {});
      },
    );
  }
}
