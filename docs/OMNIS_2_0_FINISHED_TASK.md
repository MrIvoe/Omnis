# Omnis 2.0 — Build Progress Tracker

> **Status:** Live build tracker for the Omnis 2.0 implementation.
> This document tracks what has been built, what is in progress, and what
> remains. It is the single source of truth for build progress.
>
> **References (read-only, never edited):**
> 1. [OMNIS_2_0_SPEC.md](OMNIS_2_0_SPEC.md) — product specification
> 2. [OMNIS_2_0_UI_SPEC.md](OMNIS_2_0_UI_SPEC.md) — UI/UX specification
> 3. [OMNIS_2_0_PLUGINS.md](OMNIS_2_0_PLUGINS.md) — plugin architecture & developer guide

---

## Phase 1 — Reliability

| # | Item | Status |
|---|------|--------|
| 1 | Playback engine | 🟡 In progress — `AudioEngine` covers play/pause/seek/next/prev/gapless/crossfade/speed/pitch/skip-silence/shuffle/repeat/volume. Started §51.2's split (OS media-session integration → `playback_os_integration.dart`; A-B repeat → a decoupled, unit-tested `AbRepeatController`), shrinking the file from 1208 to ~880 lines. Also introduced `PlaybackEngine` (§51.3 capability interface) — `AudioEngine` now `implements` it, and `PlaybackWatchdog`/`PlaybackRecovery` depend on the interface, not the concrete class. Still owes the bigger `QueueController`/`OutputController`/`AudioSessionController` split — queue mutation and the crossfade state machine are still interleaved in the facade, and splitting those safely needs a real-device smoke test this environment can't do (Windows build is blocked — see `docs/BUILDING.md`). |
| 2 | Queue | 🟡 In progress — manual queue (add/remove/reorder via `setQueue`/`addTrack`/`removeTrack`/`playAt`), shuffle, repeat. Added `playNext()` (§7's "play next" vs "add to queue" distinction) to the engine — not yet wired into `PluginContext` (a cross-repo `omnis_plugin_api` change) or a track context menu in the UI. Still no queue history/snapshots or smart/rule-based continuation. |
| 3 | Recovery | ✅ Solid for Phase 1 — `PlaybackWatchdog` (stuck loading, position stall, impossible position, decoder exceptions, output loss) + `PlaybackRecovery` (reload → retry → advance → stop) + `RecoveryJournal` (crash/power-loss resume) are now wired end-to-end in `MainCore`: watchdog starts with the engine, counters reset on a healthy track start, journal saves on pause/track-change/20s-heartbeat, and a "Resume where you left off?" prompt offers restoration on launch. `RecoveryJournal.save()`/`clear()` also now serialize onto one queue — they're called from several independent unawaited sites, and two concurrent writes were racing on the same `.tmp` path. Untrusted-plugin isolation (isolates) is still future work per the plugin architecture doc. |
| 4 | Database | 🟡 In progress — still JSON-file storage, not an indexed DB. §41's "atomic writes" requirement is now real across every store that persists user-authored/derived data: `LibraryStore` (atomic + debounced, prior work), `RecoveryJournal` (atomic, this session), and `PlaylistStore`/`PlayHistoryStore` (atomic, this session) — all write to a sibling `.tmp` file and rename over the real path, so a crash mid-write can no longer corrupt/truncate any of them. §41 also calls for "corruption detection" — closed a related, more severe gap this session: `LibraryStore`/`PlaylistStore`/`PlayHistoryStore` all decoded their JSON as one bulk `.map(...).toList()`/`Map.map(...)`, so a *single* malformed record (one bad track, one bad playlist, one bad stats entry) threw, was caught by the outer try/catch, and silently wiped the *entire* store back to empty — for `PlaylistStore` specifically, that means losing every hand-curated playlist with nothing to regenerate them from. All three now decode entry-by-entry and skip only the bad one, matching the per-entry guard `PlaybackState.fromJson` already had for its queue. `RemoteTextStore` (theme/layout installs) deliberately left as-is — each install is one independent file, not shared mutable state, so the blast radius of an interrupted write is already contained. Added `lib/core/backup_service.dart` (§41/§48 "automatic backup... with validation before overwriting anything") — bundles library/playlists/play-history/recovery-journal into one zip with a manifest, and `restoreBackup()` validates the *entire* archive (manifest present + recognized version, every declared file present, every declared file's JSON syntactically valid) before writing a single byte — a bad backup touches nothing, never a partial apply. Deliberately scoped to just those four store files, not `AppSettings`/plugin credentials (that's closer to §47 "Universal export," a materially bigger, separate piece of work). Wired into Settings as a new "Backup" category (`lib/ui/settings/backup_settings_page.dart`), including the search index — "Backup Omnis"/"Restore Omnis" are now searchable and reachable from the running app, not just implemented in isolation. Restore refreshes `LibraryRepository`'s in-memory cache immediately; playlists/history/journal aren't cached the same way, so the UI is upfront that a restart is needed for those to fully take effect, rather than silently leaving stale in-memory state. Still no multi-source libraries, no SQL-like query layer, no migration system. |
| 5 | Library scanning | 🟡 In progress — local-folder `MediaScanner` scan/rescan exists (pre-existing), with mtime-based incremental rescan and per-entry directory-walk error tolerance already in place. Fixed a gap this session: a file that vanished *after* being listed but *before* being stat'd (deleted mid-scan, removable storage unmounting) threw out of `file.lastModified()` and aborted the entire scan — now skipped like any other unreadable entry. Still no filesystem watchers, scheduled scans, duplicate detection, or fingerprint-based identity (§5) — tracks are still identified primarily by path. |
| 6 | Persistence | ✅ Solid for Phase 1 — playback state now survives crash/power-loss via `RecoveryJournal` (atomic writes, staleness cutoff); library and plugin-installer writes are atomic. Settings persistence (`AppSettings`) predates this session and is unchanged. |
| 7 | OS media integration | 🟡 In progress — Windows SMTC + `audio_service` notification/lock-screen controls exist (pre-existing). Not verified this session on macOS/Linux/mobile OS media session behavior. |
| 8 | Error handling | 🟡 In progress — decoder-error auto-skip, plugin-call sandboxing, plugin-installer download/zip-bomb size limits, a per-file scan failure no longer aborting the whole library scan, and (new) `library_page.dart`'s four `barrierDismissible: false` bulk-action dialogs (enrich, analyze, auto-tag, measure durations) can no longer be permanently stranded on screen — any exception mid-batch is now caught, the dialog is always dismissed, and (for `_measureDurations`) the "already running" guard flag always resets instead of silently disabling the feature for the rest of the session. Verified the metadata-enrichment and audio-analysis providers were already internally defensive (never throw) before treating this as a real gap — the actual bug was the dialogs' own lack of a `finally`, not the providers. The spec's full failure-mode checklist hasn't been run exhaustively against every subsystem — this is audit-as-you-go, not a completed sweep. |
| 9 | Tests | 🟡 In progress, meaningfully better — 478 tests passing (`flutter test`, `flutter analyze` clean; started this session at 433). New this session: `recovery_journal_test.dart`, a `MainCore` resumable-state group, `ab_repeat_controller_test.dart` (10 tests), and — via the new `PlaybackEngine` interface + `test/fakes/fake_playback_engine.dart` — `playback_watchdog_test.dart` (13 tests: every detection path) and `playback_recovery_test.dart` (10 tests: every failure-type branch, retry-then-advance behavior, custom retry limits). The recovery system, arguably the single most safety-critical subsystem per §43 of the spec, now has direct coverage for the first time. Remaining gap: `AudioEngine` itself (queue mutation, crossfade math beyond the pure `crossfadeVolumes` function, gapless/shuffle/repeat) is still untested — it needs either a real device/CI runner or an injectable-player seam of its own. |

> **Note on Phases 2–7 below:** this repo already had a mature Omnis app
> (library/playlist/settings pages, a plugin marketplace-style installer,
> a declarative theme/layout system, an accessibility pass, ~20 bundled
> plugins in `omnis_plugins`) before these Omnis 2.0 reference docs were
> added. The blanket "Not started" statuses below predate an actual
> audit against that existing code and should not be trusted as-is —
> most items likely have *some* pre-existing coverage. They need a
> dedicated audit pass (mapping existing code to each spec item) before
> being graded individually; that audit hasn't happened yet.

## Phase 2 — Library

| # | Item | Status |
|---|------|--------|
| 10 | Search | ⬜ Not started |
| 11 | Metadata | ⬜ Not started |
| 12 | Artwork | ⬜ Not started |
| 13 | Playlists | ⬜ Not started |
| 14 | Favorites | ⬜ Not started |
| 15 | Ratings | ⬜ Not started |
| 16 | History | ⬜ Not started |
| 17 | Tag editor | ⬜ Not started |

## Phase 3 — Audio

| # | Item | Status |
|---|------|--------|
| 18 | DSP pipeline | ⬜ Not started |
| 19 | ReplayGain | ⬜ Not started |
| 20 | EQ | ⬜ Not started |
| 21 | Output devices | ⬜ Not started |
| 22 | Bit-perfect | ⬜ Not started |
| 23 | Audio analysis | ⬜ Not started |

## Phase 4 — Plugin platform

| # | Item | Status |
|---|------|--------|
| 24 | Capability interfaces | ⬜ Not started |
| 25 | Plugin lifecycle | ⬜ Not started |
| 26 | Dependency resolution | ⬜ Not started |
| 27 | Permissions | ⬜ Not started |
| 28 | Plugin health | ⬜ Not started |
| 29 | Plugin updates | ⬜ Not started |
| 30 | Marketplace/catalog | ⬜ Not started |

## Phase 5 — Connectivity

| # | Item | Status |
|---|------|--------|
| 31 | OpenSubsonic | ⬜ Not started |
| 32 | Navidrome | ⬜ Not started |
| 33 | Jellyfin | ⬜ Not started |
| 34 | Plex | ⬜ Not started |
| 35 | DLNA/UPnP | ⬜ Not started |
| 36 | Spotify | ⬜ Not started |
| 37 | YouTube | ⬜ Not started |
| 38 | Other providers | ⬜ Not started |

## Phase 6 — Discovery

| # | Item | Status |
|---|------|--------|
| 39 | Recommendations | ⬜ Not started |
| 40 | Sonic similarity | ⬜ Not started |
| 41 | Radio | ⬜ Not started |
| 42 | Smart playlists | ⬜ Not started |
| 43 | AI | ⬜ Not started |

## Phase 7 — Advanced UX

| # | Item | Status |
|---|------|--------|
| 44 | Themes | ⬜ Not started |
| 45 | Layout builder | ⬜ Not started |
| 46 | Car mode | ⬜ Not started |
| 47 | TV mode | ⬜ Not started |
| 48 | Accessibility | ⬜ Not started |
| 49 | Widgets | ⬜ Not started |
| 50 | Automation | ⬜ Not started |

---

## Build log

| Date | Phase | Item | Notes |
|------|-------|------|-------|
| 2026-08-12 | — | Tracker created | Build tracker initialized. |
| 2026-08-12 | 1 | Recovery, Persistence | Wired `PlaybackWatchdog`/`PlaybackRecovery`/`RecoveryJournal` (built in a prior session but never connected) into `MainCore`: watchdog now actually starts, failure counters reset on a healthy track, the journal saves on pause/track-change/20s heartbeat, and `HomePage` offers a "Resume where you left off?" prompt on launch. Removed a stray leftover file (`lib/core/playback_d`, an interrupted write from the prior session). |
| 2026-08-12 | 1 | Tests | Added `test/recovery_journal_test.dart` and a resumable-state test group in `test/main_core_test.dart`. Full suite: 445 passing, `flutter analyze` clean. |
| 2026-08-12 | 1 | Playback engine | Split `AudioEngine` per §51.2: extracted `OmnisAudioHandler`/`OmnisWindowsMediaHandler` (audio_service + Windows SMTC) into `lib/core/playback_os_integration.dart` with zero behavior change, and extracted A-B repeat into `lib/core/ab_repeat_controller.dart` as a player-decoupled, unit-testable `AbRepeatController`. Added `test/ab_repeat_controller_test.dart` (10 tests). |
| 2026-08-12 | 2 | Queue | Added `AudioEngine.playNext()` — inserts right after the current track, distinct from `addTrack()` (append) per §7. Not yet exposed through `PluginContext` or a UI context menu. |
| 2026-08-12 | 1, 2 | Tests | Full suite: 455 passing, `flutter analyze` clean. |
| 2026-08-12 | 1, 9 | Playback engine, Tests | Introduced `lib/core/playback_engine.dart` (`PlaybackEngine`, §51.3 capability interface); `AudioEngine implements PlaybackEngine`; `PlaybackWatchdog`/`PlaybackRecovery` now depend on the interface instead of the concrete engine. Added `test/fakes/fake_playback_engine.dart`, `test/playback_watchdog_test.dart` (13 tests), `test/playback_recovery_test.dart` (10 tests) — first direct unit coverage for the watchdog/recovery system. Full suite: 478 passing, `flutter analyze` clean. |
| 2026-08-12 | — | (checkpoint) | Committed (`c38f560`): recovery/journal wiring, resume prompt, AudioEngine split (OS integration, A-B repeat, PlaybackEngine interface), playNext(), and all associated tests. |
| 2026-08-12 | 4 | Database | Applied the same atomic-write fix (`.tmp` + rename) `LibraryStore`/`RecoveryJournal` already had to `PlaylistStore.save()` and `PlayHistoryStore._save()` — both were still doing a bare `writeAsString`, i.e. still corruptible by a crash mid-write, and `PlayHistoryStore._save()` in particular fires on every pause/track-change (not a rare event). Added atomic-write tests to `test/playlist_store_test.dart` and `test/play_history_store_test.dart`. Full suite: 480 passing, `flutter analyze` clean. |
| 2026-08-12 | 5, 8 | Library scanning, Error handling | `MediaScanner._trackForFile` now catches per-file failures (`file.lastModified()` throwing when a file vanishes mid-scan) instead of letting them propagate out of the `Future.wait` batch and abort the whole scan — the exact "one bad entry breaks everything" pattern the directory-listing stream already had a fix and regression tests for, one step later in the pipeline. Added a regression test to `test/media_scanner_test.dart`. Full suite: 481 passing, `flutter analyze` clean. |
| 2026-08-12 | 8 | Error handling | Wrapped `library_page.dart`'s bulk enrich/analyze/auto-tag/measure-durations loops in try/catch/finally — all four drive a `barrierDismissible: false` progress dialog with no prior exception safety net, so any mid-batch throw left the user stuck looking at an undismissable dialog (force-close-the-app territory), and for `_measureDurations` specifically also left `_measurementInProgress` stuck `true`, silently disabling the feature for the rest of the session. No new tests — a widget-test harness for these private, deeply-stateful dialog flows didn't already exist and standing one up was disproportionate to this fix's size; verified via `flutter analyze` + the existing suite staying green. Full suite: 481 passing. |
| 2026-08-12 | 4 | Database | Fixed a more severe instance of the same "one bad entry breaks everything" pattern: `LibraryStore`/`PlaylistStore`/`PlayHistoryStore` all decoded their persisted JSON in one bulk `.map(...)`, so a single malformed record wiped the *entire* store (library, playlists, or history) back to empty, not just that one entry — `PlaylistStore` in particular meant losing every hand-curated playlist. All three now decode per-entry, matching `PlaybackState.fromJson`'s existing per-entry guard for its queue. Added a regression test to each store's test file. Full suite: 484 passing, `flutter analyze` clean. |
| 2026-08-12 | 3, 4 | Recovery, Database | Found and fixed two related concurrency bugs while re-reading the stores just hardened above: (1) `RecoveryJournal.save()`/`clear()` had no serialization — two calls close together (a pause and the 20s heartbeat) raced on the same `.tmp` path. (2) Worse: `PlayHistoryStore.recordPlay`/`recordPosition` each do their own full load→mutate→save cycle, and `MainCore` fires both unawaited from independent stream listeners around every track change — two concurrent calls could each load the same base state and whichever saved last silently discarded the other's update (a lost play count or lost position, not just a file-write race). Both stores now serialize their operations onto one queue, so each call sees the previous one's committed result. Added regression tests exercising real (unawaited, `Future.wait`-joined) concurrency, not just sequential calls. Full suite: 487 passing, `flutter analyze` clean. |
| 2026-08-12 | 4 | Database | Added `lib/core/backup_service.dart` — one-click backup/restore of the library/playlists/play-history/recovery-journal, per §41/§48's "automatic backup... with validation before overwriting anything." `restoreBackup()` validates the entire archive (manifest present + recognized version, every declared file present, every declared file's JSON well-formed) before writing anything; a bad backup is provably all-or-nothing, verified by a dedicated test that a *valid* file declared alongside a *corrupt* one still gets rejected and written nowhere. 12 new tests in `test/backup_service_test.dart`. Deliberately no Settings UI yet — flagged as a distinct follow-up task. Full suite: 499 passing, `flutter analyze` clean. |
| 2026-08-13 | 4 | Database | Wired backup/restore into a new Settings → Backup page (`lib/ui/settings/backup_settings_page.dart`), including the search index — genuinely reachable and searchable in the running app, not just a service with tests. Restore refreshes `LibraryRepository`'s in-memory cache; other stores need a restart, and the UI says so rather than pretending the change is fully live. Found and fixed a real bug while wiring this up: `_restore()` called `FilePicker.platform.pickFiles()` *outside* its try/catch, so a real picker failure (permission denied, plugin unavailable) would have thrown uncaught instead of failing soft like `_backup()` already did — now the whole method is one try/catch. **Testing note**: discovered mid-session that `file_picker`'s Windows implementation can attempt a real native dialog even under `flutter test` (left genuinely hung `dart.exe` processes during investigation) — no test in this app's suite exercises `file_picker` interactively for that reason, and `backup_settings_page_test.dart` follows the same restriction (rendering-only). `BackupService` itself already has full interactive-equivalent coverage via direct calls, so the risky UI path doesn't lose real safety-net coverage. Full suite: 502 passing, `flutter analyze` clean. |