---
type: component
kind: interface
repo: both
status: stable
---

# ISyncedLyricsProvider

Supplies the full ordered list of time-synced lyric lines for a track, when a provider genuinely has them — letting a caller render every line at once (Spotify-style scrolling lyrics), not just [ILyricsProvider.currentLyricFor]'s single current line/block.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[LyricsPlugin]]

## Serves

No tracked feature relies on this directly — [[LyricsPlugin]] is its sole implementer, itself not named by any of the 50 tracked features.
