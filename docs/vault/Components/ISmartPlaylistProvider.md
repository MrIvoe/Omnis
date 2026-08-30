---
type: component
kind: interface
repo: both
status: stable
---

# ISmartPlaylistProvider

Reads and plays a user's saved rule-based smart playlists — distinct from [IQueueBuilder] (which `SmartPlaylistPlugin` also implements): that interface matches a *query name* like a mood label against curated `BaseTrack.mood` tags, while this interface plays a specific *saved rule* the user built and named through the plugin's own settings UI.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

*(fill in during cross-linking pass)*

## Serves

*(fill in during cross-linking pass)*
