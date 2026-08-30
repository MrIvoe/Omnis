# Omnis 2.0 — Progress At a Glance

**Superseded on 2026-08-29** by the Obsidian architecture vault —
see [`docs/vault/README.md`](vault/README.md), starting from
[`docs/vault/00-Hubs/`](vault/00-Hubs/) for the same per-phase feature
status this file used to hold, now as linked notes instead of one flat
table. This file's prior content is preserved in git history.
| 4 | Database | 🟡 Atomic writes, corruption detection, schema versioning, and scheduled backups all real; still JSON files, no indexed DB or multi-source libraries |
| 5 | Library scanning | ✅ Incremental rescan, desktop filesystem watcher, scheduled background scans, and now content-fingerprint-based rename/move detection (a renamed file keeps its favorites/ratings/play history/playlist membership across every rescan trigger — the explicit "Add audio files" button, the desktop watcher, and the scheduled background scan — instead of silently losing them) — no further named gaps |
| 6 | Persistence | ✅ Crash-safe playback/library/settings persistence |
| 7 | OS media integration | 🟡 Windows SMTC + lock-screen controls confirmed; other platforms not re-verified this session |
| 8 | Error handling | 🟡 Decoder auto-skip, plugin sandboxing, stranded-dialog fixes done; no full failure-mode audit yet |
| 9 | Tests | 🟡 1291 tests passing, `flutter analyze` clean; `AudioEngine` itself still lacks an injectable test seam |

## Phase 2 — Library

| # | Item | Status |
|---|------|--------|
| 10 | Search | 🟡 Real full-text + field qualifiers (`rating:`, `bpm:`, `missing:`, etc.), built this project from a genuine 0% start; Library page now also has UI_SPEC §11's toggleable song-row metadata columns (Artist/Album/Year/Genre/Bitrate/Format/Rating/Play count/ReplayGain) — not reorderable spreadsheet columns, a scoped subset |
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
| 30 | Marketplace/catalog | ✅ Real permission-confirmation install flow against a fetched `catalog.json`; a bare `github.com/user/repo` URL now tries both `main` and `master` before failing (previously hardcoded to `main` only, so any `master`-default repo failed install with a misleading "missing omnis_plugin.yaml" error even though the file was really there) |

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
| 38 | Other providers | 🟡 Emby, Ampache, and Koel closed (all self-hostable, keyless); Apple Music/SoundCloud/Bandcamp/Tidal/Qobuz remain judged not tractable (closed/paid developer gates) |

## Phase 6 — Discovery

| # | Item | Status |
|---|------|--------|
| 39 | Recommendations | 🟡 Data-driven "Moods" algorithm, Similar Artist, Deep Cuts, New Releases, Daily/Weekly Mix presets, and now UI_SPEC §13's user-created custom moods (genre/mood-tag/tempo-range/rating-floor/recently-played-exclusion rules, plus §14's color/icon visual identity — Background/Artwork/Animation/Gradient/Sound-behavior deliberately not built) all real; Discovery, Energy Flow, and a provider-neutral recommendation framework still open |
| 40 | Sonic similarity | 🟡 Real acoustic-feature distance/similarity scoring on top of Essentia's extracted features |
| 41 | Radio | 🟡 Real client to the free Radio Browser directory; built from a genuine 0% start |
| 42 | Smart playlists | 🟡 Real rule engine incl. BPM/duration/bitrate/codec conditions and JSON import/export — no further named gaps |
| 43 | AI | 🟡 Real playlist generation and natural language search from a genuine 0% start; conversational assistant/voice control/tagging still 0% |
| 44 | Themes | 🟡 Real declarative theme engine (URL/file import, closed-schema colors/typography/icon-style) plus a full in-app visual editor (9 color pickers, font/scale/corner-radius/motion/icon-style controls, solid/gradient background editor, live preview, save-and-install); named-preset parity closed, more presets possible |

## Phase 7 — Advanced UX

| # | Item | Status |
|---|------|--------|
| 45 | Layout builder | 🟢 Solid for Now Playing (real drag-and-drop editor, 6 bundled layouts); Home now has reorder/hide too, and now UI_SPEC §3-5's pop-out sidebar (a global drawer, reachable via a menu button or Ctrl+B, pinning playlists/moods into user-editable, reorderable sections) — a free-form widget canvas and the sidebar's fuller mode-switching (Compact/Pinned/Auto-hide) remain open |
| 46 | Car mode | 🟢 Dedicated minimal layout plus real GPS-speed auto-activation |
| 47 | TV mode | 🟡 New TV-optimized Now Playing layout; built from a genuine 0% start |
| 48 | Accessibility | 🟡 Keyboard shortcuts (now with per-shortcut remapping and conflict detection), tooltips, `Semantics` pass, reduce-motion/transparency, and a Ctrl+K command palette (11 of 13 spec-named commands, now also §37's "search everywhere" overlay across Commands/Songs/Playlists/Moods) all real; Artists/Albums/Settings search-everywhere coverage and the 2 still-deferred commands are the remaining named gaps |
| 49 | Widgets | 🟡 Real interactive Android home-screen widget; built from a genuine 0% start |
| 50 | Automation | 🟡 GPS-speed and Bluetooth-connect triggers (now including a Car Mode layout switch), time-based playback scheduling, and now scheduled radio (a saved custom station); a general rules engine and scheduled podcasts still deferred |

---

## How this gets updated

Every increment closes one named gap, adds tests proving it, and gets
one line in [OMNIS_2_0_FINISHED_TASK.md](OMNIS_2_0_FINISHED_TASK.md)'s
build log the same day. This file is a hand-rolled digest of that
log's current state, refreshed alongside it — treat the build log as
the source of truth if the two ever disagree.
