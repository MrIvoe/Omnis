---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# OnlinePlugin

Contributes the Online tab (Internet Radio, self-hosted media-server search, embedded YouTube/Spotify playback) as a [PluginDestination] — Tier 2 task 5's extraction of what used to be a hardcoded core tab built inline in the Omnis app's own `lib/ui/home_page.dart`, alongside `online_page.dart` (which now also hosts `RadioBody`, merged in during the same move — see that file's own doc comment for why) and `custom_radio_station_store.dart`.

## Where it lives

`Omnis-Plugins/lib/online_plugin.dart`

## Serves

No single tracked feature — the umbrella UI container (Online tab) that hosts [[41 - Radio]] (via [[RadioPlugin]]), self-hosted media-server search (via [[31 - OpenSubsonic]]/[[33 - Jellyfin]]/[[34 - Plex]]/[[38 - Other providers]]), and embedded playback (via [[36 - Spotify]]/[[37 - YouTube]]).
