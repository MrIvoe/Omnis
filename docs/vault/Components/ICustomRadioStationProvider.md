---
type: component
kind: interface
repo: both
status: stable
---

# ICustomRadioStationProvider

Read access to user-added custom radio stations (`omnis_plugins`' `CustomRadioStationStore`/`CustomRadioStation`) for the two Omnis-app call sites that need it — scheduled "play this custom station" playback (`MainCore._checkPlaybackSchedules`) and the scheduled-playback editor's "pick a target" list (`PlaybackSchedulePage`) — without either one reaching a plugin-owned store by a direct concrete import.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[RadioPlugin]]

## Serves

- [[41 - Radio]]
- [[50 - Automation]] (scheduled radio — a saved custom station)
