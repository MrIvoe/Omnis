---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# MainCore

The entry point for the Omnis micro-kernel music engine — wires together the two "indestructible" layers, [[AudioEngine]] (playback never stops) and [[PluginManager]] (plugin crashes are sandboxed and health-logged), and deliberately knows no concrete plugin: the only plugin-side import is the bundled-plugin factory list from the separate `omnis_plugins` package. It also owns the playback watchdog/recovery pair, a rolling diagnostics store, bridges the audio engine's position/duration streams into low-frequency [[PlayHistoryStore]] writes (pause/track-change only, never per tick), and is the caller that fires [[RecoveryJournal]] saves from several independent, unawaited call sites.

## Where it lives

`lib/core/main_core.dart`

## Depends on

- [[AudioEngine]]
- [[PluginManager]]
- [[LibraryRepository]]
- [[PlayHistoryStore]]
- [[AppSettings]]
- [[MediaScanner]]
- [[RecoveryJournal]]
- [[PlaylistStore]]

## Serves

- [[3 - Recovery]]
