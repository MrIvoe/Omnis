---
type: component
kind: core-singleton
repo: Omnis
status: stable
---

# RecoveryJournal

Persists `PlaybackState` snapshots for crash recovery and queue restoration (spec §42). Writes are atomic — a sibling temp file is written and renamed over the real file only once complete, so a crash or power loss mid-write leaves the previous good snapshot intact rather than a half-written one. A corrupt or absent file makes `load()` return `null` ("nothing to resume"), writes are best-effort (a failure is logged, never thrown — losing the journal must never take down playback or the UI), and `removeIfStale` lets a caller drop snapshots older than a cutoff so the journal never resurrects a stale queue. Every `save()` call is chained onto one pending-write future, because [[MainCore]] fires saves from several independent, unawaited call sites (pause, track change, a 20s heartbeat) that would otherwise race on the same temp path.

## Where it lives

`lib/core/recovery_journal.dart`

## Depends on

*(none — no dependency on another core singleton)*

## Serves

*(fill in during cross-linking pass)*
