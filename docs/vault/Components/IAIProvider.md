---
type: component
kind: interface
repo: both
status: stable
---

# IAIProvider

Turns a natural-language request into a real queue built from the caller's own library — the spec's §21 "AI subsystem" ("a major optional ecosystem," in its own words) starting from one deliberately narrow slice: playlist creation from a prompt like "make me a two-hour workout playlist." Natural-language search, metadata cleanup, tagging, a conversational "library assistant," voice control, and artist-similarity discovery are each real, separate capabilities the spec names — none of them is this interface's job, and cramming them in here would be exactly the kind of keeps-growing-forever interface `service_interfaces.dart`'s own file doc warns against.

## Where it lives

`packages/omnis_plugin_api/lib/service_interfaces.dart`

## Implemented by

- [[AIPlaylistPlugin]]

## Serves

- [[43 - AI]]
