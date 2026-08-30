---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# ShuffleRepeatPlugin

Shuffle and repeat mode — the Core Philosophy doc lists "Shuffle Algorithms" explicitly under Layer 3 (Plugin Ecosystem), not Layer 2 (Player Runtime): repeat-mode handling stays a thin call into [PluginContext] (`setRepeatMode` just forwards to just_audio's own loop mode, which is where it has to live to stay consistent with just_audio's gapless auto-advance — see `AudioEngine`'s doc), but shuffle *order* is this plugin's own algorithm, not just_audio's plain shuffle — see [toggleShuffle].

## Where it lives

`Omnis-Plugins/lib/shuffle_repeat_plugin.dart`

## Serves

- [[1 - Playback engine]]
