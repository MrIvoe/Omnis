---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# ScrobblePlugin

Records real play history, persisted via this plugin's own [MusicPlugin.storage] (plugin-private state, not a shared app-settings singleton — `storage` also works before this plugin is attached to a `PluginManager`, unlike `context`, which keeps it usable standalone in tests).

## Where it lives

`Omnis-Plugins/lib/scrobble_plugin.dart`

## Implements

- [[IPlayHistoryProvider]]

## Serves

*(fill in during cross-linking pass)*
