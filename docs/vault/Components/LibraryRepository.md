---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# LibraryRepository

The single in-memory source of truth for the persisted library, caching what `LibraryStore` reads from disk so `home_page`/`playlist_page`/`library_page` don't each independently re-read and re-parse the whole library JSON on every `initState`. `load()` resolves once and caches the result; concurrent callers during the first load share the same in-flight `Future` rather than issuing separate disk reads. `save()` updates the in-memory copy, notifies listeners, and persists — `playlist_page.dart` still listens live so a favorite toggled elsewhere shows up there without a reload trigger, but the bundled Home dashboard and mood-player plugins (moved to the separate `omnis_plugins` package) read through `PluginContext.loadLibraryTracks()` instead and no longer get that live-update guarantee.

## Where it lives

`lib/core/library_repository.dart`

## Depends on

*(none — no dependency on another core singleton; wraps `LibraryStore`)*

## Serves

- [[4 - Database]] (atomic-write/schema-versioning conventions)
- [[6 - Persistence]] (library persistence)
