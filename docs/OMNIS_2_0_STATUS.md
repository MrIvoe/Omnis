# Omnis 2.0 — Progress At a Glance

> A compact, skimmable snapshot of build progress across the 50 tracked
> feature areas, regenerated from [OMNIS_2_0_FINISHED_TASK.md](OMNIS_2_0_FINISHED_TASK.md)
> (the authoritative build log — every claim below traces back to a
> dated entry there, with the tests/commits behind it). This file
> answers "how far along is this, roughly" at a glance; that one
> answers "what exactly changed and why" in full engineering detail.
>
> Last regenerated: 2026-08-16 (item 28 closed).

## Overall

| ✅ Solid | 🟢 Solid, unverified | 🟡 Partial / in progress | ⬜ Not started |
|---|---|---|---|
| 8 | 8 | 34 | 0 |

### Estimated completion: ~71% (≈29% left to build)

A rough, weighted estimate — not a precise metric, since "partial"
areas vary in how much is actually left: ✅ counts as 100% done, 🟢
counts as 90% (fully built, only live-service verification pending),
🟡 counts as 60% (real, working functionality exists, but named gaps
remain), ⬜ counts as 0%. `(8×100 + 8×90 + 34×60 + 0×0) / 50 ≈ 71%`.
This will shift as items close out and as new gaps get discovered
mid-build; it's refreshed alongside the rest of this file.

**Every one of the 50 tracked areas already has real, working
functionality — none are starting from zero.** The remaining work is
closing specific named gaps inside already-functional systems (a
missing condition type, an unverified live-server round-trip, a
smarter algorithm), not building whole new systems from scratch. There
is no fixed ship date — this is continuous, incremental hardening —
but the shape of what's left is narrow and well-enumerated, not open-ended.

**Legend**
- ✅ **Solid** — feature-complete and hardened, no known named gaps left in the tracker.
- 🟢 **Solid, unverified** — fully implemented, but not yet exercised against a real external service/device (no live account/server available this session).
- 🟡 **Partial / in progress** — real, working functionality exists; specific named gaps remain, listed in the build log.
- ⬜ **Not started** — no real implementation yet.

---

## Phase 1 — Reliability

| # | Item | Status |
|---|------|--------|
| 1 | Playback engine | 🟡 Core playback (gapless, crossfade, speed/pitch, shuffle/repeat) works end-to-end; the bigger Queue/Output/Session controller split is still owed |
| 2 | Queue | 🟡 Manual queue, play-next, reorder, history/snapshots, cleanup, and now smart/rule-based continuation (similar track/artist, same genre/mood/album) all real; queue rules/exclusions and multiple queue sources not started |
| 3 | Recovery | ✅ Watchdog + crash/power-loss recovery wired end-to-end |
| 4 | Database | 🟡 Atomic writes, corruption detection, schema versioning, and scheduled backups all real; still JSON files, no indexed DB or multi-source libraries |
| 5 | Library scanning | 🟡 Incremental rescan, desktop filesystem watcher, and scheduled background scans all real; no fingerprint-based track identity |
| 6 | Persistence | ✅ Crash-safe playback/library/settings persistence |
| 7 | OS media integration | 🟡 Windows SMTC + lock-screen controls confirmed; other platforms not re-verified this session |
| 8 | Error handling | 🟡 Decoder auto-skip, plugin sandboxing, stranded-dialog fixes done; no full failure-mode audit yet |
| 9 | Tests | 🟡 1291 tests passing, `flutter analyze` clean; `AudioEngine` itself still lacks an injectable test seam |

## Phase 2 — Library

| # | Item | Status |
|---|------|--------|
| 10 | Search | 🟡 Real full-text + field qualifiers (`rating:`, `bpm:`, `missing:`, etc.), built this project from a genuine 0% start |
| 11 | Metadata | 🟡 MusicBrainz/Last.fm enrichment, pre-existing and real |
| 12 | Artwork | 🟡 Embedded + MediaStore artwork; bulk "look up artwork for the whole library" added |
| 13 | Playlists | 🟡 Static playlists with M3U/PLS/XSPF/CSV/JSON export, fairly complete |
| 14 | Favorites | 🟡 Real, wired into per-track and bulk actions |
| 15 | Ratings | 🟡 Half-star precision, calculated album/artist averages; built from a genuine 0% start |
| 16 | History | ✅ Play history, skip tracking, completion rate, favorite/rated aggregation — no further named gaps |
| 17 | Tag editor | 🟡 ID3/Vorbis/MP4 editing, undo, find/replace, virtual/calculated tags, composer now modeled/searchable too — no further named gaps within Library Health Center scope |

## Phase 3 — Audio

