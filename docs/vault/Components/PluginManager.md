---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# PluginManager

The heart of the micro-kernel plugin ecosystem. Owns registration of in-process `MusicPlugin`s (the bundled plugins compiled into the app), installation of GitHub-downloaded plugins via `PluginInstaller`, runtime execution of those downloaded plugins via `PluginRuntime` (hooks receive JSON-serialised tracks), isolation of every plugin hook call via the sandbox (a plugin crash reaches the health dashboard, never the player), and hot-swap enable/disable/uninstall at runtime. Unifies both plugin kinds under one `ManagedPlugin` record.

## Where it lives

`lib/core/plugin_manager.dart`

## Depends on

- [[AppSettings]]

## Serves

- [[8 - Error handling]] (plugin sandboxing/crash isolation)
- [[24 - Capability interfaces]]
- [[25 - Plugin lifecycle]]
- [[26 - Dependency resolution]]
- [[27 - Permissions]]
- [[28 - Plugin health]]
- [[29 - Plugin updates]]
- [[30 - Marketplace-catalog]]
