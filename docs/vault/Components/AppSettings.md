---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# AppSettings

A `ChangeNotifier`-backed singleton persisting nearly every user-facing app setting to `shared_preferences` behind one key namespace: theme mode/preset/accent color, layout and gesture choices, library source and watcher toggle, lyrics text size, playback volume/speed/pitch/crossfade/skip-silence/gapless, seek increment, keyboard shortcuts, disabled plugins, and more. It's the single source of truth every settings screen — and every other core singleton or plugin that needs to read a current setting — reads and writes through.

## Where it lives

`lib/core/app_settings.dart`

## Depends on

*(none — no dependency on another core singleton)*

## Serves

- [[6 - Persistence]] (settings persistence)
- [[44 - Themes]] (persists the active theme mode/preset/accent color)
