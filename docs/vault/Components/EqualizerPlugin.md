---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# EqualizerPlugin

A bundled equalizer plugin with two implementations behind one API: - **Hardware mode** (Android only): drives the OS's real per-band equalizer (`android.media.audiofx.Equalizer`) through `PluginContext.hardwareEqBands` — genuine frequency-band shaping, reported and controlled by the device itself.

## Where it lives

`Omnis-Plugins/lib/equalizer_plugin.dart`

## Serves

- [[18 - DSP pipeline]] (feeds a named gain contribution into [[AudioEngine]])
- [[20 - EQ]]
