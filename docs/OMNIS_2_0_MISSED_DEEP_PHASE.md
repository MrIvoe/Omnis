# Omnis 2.0 — Missed / Deferred Items ("Deep Phase")

> **Purpose:** a running list of every gap, deferred decision, or
> documented limitation surfaced while building against
> [OMNIS_2_0_SPEC.md](OMNIS_2_0_SPEC.md), [OMNIS_2_0_UI_SPEC.md](OMNIS_2_0_UI_SPEC.md),
> and [OMNIS_2_0_PLUGINS.md](OMNIS_2_0_PLUGINS.md), that didn't get fixed
> in the pass that found it. [OMNIS_2_0_FINISHED_TASK.md](OMNIS_2_0_FINISHED_TASK.md)
> tracks what's *done*; this file tracks what's *known to still be
> missing* — the deliberate re-run pass mentioned in that tracker's own
> log works off this list, not just the phase table.
>
> Each entry names the spec section it traces to, why it wasn't done in
> the pass that found it (usually: real scope, needs hardware/an
> external account, or is a distinct unit of work), and enough context
> to pick it up later without re-deriving it.

---

## From Phase 1 (Reliability)

- **§51.2 — `AudioEngine` is still one large facade.** Split OS-integration
  and A-B repeat out into their own files/classes; the bigger split
  (`QueueController`, `OutputController`, `AudioSessionController`) is
  still undone. Reason: touching the crossfade/queue state machine
  without a real device to smoke-test on (this dev environment's Windows
  build is blocked — see `docs/BUILDING.md`) is a correctness risk not
  worth taking blind.
- **§7 — Queue engine depth.** No queue history/snapshots, no
  smart/rule-based continuation (mood/artist/genre/similar-track
  auto-continuation), no advanced shuffle modes beyond what
  `ShuffleRepeatPlugin` already does. `playNext()` exists on `AudioEngine`
  but isn't exposed through `PluginContext` (a cross-repo
  `omnis_plugin_api` change) or a track context menu yet.
- **§4/§41 — Real indexed database.** Every store is still a JSON file
  (now atomic-write-safe and per-entry-decode-safe, but not an indexed
  DB). No multi-source libraries, no SQL-like query layer, no schema
  migration system, no scheduled integrity check.
- **§5 — Scanning depth.** No filesystem watchers, no scheduled scans, no
  duplicate-file detection beyond the Library page's own manual cleanup
  tool, no content-fingerprint/hash-based track identity (tracks are
  still identified primarily by path — moving a library folder still
  loses history/favorites/ratings linkage).
- **§43 — `AudioEngine` itself has no direct test coverage.** Queue
  mutation, gapless, shuffle/repeat, and the crossfade math beyond the
  pure `crossfadeVolumes` function are untested. Needs either a real
  device/CI runner or an injectable-player seam of its own (the
  `PlaybackEngine` interface built this cycle only covers what
  `PlaybackWatchdog`/`PlaybackRecovery` need, not the whole engine).
- **§60 — Failure-mode audit is "as found," not exhaustive.** Several real
  instances of "one bad entry breaks everything" were found and fixed
  (media scanner, library bulk-dialogs, three JSON stores, two
  concurrency races) by re-reading code that had just been touched for
  other reasons — this was never a systematic sweep of every subsystem
  against the spec's own failure-mode checklist.
- **Testing infrastructure gap, not a feature gap:** this environment's
  `flutter test` cannot safely exercise `file_picker` (a real native
  dialog can open even under `flutter test` — confirmed, left genuinely
  hung processes) or construct a real `AudioEngine`/`AudioPlayer` inside
  a widget test (also hangs, root cause not fully identified past two
  fixed causes). `lib/ui/library_page.dart` has **no widget test file at
  all** as a result — every UI wired into it (search, favorites, ratings)
  is verified by `flutter analyze` + the underlying logic's own unit
  tests only, never an actual widget-tree interaction test.

## From Phase 2 (Library)

