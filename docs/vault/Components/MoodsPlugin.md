---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# MoodsPlugin

Contributes the Moods tab (preset mood tiles from every registered [IQueueBuilder], plus the user's own rule-based custom moods, plus the Forgotten Music page reached from its app bar) as a [PluginDestination] — Tier 2 task 4's extraction of what used to be a hardcoded core tab built inline in the Omnis app's own `lib/ui/home_page.dart`, alongside `mood_builder_dialog.dart`, `custom_mood.dart`, `forgotten_music_page.dart` and `forgotten_tracks.dart`.

## Where it lives

`Omnis-Plugins/lib/moods_plugin.dart`

## Implements

- [[IMoodPlayer]]

## Serves

- [[39 - Recommendations]]
