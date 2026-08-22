# Omnis "Music Player Kernel + Plugins" Re-architecture Plan

## Goal

With zero plugins installed, Omnis is a minimal, beautiful, lightweight
music player: basic playback of local files, nothing more. Every
feature beyond that — browsing conveniences, smart/AI playlists, DJ
tools, karaoke, tag editing, file organization, streaming, visualizer,
equalizer, extra layouts, new tabs/windows/buttons — comes from a
plugin, bundled or downloadable.

Read directly (not assumed) for this plan: `lib/ui/home_page.dart`,
`lib/ui/home_navigation.dart`, `lib/ui/plugin_slot_view.dart`,
`lib/core/plugin_manager.dart`, `lib/core/plugin_interface.dart`,
`lib/core/service_registry.dart`,
`packages/omnis_plugin_api/lib/service_interfaces.dart`,
`lib/core/main_core.dart`, `lib/core/plugin_catalog.dart`, every file
in `lib/core/` and `lib/ui/` (headers + line counts), all 32 files in
`Omnis-Plugins/lib/`, and `bundled_plugins.dart`. The Favorites
conversion (`b4c9080`) is the precedent this plan generalizes.

## Part 1: Core/Plugin Boundary Audit

### 1A. Genuinely CORE (the bare-player kernel)

