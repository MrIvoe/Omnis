---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# DeviceVolumePlugin

Remembers a separate master-volume level per output device — item 21's "no per-device volume profile" gap, the same idea `EqualizerPlugin` already implements for EQ bands, extended to plain volume: headphones can play quieter than a car Bluetooth speaker, and switching between them restores each one's own remembered level instead of carrying over whatever the other was left at.

## Where it lives

`Omnis-Plugins/lib/device_volume_plugin.dart`

## Serves

*(fill in during cross-linking pass)*
