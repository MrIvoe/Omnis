# Omnis — Micro-kernel Music Engine

A high-performance, indestructible music player with a hot-swappable plugin ecosystem. The Core stays lightweight and never crashes; 100% of features live in plugins.

## Architecture

```
┌─────────────────────────────────────────────┐
│                  UI Layer                     │
│  Now Playing · Library · Plugins · Settings  │
├─────────────────────────────────────────────┤
│              PluginManager                    │
│  install · register · sandbox · health        │
├─────────────────────────────────────────────┤
│              AudioEngine (Core)               │
│  just_audio · gapless · crossfade · ReplayGain│
└─────────────────────────────────────────────┘
```

### Core Kernel (Indestructible)

- **AudioEngine** (`lib/core/audio_engine.dart`): gapless playback via `ConcatenatingAudioSource`, crossfade, ReplayGain pre-gain, real `audio_service` handler. If a file is corrupt, it auto-skips to the next track.
- **BaseTrack** (`lib/core/base_track.dart`): unified schema — local files, Spotify tracks, and YouTube streams are the same `BaseTrack` object with a `TrackType` enum.
- **PluginSandbox** (`lib/core/sandbox.dart`): every plugin hook runs in a try-catch. Failures log to a `PluginHealthRecord` dashboard, never crash the app.

### Plugin Ecosystem

- **PluginInstaller** (`lib/core/plugin_installer.dart`): paste a GitHub URL → downloads the repo as a zip → extracts → validates `omnis_plugin.yaml` → registers.
- **PluginRuntime** (`lib/core/plugin_runtime.dart`): executes downloaded plugin Dart code at runtime via `dart_eval` (a full Dart bytecode interpreter). Plugins are sandboxed — they cannot import `package:omnis` or `dart:ui`.
- **PluginManager** (`lib/core/plugin_manager.dart`): hot-swap (enable/disable/uninstall at runtime), hook dispatch (`onTrackStart`, `onLibraryScan`, `uiSlot`), health dashboard.

## Plugin Contract

A plugin is a self-contained Dart file (`plugin.dart`) plus a manifest (`omnis_plugin.yaml`):

### `omnis_plugin.yaml`

```yaml
id: my_plugin
name: My Plugin
description: Does something cool
version: 1.0.0
author: Your Name
entrypoint: plugin.dart
hooks:
  - onTrackStart
  - onLibraryScan
permissions:
  - network
```

### `plugin.dart`

```dart
dynamic createPlugin(dynamic api) {
  return {
    'id': 'my_plugin',
    'name': 'My Plugin',
    'description': 'Does something cool',
    'version': '1.0.0',
    'author': 'Your Name',
    'hooks': ['onTrackStart', 'onLibraryScan'],
  };
}

dynamic onTrackStart(dynamic track) {
  // track is a JSON Map: {id, title, artists, album, duration, ...}
  return null;
}

dynamic onLibraryScan(dynamic file) {
  // file is a String path
  return null;
}
```

### Installing a Plugin

1. Open the **Plugins** tab.
2. Paste a GitHub repository URL (e.g. `https://github.com/user/my-plugin`).
3. Click **Install**.
4. The plugin is downloaded, extracted, compiled, and executed at runtime.
5. Toggle it on/off or uninstall at any time (hot-swap).

### Plugin Health Dashboard

If a plugin crashes, the failure appears in the **Plugin Health** section of the Plugins tab. The music never stops.

## Running

```bash
cd Omnis
flutter pub get
flutter run
```

## Testing

```bash
cd Omnis
flutter test
```

## Sample Plugin

See `plugins/sample_logger/` for a minimal example plugin.