| File | Why CORE |
|---|---|
| `lib/core/audio_engine.dart` | The actual playback engine. No player without it. |
| `lib/core/playback_engine.dart`, `playback_state.dart` | Shared playback state model. |
| `lib/core/base_track.dart`, `library_repository.dart`, `library_store.dart`, `media_scanner.dart`, `audio_format_reader.dart` | Scanning local files and reading enough tags to list/play them — discovery+playback metadata, not tag *editing*. |
| Plugin kernel: `plugin_manager.dart`, `plugin_interface.dart`, `plugin_context.dart`, `plugin_runtime.dart`, `plugin_installer.dart`, `plugin_manifest.dart`, `plugin_sandbox_bridge.dart`, `plugin_sandbox_services.dart`, `sandbox.dart`, `plugin_catalog.dart`, `plugin_heartbeat_scheduler.dart`, `plugin_update_scheduler.dart`, `plugin_health_summary.dart` | The mechanism, not a feature. |
| `packages/omnis_plugin_api/*` | The kernel↔plugin contract surface. |
| `event_bus.dart`, `service_registry.dart` | Generic plugin↔host mechanism. |
| `bootstrap.dart`, `omnis_version.dart`, `semver.dart`, `schema_versioning.dart` | App/version lifecycle plumbing. |
| `app_settings.dart` | The persistence *mechanism* is core; most individual flags on it are feature-specific and should migrate to plugin-scoped storage as those features become plugins (see 1E). |
| `home_page.dart`'s shell, `home_navigation.dart` | The navigation *frame* — must exist even with zero plugin tabs. |
| `now_playing_page.dart`, `player_layouts/` (at minimum the standard layout + `layout_manager.dart`'s registry) | Baseline now-playing UI. |
| `widgets/mini_player_bar.dart`, `track_artwork.dart`, `library_shimmer.dart` | Baseline playback chrome. |
| `global_keyboard_shortcuts.dart` (baseline media keys only, not the remap system) | Spacebar-play is not a regression to cut. |

### 1B. Already correctly PLUGIN — no move needed

All 32 files in `Omnis-Plugins/lib/` are legitimately plugin-shaped and
isolated via `bundled_plugins.dart` + `MusicPlugin`/service-interface
contracts: sleep_timer, shuffle_repeat, replay_gain, lyrics, favorites,
ratings, visualizer, smart_playlist, queue_preset, radio, scrobble,
metadata_enrichment, ai_playlist, opensubsonic, jellyfin, emby,
ampache, koel, plex, dlna, artist_image, audio_analysis, tag_editor,
spotify_import, spotify_playback, youtube_music_import,
youtube_playback, bluetooth_playback, equalizer, device_volume,
ringtone, driving_mode.

The gap is not that these live in the wrong repo — it's (a) UI still
reaches many of them by concrete type instead of interface (1D), and
(b) an equally large second pile of features never got extracted at
all and still lives directly in `lib/core/`/`lib/ui/` (1C).

### 1C. Should be PLUGIN, currently baked into core — the larger half of the job

- **DJ/practice**: `ab_repeat_controller.dart`, `ab_loop_store.dart`.
- **Recommendation**: `artist_similarity.dart`, `track_similarity.dart`.
- **Tagging/organization** ("a file organizer and tags"): `calculated_tags.dart`, `tag_find_replace.dart` (+ dialogs), `rename_reconciliation.dart`, `track_fingerprint.dart`/store, `library_cleanup_analyzer.dart` (+ `library_cleanup_report_page.dart`).
- **Moods/smart playlists**: `custom_mood.dart` + the entire Moods tab defined *inline inside `home_page.dart`* (lines 436-826) + `mood_builder_dialog.dart`. The underlying logic (`SmartPlaylistPlugin`/`QueuePresetPlugin`) is already a plugin; the tab shell isn't.
- **Statistics**: `library_statistics.dart`, `favorite_aggregation.dart`, `rating_aggregation.dart` (+ page).
- **Queue intelligence**: `queue_rules.dart`, `queue_continuation.dart` (wired directly into `MainCore._continueQueue`), `queue_history_store.dart` (+ page).
- **Scheduling**: `playback_schedule.dart`, `playback_scheduler.dart` (+ page) — driven by a permanent `MainCore`-owned timer.
- **Diagnostics extras**: `playback_watchdog.dart`, `playback_diagnostics.dart`, `recovery_journal.dart` — keep a minimal always-on watchdog in core, move the reporting UI/elaborate policy config to a plugin.
- **Backup**: `backup_service.dart`, `backup_scheduler.dart` (+ page).
- **Home-screen widget**: `home_widget_service.dart`, `home_widget_track_source.dart` (OS media-session integration itself stays core; the widget doesn't).
- **Radio**: `custom_radio_station_store.dart` + `radio_page.dart` (the plugin logic is bundled correctly; the tab/store around it isn't).
- **Forgotten music**: `forgotten_tracks.dart` + page.
- **Misc**: `output_device_controller.dart`, `mute_toggle.dart`, `star_rating.dart`, `waveform_store.dart`, `artwork_candidates.dart`.
- **Command palette**: `command_palette.dart` + dialog — wired directly into `HomePage`'s Ctrl+K binding.
- **Keyboard remap**: `keyboard_shortcut_remap.dart` + page (distinct from baseline media keys, which stay core).
- **Sidebar customization**: `sidebar_config.dart` + drawer.
- **Home dashboard**: `home_layout_store.dart` + `home_dashboard_page.dart` — the whole Home tab is a customizable widget-dashboard, not baseline playback.
- **Accessibility extras**: `text_scale.dart` + page.
- **App update checker**: `app_update_checker.dart` + `about_page.dart` section.
- **Onboarding**: plausibly core (first-run), but content should reflect installed plugins, not a fixed script.
- **`library_page.dart` (3424 lines)** — the largest file in the app; mixes core browsing with cleanup UI, star-rating UI, column customization, and 5 concrete-type plugin reaches (see 1D).
- **`playlist_page.dart` (1532 lines)** — core playlist CRUD + one concrete-type reach.

### 1D. Concrete-type coupling — confirmed to recur beyond Favorites

The exact `.bundled<XPlugin>(onlyEnabled: true)` pattern Favorites had
to fix recurs at minimum in:

- `library_page.dart`: `LyricsPlugin` (286), `MetadataEnrichmentPlugin` (602), `TagEditorPlugin` (1520), `RingtonePlugin` (1523), `RatingsPlugin` (1552).
- `online_page.dart`: `YoutubePlaybackPlugin` (68), `SpotifyPlaybackPlugin` (74).
- `playlist_page.dart`: `SmartPlaylistPlugin` (87).
- `radio_page.dart`: `RadioPlugin` (44, 101).

Each is its own scoped conversion task (Tier 1 below), same shape and
cost as the completed Favorites conversion.

### 1E. Ambiguous judgment calls

- **Tag reading vs. editing**: reading enough tags to display title/artist/album/duration is CORE; writing tags and derived tag machinery is PLUGIN.
- **Settings shell**: the scaffold (already ends in `uiSlot('settings_page')`) stays CORE; keep only Audio output / Library folder / Plugins as core entries, move the rest behind plugin injection as each owning feature migrates.
- **Now Playing layouts**: Standard stays core; Car Mode/TV Mode/Karaoke/Full Art Gestures/Landscape are plugin territory. `layout_manager.dart`'s registry/switching mechanism stays core.
- **Online tab**: recommend classifying as 100% PLUGIN once Part 2's tab mechanism exists, rather than leaving it ambiguous forever.
- **`playback_watchdog.dart`**: keep a minimal stuck-track→skip watchdog in core; move diagnostics UI/policy config to a plugin.
- **`AppSettings` god-object**: the persistence mechanism is core; individual optional-feature flags should migrate to plugin-scoped storage (`PluginStorage`) as those features become plugins.

## Part 2: The Plugin-Contributed Tab/Window Mechanism

### 2A. What already exists

`plugin_slot_view.dart`'s `nav_item` slot type already lets a
**bundled** plugin return `{'type': 'nav_item', ...}` from
`uiSlot('sidebar_item')`, rendered as a tappable item that pushes a
full, unrestricted route (`Navigator.push(MaterialPageRoute(builder:
hookValue))`) — today, for bundled plugins. It's currently a
secondary-entry-point mechanism (a pushed route, not a persistent
`IndexedStack` tab with state preservation), not a first-class tab.
The new mechanism generalizes this rather than inventing something
unrelated.

### 2B. Design for BUNDLED plugins

1. New optional `MusicPlugin` method in `omnis_plugin_api`:
   `List<PluginDestination> homeDestinations() => const [];`
   `PluginDestination`: `{ id, icon, label, pageBuilder, order }`.
2. `PluginManager` gains an aggregating `homeDestinations` getter
   (sandboxed via `_sandbox.runSync`, mirroring `uiSlot()`), live via
   the existing `changes` stream.
3. `home_page.dart`'s hardcoded `destinations`/`pages` lists become:
   core list + `pluginManager.homeDestinations`-derived list, core
   first, plugin destinations appended ordered by `order` (ties by
   registration order in `bundled_plugins.dart`). `_selectedIndex`
   becomes id-keyed (`String? _selectedDestinationId`) with fallback
   to the first core destination if the previous selection vanished
   (a plugin can be disabled mid-session).
4. `IndexedStack` keeps every tab's subtree alive across switches —
   free once a plugin destination is added to the same children list.
5. Guard: `home_page.dart`'s `build()` must clamp/redirect selection on
   every rebuild, not just on tab-tap, so a shrinking destination list
   (uninstall) never leaves the index pointing past the end.

### 2C. Design for DOWNLOADABLE plugins — hard wall, stated plainly

**Not achievable today.** A downloadable plugin runs in `dart_eval`
with no `package:flutter` access — it can only return small
declarative Maps, never a real persistent widget subtree with its own
scroll/animation state. Two real paths forward, neither incremental:

- **(a) A declarative page-description DSL**, reusing the existing
  pattern in `lib/ui/player_layouts/declarative/declarative_layout_renderer.dart`
  as the template. Bounded but real multi-task work; always a strict
  subset of a bundled tab's capability.
- **(b) Loosen the sandbox** to allow constrained widget-building — a
  much larger, riskier undertaking given this session already hit a
  real dart_eval interpreter bug just calling zero-arg hooks.

**Recommendation: do not block Part 3 on this.** Ship the bundled tab
mechanism first; downloadable plugins keep contributing only slot
content until (a) is separately scoped later.

### 2D. New window vs. new tab (mobile vs. desktop)

- **Mobile**: "new window" degrades to a full-screen route push,
  identical to today's tab-tap behavior.
- **Desktop (Windows CI target)**: extend `PluginDestination` with an
  optional `preferSeparateWindow` flag; on desktop, opens a genuine OS
  window (DJ dual-deck view, a detached karaoke display for a second
  monitor) hosting the same `pageBuilder`. Sequence after the basic
  tab mechanism ships and is proven with one real plugin — additive,
  not a prerequisite.

## Part 3: Ordered Task Breakdown

### Tier 0 — Blocking foundation

- **T0.1** Add `homeDestinations()` to the plugin contract (`omnis_plugin_api`, `plugin_manager.dart`). Additive, no existing call site touched.
- **T0.2** Make `home_page.dart`'s destination/page list dynamic (depends on T0.1). **Hidden risk**: `_paletteActions` hardcodes literal `_selectedIndex = N` (lines 183, 199, 244, 248) — must convert to id-keyed resolution. Check `global_sidebar_drawer.dart`/`command_palette_dialog.dart` for the same assumption.
- **T0.3** Convert `RadioPlugin` to interface-based lookup in `radio_page.dart` — simplest of the five 1D reaches (2 call sites, one plugin, no persistence complication), proving the template Tier 1 copies.

### Tier 1 — Parallelizable once Tier 0 lands (concrete-type fixes)

- **T1.1** `LyricsPlugin` in `library_page.dart` (286) — interface already exists, pure call-site fix.
- **T1.2** `MetadataEnrichmentPlugin` (602) — same, pure call-site fix.
- **T1.3** `RatingsPlugin` (1552) — likely needs a write method added to `IRatingsProvider`/`IThumbsProvider`, same shape/cost as Favorites. **Higher risk.**
- **T1.4** `TagEditorPlugin` (1520) — needs a new, narrowly-scoped write interface (title/artist/album/genre only). **Higher risk.**
- **T1.5** `RingtonePlugin` (1523) — no existing interface; small, from-scratch addition.
- **T1.6** `SmartPlaylistPlugin` in `playlist_page.dart` (87) — `IQueueBuilder` may already cover this via `services.getAll<IQueueBuilder>()`; verify before assuming new interface work is needed.
- **T1.7** `YoutubePlaybackPlugin`/`SpotifyPlaybackPlugin` in `online_page.dart` (68, 74) — likely needs a small new capability-check interface; do both together.

**Coordination note**: T1.1-T1.5 all touch the same 3424-line
`library_page.dart` — sequence them serially even though logically
independent, to avoid merge conflicts across parallel workers.

### Tier 2 — Depends on T0.2 (moving whole tabs into plugins)

- **T2.1** Extract Home dashboard into a bundled plugin. Preserve the `GlobalKey`-based "customize home" command-palette action via a new ServiceRegistry capability instead of a cross-boundary GlobalKey reach.
- **T2.2** Extract Moods (currently inline in `home_page.dart`, lines 436-826) into a bundled plugin. Largest Tier-2 extraction; `MoodsPageState` is reached via GlobalKey from the command palette — replace with a ServiceRegistry interface for "play this named mood."
- **T2.3** Extract Radio+Online tab into a plugin (depends on T0.3, T1.7).
- **T2.4** Move Settings sub-pages behind `uiSlot('settings_page')` injection, sequenced *after* each feature's own extraction lands, not as one big-bang task.

### Tier 3 — Independent, no tab-mechanism dependency

File-cluster extractions that don't touch `home_page.dart`'s nav list:
A/B loop+DJ tools, tag/organization cluster (likely splits into
cleanup-analyzer+report and calculated-tags+find-replace), similarity,
statistics (sequence after T1.3), queue intelligence (**higher risk** —
`queue_continuation.dart` is called directly by
`MainCore._continueQueue`, needs a new kernel extension point, not a
simple file move), playback scheduling (**higher risk**, same
`MainCore`-owned-timer issue), backup (same timer issue — consider a
shared "periodic tick" hook built once for scheduling+backup+queue
intelligence), forgotten music (sequence with T2.2 — reached from
inside the Moods page today), home-screen widget, command palette
(likely stays as a core shell, only specific actions migrate with
their features), keyboard remap, sidebar customization, accessibility
settings, app update checker, output device controller (check overlap
with existing `BluetoothPlaybackPlugin`/`DeviceVolumePlugin` first),
star-rating math (sequence with T1.3), artwork candidates (check
overlap with `MetadataEnrichmentPlugin`/`ArtistImagePlugin`).

### Tier 4 — Downloadable-plugin declarative page DSL

Separately scoped multi-task effort (design vocabulary → renderer →
sandbox bridge hook → one real proof-of-concept plugin), not detailed
further here, not blocking Tiers 0-3.

## Part 4: Honest Scope/Risk Assessment

**Rough scale**: ~35-40 discrete tasks as listed, realistically
**45-55** once several (T1.3, T1.4, and the Tier-3 timer-dependent
tasks) split further on contact, the same way "convert Favorites"
turned into touching 6 files plus a real feature-cut decision. Each
task is sized similarly to the completed Favorites conversion — a few
hours to a day of focused work including verification.

**Single riskiest part of the whole plan**: extracting anything
`MainCore` currently *drives* itself via an owned `Timer`/direct method
call — queue continuation, playback scheduling, backup, and to a
lesser extent the playback watchdog. Unlike every conversion done so
far (including Favorites), where the plugin was a passive thing UI
*reads from*, these need `MainCore` itself to grow new generic
extension points ("periodic tick," "queue exhausted") that don't exist
in any form today — new kernel surface area, with the same "what if a
plugin's handler is slow/throws/never returns" sandboxing questions the
rest of the plugin system already solved once, needing to be re-solved.
It's possible the honest answer for one or more of these is "this
can't be cleanly pulled out without a kernel redesign broader than
this plan accounts for" — worth confirming in detail before committing
schedule to that part of Tier 3, rather than discovering it mid-task.

**Secondary risk**: `library_page.dart` (3424 lines) is simultaneously
the most core surface and the most plugin-entangled file — sequence
its five Tier-1 fixes serially even though logically parallel, to
avoid multi-worker merge conflicts on one file.

## Critical files

- `lib/ui/home_page.dart` — the hardcoded shell Part 2 replaces.
- `lib/core/plugin_manager.dart` — where `homeDestinations()` and every Tier-1 interface fix is wired.
- `packages/omnis_plugin_api/lib/service_interfaces.dart` — every new capability interface lands here.
- `lib/ui/plugin_slot_view.dart` — the existing `nav_item` precedent Part 2 generalizes; also Tier 4's extension point.
- `lib/core/main_core.dart` — the highest-risk file (Part 4's Tier-3 kernel-extension-point problem).
- `lib/ui/library_page.dart` — the largest concentration of Tier-1 fixes and Tier-3 extraction.
