---
type: component
kind: plugin
repo: Omnis-Plugins
status: stable
---

# AIPlaylistPlugin

The first two real slices of the spec's §21 "AI subsystem" — natural language playlist creation ("make me a two-hour workout playlist") and natural language *search* ("upbeat songs from the 90s I haven't played in a while" — item 43's own named gap), both backed by a real cloud LLM (Anthropic's Messages API) using a user-supplied API key, matching the same "user brings their own credential" pattern `MetadataEnrichmentPlugin`'s Last.fm/Discogs keys already established — this app ships no embedded key of its own.

## Where it lives

`Omnis-Plugins/lib/ai_playlist_plugin.dart`

## Implements

- [[IAIProvider]]

## Serves

- [[43 - AI]]
