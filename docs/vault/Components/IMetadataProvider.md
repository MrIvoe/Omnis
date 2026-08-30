---
type: component
kind: interface
repo: both
status: stable
---

# IMetadataProvider

Looks up canonical/community metadata for a track from an external source (MusicBrainz, Last.fm, Discogs today, all behind one provider — `MetadataEnrichmentPlugin`).

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[MetadataEnrichmentPlugin]]

## Serves

- [[11 - Metadata]]
- [[12 - Artwork]] (artwork lookup)
