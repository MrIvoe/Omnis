---
type: component
kind: interface
repo: both
status: stable
---

# IOnlineSearchProvider

Searches a self-hosted media server's own catalog and returns real, directly playable [BaseTrack]s (a genuine `streamUrl`, unlike [IAIProvider.searchLibrary], which only ever searches the tracks already scanned into the local library).

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[AmpachePlugin]]
- [[EmbyPlugin]]
- [[JellyfinPlugin]]
- [[KoelPlugin]]
- [[OpenSubsonicPlugin]]
- [[PlexPlugin]]

## Serves

- [[31 - OpenSubsonic]]
- [[32 - Navidrome]]
- [[33 - Jellyfin]]
- [[34 - Plex]]
- [[38 - Other providers]]
