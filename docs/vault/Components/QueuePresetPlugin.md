---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# QueuePresetPlugin

Curated queue presets built from objective, always-available track data (genre keywords, BPM) — deliberately independent of `BaseTrack.mood`, which only ever gets populated by opt-in enrichment/analysis/manual tagging.

## Where it lives

`Omnis-Plugins/lib/queue_preset_plugin.dart`

## Implements

- [[IQueueBuilder]]

## Serves

Not named by any of the 50 tracked features — contributes curated preset queue tiles (by genre/BPM) alongside [[MoodsPlugin]]'s own presets in the Moods tab; [[39 - Recommendations]] credits [[MoodsPlugin]] as the primary implementer.
