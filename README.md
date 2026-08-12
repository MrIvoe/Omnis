# Omnis

[![CI](https://github.com/MrIvoe/Omnis/actions/workflows/ci.yml/badge.svg)](https://github.com/MrIvoe/Omnis/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Site](https://img.shields.io/badge/site-mrivoe.github.io%2FOmnis-3DDCC4)](https://mrivoe.github.io/Omnis/)
[![Wiki](https://img.shields.io/badge/docs-wiki-A78BFA)](https://github.com/MrIvoe/Omnis/wiki)

A micro-kernel music player with a hot-swappable plugin ecosystem. The
Core stays small and never crashes; every feature — equalizer, lyrics,
scrobbling, smart playlists, tag editing, Spotify/YouTube integration —
lives in a plugin.

## Features

**Playback**
- Gapless queue playback, crossfade, ReplayGain-based volume normalization
- Shuffle, repeat (off/all/one), A-B repeat
- Independent pitch and speed controls, skip-silence
- Real per-band hardware equalizer on Android; a virtual bass/mid/treble
  model everywhere else

**Library**
- List/grid views (2–5 column density) for Songs, Albums, and Genres;
  list views for Artists and Folders
- Duplicate and short-track ("ad stinger") detection with multi-select
  cleanup
- Real embedded artwork everywhere (MediaStore on Android, direct ID3
  parsing on desktop) — not a placeholder icon
- Manual and automatic ID3 tag editing — every standard field, plus
  freeform custom fields — with smart skip-if-already-tagged tracking
- Configurable "feat./ft./featuring" artist-separator rules, so a
  featured artist doesn't stay stuck in the title field

**Lyrics**
- Manual lyrics entry, or automatic online lookup (via
  [lrclib.net](https://lrclib.net), free, no API key) with optional
  time-synced display
- Optional auto-fetch when a track starts playing, and an option to embed
  fetched lyrics directly into the file's own tags

**Customization**
- Six built-in Now Playing layouts (Standard, Top Controls, Landscape,
  Full Art + Gestures, Karaoke Gestures, Car Mode), plus an importable
  declarative layout format for building your own — no code required,
  safe to import from a URL with no permission prompt
- Full theming: light/dark/system, accent color, presets
- Every plugin has its own settings page — tap it in the Plugins list —
  the same "click the plugin to configure it" model RuneLite uses

**Streaming integrations** *(bring your own API credentials — see
[docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md))*
- Spotify: browse/import your playlists, or remote-control playback on a
  Spotify Connect device
- YouTube: search and browse your playlists, or play a video through
  YouTube's own embedded player

**Ecosystem**
- Install community plugins by pasting a GitHub URL — sandboxed, with a
  permission-confirmation dialog before any downloaded code runs
- A plugin crash never takes down playback — every hook runs sandboxed,
  with failures surfaced on a Plugin Health dashboard, not silently
  swallowed or fatal

## Documentation

- **[Wiki](https://github.com/MrIvoe/Omnis/wiki)** — the long-form guide:
  architecture walkthrough, writing your first plugin end-to-end, the
  theme/layout YAML reference, and an honestly-labeled roadmap. Start
  here if you're new.
- **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)** — how the micro-kernel
  is put together and why: the Core/plugin split, `ServiceRegistry`/
  `EventBus`, `PluginContext`/`PluginStorage`, player layouts, and an
  honest "what's real vs. approximated" feature-by-feature breakdown.
- **[docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md)** — how to build a
  plugin, bundled or downloadable, with a complete working example at
  [`example/example_plugin.dart`](example/example_plugin.dart).
- **[docs/BUILDING.md](docs/BUILDING.md)** — prerequisites, running,
  testing, building release artifacts, signing.
- **[CONTRIBUTING.md](CONTRIBUTING.md)** — the ground rules and workflow
  for contributing.
- **[docs/PLUGIN_SECURITY.md](docs/PLUGIN_SECURITY.md)** — what a
  downloaded plugin can and can't do, written for anyone deciding
  whether to paste a GitHub URL in.
- **[docs/COMMUNITY_PLUGINS.md](docs/COMMUNITY_PLUGINS.md)** — a
  curated list of downloadable community plugins, and how to get yours
  added.
- **[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)** /
  **[SECURITY.md](SECURITY.md)** — community conduct expectations and
  how to privately report a vulnerability.

## Quick start

```bash
git clone <this-repo-url>
cd Omnis
flutter pub get
flutter run
```

See [docs/BUILDING.md](docs/BUILDING.md) for platform prerequisites,
building release artifacts, and troubleshooting.

## Architecture, in one picture

```
┌───────────────────────────────────────────────┐
│                   UI Layer                     │
│   Now Playing · Library · Plugins · Settings   │
├───────────────────────────────────────────────┤
│      lib/plugins/  — every feature lives here  │
│  equalizer · lyrics · replay gain · scrobble   │
│  Spotify · YouTube · smart playlist · …        │
├───────────────────────────────────────────────┤
│  lib/plugin_api/  — capability contracts.      │
│  Grows with the ecosystem. Depends on core;    │
│  core never depends back.                      │
├───────────────────────────────────────────────┤
│      lib/core/  — the kernel, plugin-agnostic  │
│  AudioEngine · PluginManager · Sandbox         │
│  PluginContext · ServiceRegistry · EventBus    │
└───────────────────────────────────────────────┘
```

The kernel never imports a concrete plugin — `lib/core/main_core.dart`
has exactly one plugin-side import, the registry. Adding a plugin means
editing `lib/plugins/`, never `lib/core/`. Full rationale in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Versioning across the plugin split

`omnis_plugins` ([github.com/MrIvoe/Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins))
and `packages/omnis_plugin_api` (in this repo) are pinned to each other by
git tag, not a floating branch — `pubspec.yaml`'s `ref:` fields. A push to
either repo never silently changes what the other builds against. To pick
up new work on purpose: cut a new tag in the changed repo, then bump the
`ref:` in whichever `pubspec.yaml` depends on it, as its own reviewed
commit.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Short version: `flutter analyze`
and `flutter test` clean before every PR, new features come with tests,
and most contributions are plugins — see
[docs/PLUGIN_GUIDE.md](docs/PLUGIN_GUIDE.md).

## License

[MIT](LICENSE).
