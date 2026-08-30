---
type: component
kind: interface
repo: both
status: stable
---

# IQueueBuilder

Builds a ready-to-play queue for a named query (a mood/preset label like `"Chill"` or `"Workout"`).

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[QueuePresetPlugin]]
- [[SmartPlaylistPlugin]]

## Serves

- [[42 - Smart playlists]] (via [[SmartPlaylistPlugin]]; [[QueuePresetPlugin]]'s own preset tiles aren't named by any of the 50 tracked features)
