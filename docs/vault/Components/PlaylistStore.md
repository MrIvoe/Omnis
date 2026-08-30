---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# PlaylistStore

Persists named playlists to disk — the same load/save shape as `LibraryStore`: one JSON file in the app's documents directory, and the caller owns the in-memory playlist list and decides when to call `save()`. Also provides the M3U/PLS import and export helpers (`exportM3U`, `importM3U`, `exportPLS`, plus CSV/JSON export results), which report how many entries were written/matched versus skipped (a streaming-only track with no local file, or a track id no longer in the library).

## Where it lives

`lib/core/playlist_store.dart`

## Depends on

*(none — no dependency on another core singleton)*

## Serves

*(fill in during cross-linking pass)*
