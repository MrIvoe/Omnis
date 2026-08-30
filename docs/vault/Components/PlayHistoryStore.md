---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# PlayHistoryStore

Persists per-track play aggregates (`TrackPlayStats`: play count, last played, etc.) to their own JSON file so the Home dashboard's Recently Played / Most Played / Continue Listening sections work regardless of whether the optional `ScrobblePlugin` is installed — this is core, always-on infrastructure, not a plugin. Unlike `LibraryStore`/`LibraryRepository`, it deliberately keeps no in-memory cache: the file is small (a few numbers per track) so re-reading it on every call is cheap and sidesteps an entire class of stale-cache bug. Each stats entry decodes independently so one corrupted record can't wipe the whole history.

## Where it lives

`lib/core/play_history_store.dart`

## Depends on

*(none — no dependency on another core singleton)*

## Serves

- [[4 - Database]] (atomic-write/schema-versioning conventions)
- [[16 - History]]
