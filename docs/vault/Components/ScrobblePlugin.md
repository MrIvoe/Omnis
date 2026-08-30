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

Not named by any of the 50 tracked features directly — [[16 - History]] credits [[PlayHistoryStore]] as the always-on core implementer; this plugin is an optional alternate play-history recorder reachable through the same [[IPlayHistoryProvider]] interface.