- **§6 — Search is a genuine MVP, not the full spec.** `filterTracks`
  supports free text + `artist:`/`album:`/`genre:`/`title:`/`mood:`/
  `year:`. Missing: quoted multi-word field values (`album:"greatest
  hits"` currently splits into two AND'd terms), `rating:`/`bpm:`/
  `format:`/`bitrate:`/`lyrics:`/`missing:`/`duplicate:` operators
  (each needs a feature/data source — several now exist as of this
  session, e.g. ratings, but aren't wired into search yet), natural-
  language queries, and **no search scope beyond the Library page** — no
  global Ctrl+K command palette (§37/§38) searching settings/commands/
  playlists/moods in one place.
- **§9 — `rating:>=4` search/smart-playlist operator not wired.**
  `RatingsPlugin.ratedAtLeast()` exists specifically as the building
  block for this, but `filterTracks` is a pure `BaseTrack`-only function
  with no plugin access — wiring it in means either the caller
  pre-joining ratings onto tracks before calling `filterTracks`, or a
  deliberate design decision about whether `filterTracks` should gain a
  plugin dependency at all.
- **§9 — No bulk "rate selected" action.** Favorites has a one-tap bulk
  toggle in selection mode; ratings don't, because a specific 1-5 value
  doesn't fit that same one-tap pattern. A bulk rating dialog (rate N
  selected tracks at once) is a reasonable follow-up.
- **§13 — Playlist folders/groups, collaborative playlists, XSPF/PLS
  import/export** don't exist (M3U/M3U8 does, plus a full
  `SmartPlaylistPlugin`).
- **§11 — Metadata provider framework.** Only `MetadataEnrichmentPlugin`
  (MusicBrainz + optional Last.fm) exists — not the `IMetadataProvider`-
  pluggable-provider framework the spec describes (Discogs/Deezer/Genius
  etc. as swappable alternatives a user could install instead).
- **§12 — Artwork provider framework.** Embedded artwork, Android
  MediaStore artwork, and `ArtistImagePlugin` (Deezer search) exist —
  no `IArtworkProvider` framework (Cover Art Archive/Fanart.tv lookup),
  no manual/drag-drop artwork override.
- **§20 — Guided "Music Library Cleanup" report.** The spec describes a
  one-button "Analyze Library" producing a report ("1,421 missing
  artwork, 832 inconsistent artists, ..." style) with guided cleanup.
  `library_page.dart` has a narrower duplicate/short-track cleanup tool
  today, not this broader analysis. No undo/backup/restore for tag
  edits either.

---

## Cross-cutting gaps expected before Phase 3+ auditing even started

These aren't specific to one phase — flagging them here so the deep-phase
re-run pass checks for them everywhere, not just where they were first
noticed:

- **The "one bad entry breaks everything" bug class** was found in 5+
  places this cycle purely by re-reading code already being touched for
  other reasons — not a systematic search. Any future JSON-blob-per-
  plugin storage (matching `RatingsPlugin`'s own pattern) should get the
  per-entry-decode treatment from the start, and anything *not* built
  this cycle should be checked for the same issue before being trusted.
- **Cross-repo plugin work (Omnis-Plugins) is a materially bigger unit of
  work than an in-repo fix** — new plugin, its own tests, a version bump
  + tag + push, then a ref bump + `bundled_plugins.dart` registration +
  UI wiring back in the main repo. Expect this pattern to recur for
  every Phase 3-7 item that's plugin-shaped and currently missing.
- **Real external accounts/hardware this dev environment cannot verify
  against**: Spotify/YouTube OAuth flows, Bluetooth devices, GPS
  movement, a real Android device (hardware EQ, ringtone-setting,
  visualizer capture), a real Windows build (SMTC media controls) are
  all implemented against documented APIs but explicitly marked
  unverified in `Omnis-Plugins/README.md`'s own table. Building *more*
  features on top of these doesn't change that underlying verification
  gap — it should be called out per-item, not silently assumed away.

---

## Phase 3–7 audit (pending)

*Populated by the parallel audit pass launched 2026-08-13, before any
Phase 3+ work started. Each phase's real gaps get appended here as the
audits return, then the tracker's own phase tables get updated from
this.*
