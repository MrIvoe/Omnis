---
type: component
kind: interface
repo: both
status: stable
---

# IRatingsProvider

Queries a track's star rating (0-5, 0 meaning unrated) — real signal `RatingsPlugin` already collects but that, before this interface existed, nothing outside that plugin itself could read: another plugin has no way to reach a different plugin's concrete type, only a registered capability.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[RatingsPlugin]]

## Serves

- [[15 - Ratings]]