| # | Item | Status |
|---|------|--------|
| 18 | DSP pipeline | 🟡 Flat named-multiplier gain composition; not yet the spec's staged, independently-reorderable pipeline |
| 19 | ReplayGain | 🟡 Tag-based gain + user preamp; no on-device loudness analysis |
| 20 | EQ | 🟡 Real Android hardware EQ + a virtual trim elsewhere, with per-artist/album profiles and now a selectable 3/5/10-band count too; no parametric EQ (needs a native platform channel this project doesn't have) |
| 21 | Output devices | 🟡 Real device listing/selection plus per-device volume memory; exclusive/bit-perfect mode partial |
| 22 | Bit-perfect | 🟡 Informational half fully real now (every recognized format/extension, including bare ADTS AAC); no verified bit-perfect output path |
| 23 | Audio analysis | 🟡 Real BPM/key/mood/genre via a self-hosted Essentia service (user must run it — not bundled) |

## Phase 4 — Plugin platform

| # | Item | Status |
|---|------|--------|
| 24 | Capability interfaces | ✅ Typed `ServiceRegistry`, 9 capability interfaces |
| 25 | Plugin lifecycle | ✅ Real sandboxing, health tracking, deterministic init ordering |
| 26 | Dependency resolution | 🟡 Bundled-plugin ordering solid; missing external dependencies now offer a real one-tap Install when the catalog has them — no further named gaps |
| 27 | Permissions | ✅ Manifest permissions map to real `dart_eval` grants, shown before any plugin code runs |
| 28 | Plugin health | ✅ Reactive health records, per-plugin retry/reset, a dedicated health-center page, and background heartbeat monitoring for both external and bundled/in-process plugins — no further named gaps |
| 29 | Plugin updates | 🟡 Real update detection plus automatic/background checking; built from a genuine 0% start |
| 30 | Marketplace/catalog | ✅ Real permission-confirmation install flow against a fetched `catalog.json` |

## Phase 5 — Connectivity

| # | Item | Status |
|---|------|--------|
| 31 | OpenSubsonic | 🟢 Real client built; unverified against a live server (none available this session) |
| 32 | Navidrome | 🟢 Works via the OpenSubsonic client in principle; unverified live |
| 33 | Jellyfin | 🟢 Real REST client built; unverified against a live server |
| 34 | Plex | 🟢 Real Plex Media Server client built; unverified live |
| 35 | DLNA/UPnP | 🟡 Real SSDP+SOAP/DIDL-Lite client; built from a genuine 0% start |
| 36 | Spotify | 🟢 Real PKCE OAuth, playlist import, Connect remote control; unverified live |
| 37 | YouTube | 🟢 Real OAuth, playlist import + search, in-app playback; unverified live |
| 38 | Other providers | 🟡 Emby closed (self-hostable, keyless); other self-hosted providers not attempted |

## Phase 6 — Discovery

| # | Item | Status |
|---|------|--------|
| 39 | Recommendations | 🟡 Data-driven "Moods" algorithm, Similar Artist, Deep Cuts, and now New Releases presets all real; Daily/Weekly Mix, Discovery, Energy Flow, and a provider-neutral recommendation framework still open |
| 40 | Sonic similarity | 🟡 Real acoustic-feature distance/similarity scoring on top of Essentia's extracted features |
| 41 | Radio | 🟡 Real client to the free Radio Browser directory; built from a genuine 0% start |
| 42 | Smart playlists | 🟡 Real rule engine incl. BPM/duration/bitrate/codec conditions and JSON import/export — no further named gaps |
| 43 | AI | 🟡 Real playlist generation and natural language search from a genuine 0% start; conversational assistant/voice control/tagging still 0% |
| 44 | Themes | 🟡 Real declarative theme engine (URL/file import, closed-schema colors/typography); named-preset parity closed, more presets possible |

## Phase 7 — Advanced UX

| # | Item | Status |
|---|------|--------|
| 45 | Layout builder | 🟢 Solid for Now Playing (real drag-and-drop editor, 6 bundled layouts); Home now has reorder/hide too, but no free-form widget canvas or sidebar |
| 46 | Car mode | 🟢 Dedicated minimal layout plus real GPS-speed auto-activation |
| 47 | TV mode | 🟡 New TV-optimized Now Playing layout; built from a genuine 0% start |
| 48 | Accessibility | 🟡 Keyboard shortcuts, tooltips, `Semantics` pass, reduce-motion/transparency, and now a Ctrl+K command palette (11 of 13 spec-named commands) all real; per-shortcut remapping and the "search everywhere" Ctrl+K overlay still open |
| 49 | Widgets | 🟡 Real interactive Android home-screen widget; built from a genuine 0% start |
| 50 | Automation | 🟡 GPS-speed and Bluetooth-connect triggers (now including a Car Mode layout switch), plus time-based playback scheduling; a general rules engine still deferred |

---

## How this gets updated

Every increment closes one named gap, adds tests proving it, and gets
one line in [OMNIS_2_0_FINISHED_TASK.md](OMNIS_2_0_FINISHED_TASK.md)'s
build log the same day. This file is a hand-rolled digest of that
log's current state, refreshed alongside it — treat the build log as
the source of truth if the two ever disagree.
