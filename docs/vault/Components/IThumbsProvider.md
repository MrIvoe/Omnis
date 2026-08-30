---
type: component
kind: interface
repo: both
status: stable
---

# IThumbsProvider

Queries a track's thumbs-up/down state — the identical nothing-outside-the-owning-plugin-can-read-this gap [IRatingsProvider]/[IFavoritesProvider]'s own docs already describe, mirrored here for a third, independent signal.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[RatingsPlugin]]

## Serves

- [[15 - Ratings]] (no tracked feature separately names a "thumbs" signal; [[RatingsPlugin]] is the same plugin [[15 - Ratings]] credits)
