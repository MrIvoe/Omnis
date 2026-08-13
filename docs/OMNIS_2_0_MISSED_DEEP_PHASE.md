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

## Phase 3–7 audit (2026-08-13)

Five parallel research passes against both repos, launched before any
Phase 3+ code was touched — same discipline as the Phase 2 audit that
found Search/Ratings were real gaps while most of the rest of Library
already existed. [OMNIS_2_0_FINISHED_TASK.md](OMNIS_2_0_FINISHED_TASK.md)'s
phase tables summarize these; this section has the full detail each
summary was distilled from.

### Phase 3 — Audio

**18. DSP pipeline** — Partial. `AudioEngine.setGainContribution` is a
flat named-multiplier gain-composition system (ReplayGain and EQ each
register a multiplier, engine multiplies them together), not the
spec's staged, independently-replaceable chain. Zero code anywhere in
either repo for compressor, limiter, crossfeed, convolver, spatializer,
or room/headphone/speaker correction. No explicit "visualizer tap" —
`VisualizerPlugin` captures via a separate OS-level system-mix
(`audify`), not a tap on this pipeline.

**19. ReplayGain** — Partial. `ReplayGainPlugin` reads
`BaseTrack.replayGain.trackGain` (populated from existing file tags via
`TagEditorPlugin`/`MediaScanner`) and applies it as a gain multiplier,
plus a user preamp (-6..+6 dB). Omnis never *scans*/computes ReplayGain
itself — it only consumes values some other tool already wrote. No
album-gain mode toggle, no true-peak/limiter clip protection.

**20. EQ** — Partial. `EqualizerPlugin` has two real modes: hardware
(Android only, drives the OS `android.media.audiofx.Equalizer` via
`HardwareEqBand`) and virtual (a fixed 3-band ±12dB trim as a gain
contribution, everywhere else). Bands persist *per connected device*
(via `IDeviceConnectivityProvider`/`BluetoothPlaybackPlugin`) — real
per-device profiles, but not per-artist/per-album. No selectable band
count, no parametric mode, no EQ at all on desktop beyond the 3-band
trim (no `AVAudioUnitEQ`, no WASAPI APO).

**21. Output devices** — 0% for device *selection*. `BluetoothPlaybackPlugin`
detects a Bluetooth device connecting/disconnecting (used for quick-play
prompts and EQ-profile keying only). `AudioEngine.setOutputDeviceToDefault()`
is an explicit documented no-op. No device list UI, no USB DAC support,
no per-device volume/DSP beyond the EQ keying above, no
HDMI/Cast/DLNA/AirPlay output.

**22. Bit-perfect mode** — Genuine 0%. `BaseTrack` carries no audio-format
fields at all — no codec, container, bit depth, sample rate, channels,
or bitrate. There's no data source to build the spec's
source→DSP→resampling→output display from, and no exclusive/WASAPI-style
output mode.

**23. Audio analysis** — Partial. `AudioAnalysisPlugin` is a real HTTP
client to a self-hosted Essentia service (`tools/essentia_service/`,
not bundled — the user must deploy it themselves) that returns genuine
audio-derived BPM/key/mood/genre. No loudness/dynamic-range measurement,
no on-device/offline analysis, no acoustic-fingerprint/embedding output
for a future recommendation engine to consume.

### Phase 4 — Plugin platform

**24. Capability interfaces** — Solid. `packages/omnis_plugin_api/lib/service_interfaces.dart`
defines 9 typed interfaces (`ILyricsProvider`, `IPlayHistoryProvider`,
`IQueueBuilder`, `IMetadataProvider`, `IAudioAnalysisProvider`,
`IFileTagWriter`, `IVisualizerProvider`, `IArtistImageProvider`,
`IDeviceConnectivityProvider`); `ServiceRegistry`
(`packages/omnis_plugin_api/lib/service_registry.dart`) is a real,
working typed registry (`register`/`unregister`/`get<T>`/`getAll<T>`/`has<T>`,
a `changes` stream, multi-provider support — used for `IQueueBuilder`
by both `SmartPlaylistPlugin` and `QueuePresetPlugin`). Gap: external
(downloaded) plugins can only register as providers for 2 of the 9 —
`PluginManager._registerProvidedServices`/`_capabilityType` hard-codes a
`switch` covering only `'lyrics'` and `'queue_builder'`; a downloaded
plugin declaring `provides: [IMetadataProvider]` is silently never
registered.

**25. Plugin lifecycle** — Solid mechanics, partial spec fidelity.
Install → register → init → enable/disable → uninstall all work, and
isolation is real: every hook call goes through `PluginSandbox.run`,
which catches exceptions, logs a `PluginHealthRecord`, times out after
8s, and never propagates (confirmed in `docs/PLUGIN_SECURITY.md`).
Downloaded plugins additionally run through `dart_eval`
(`lib/core/plugin_runtime.dart`), a real interpreted sandbox that can't
import `package:omnis`/`dart:ui`. Gap: no explicit
`[INSTALLED]→[LOADING]→...→[UNINSTALLED]` state-machine enum (inferred
from two booleans instead); `dart_eval` runs on the same thread, so a
synchronous non-yielding loop in a downloaded plugin can still hang the
UI (documented limitation, not an oversight).

**26. Dependency resolution** — Partial for bundled plugins only, 0%
for the manifest-declared case. `PluginManifest.parse` has **no
`dependencies:` field at all** — confirmed by reading the parser. What
exists instead is code-level ordering for bundled plugins:
`MusicPlugin.requiresSequentialInit` plus `PluginManager.initializeAll()`'s
two-round init, used for two documented real dependencies
(`QueuePresetPlugin` after `SmartPlaylistPlugin`; `EqualizerPlugin`
after `BluetoothPlaybackPlugin`). No manifest syntax for "I need plugin
X"/"I need capability Y", no dependency graph/resolver,
`minOmnisVersion` is parsed but never enforced anywhere (3 total hits,
all in the parser itself), and no handling of a dependency disappearing
(e.g. disabling `BluetoothPlaybackPlugin` just makes
`EqualizerPlugin`'s device-profile lookup silently return null, no
warning).

**27. Permissions** — Solid. Manifest `permissions:` map to real
`dart_eval` grants (`FilesystemPermission`, `LibraryReadPermission`,
`EventsPermission`, `PlaybackControlPermission`), checked via
`PluginRuntime.hasPermission`. Plain-English disclosure via
`plugins_page.dart`'s `_confirmPermissions` dialog, shown *before* any
plugin code executes. Gap: coarse, un-namespaced categories (`network`,
`storage`) rather than the spec's granular `network:musicbrainz`-style
scoping; `docs/PLUGIN_SECURITY.md` itself states `network` is
declarative-only (not technically enforced) and `storage` is
all-or-nothing. No `privacy:`/`data-collected:`/`network-hosts:`
manifest section parsed or shown.

**28. Plugin health** — Partial. `PluginSandbox.healthRecords` (capped
at 200) is populated automatically on every sandboxed failure, with a
live listener mechanism and a real "Plugin Health" section at the
bottom of the Plugins page (name, hook, human-readable reason, raw
message, timestamp, "Dismiss all"). Gap: no dedicated health-center
page (it's a section of the general Plugins page, not the spec's
separate 🟢/🟡/🔴-per-plugin view), no heartbeat (health is purely
reactive — a silently-hung plugin that never throws is never detected),
no per-plugin retry/reset action, no auto-disable/auto-retry on
repeated failure.

**29. Plugin updates** — Genuine 0%. Reinstalling the same URL
deletes-and-replaces the plugin directory, but there's no version
comparison against any remote/catalog version, no update-check, no
backup-before-update, no rollback-on-failed-update, no "update
available" UI.

**30. Marketplace/catalog** — Partial. A real permission-confirmation
install flow exists for two paths: a hardcoded `officialPluginCatalog`
(currently one entry, `sample_logger`) and a free-text "paste a
GitHub/zip URL" field (`PluginInstaller.installFromUrl` — zip-bomb/
zip-slip guarded, manifest-validated). `docs/PLUGIN_SECURITY.md` states
outright: "No plugin registry or curation today... Installing means
trusting whoever's GitHub URL you pasted." No fetched `catalog.json`
from any endpoint, no browsable UI (search/categories/featured/
ratings/screenshots), no `omnis-plugin-hub` meta-repo — `Omnis-Plugins`
itself is a flat package of plugin *sources*, not a hub of references
to separate plugin repos as spec §6.2 describes.

### Phase 5 — Connectivity

**31-35. OpenSubsonic / Navidrome / Jellyfin / Plex / DLNA-UPnP** —
Genuine 0%, every one. No file, class, or `TrackType` case for any of
them in either repo. Since Navidrome would piggyback on an OpenSubsonic
client, and none exists, there's no partial credit there either. This
is the single biggest concrete gap-cluster found across every phase
audited — the spec (§16) calls self-hosted connectivity "a major
opportunity," and literally none of it exists.

**36. Spotify** — Solid, unverified. `SpotifyAuth`: full Authorization
Code + PKCE OAuth (RFC 7636) against Spotify's Web API, platform-aware
redirect URIs, secure token storage, automatic refresh.
`SpotifyImportPlugin`: fetches account playlists/tracks as metadata-only
`BaseTrack`s (DRM prevents real playback — deliberate, not a shortfall),
with a real settings UI. `SpotifyPlaybackPlugin`: genuine Spotify
Connect remote control (device list, transfer, transport, now-playing
poll), deliberately not merged into Omnis's own queue (audio plays on
the external Spotify app/device). `Omnis-Plugins/README.md` self-flags
both plugins ⚠️: "Not exercised against a real Spotify account[/device]."

**37. YouTube** — Solid, unverified. Same shape as Spotify:
`YoutubeAuth` (PKCE OAuth against Google), `YoutubeMusicImportPlugin`
(API-key public search + OAuth-gated playlist import),
`YoutubePlaybackPlugin` (plays via YouTube's own embedded IFrame
player/WebView, deliberately not stream-extraction — a ToS violation).
Correctly platform-gated (Android/iOS/web only, no Windows/Linux
WebView). Self-flagged ⚠️ in the README: neither exercised against a
real OAuth client or device/web build.

**38. Other providers** — Genuine 0% as music providers. Apple Music,
SoundCloud, Bandcamp, Tidal, Qobuz, Emby: no files, no references,
anywhere. `ArtistImagePlugin`'s Deezer call is explicitly documented as
artist-photo lookup only ("not for playback or any Deezer-catalog
feature") — not a Deezer music provider.

### Phase 6 — Discovery

**39. Recommendations** — Partial. The "Moods" page (`_MoodsPage` in
`home_page.dart`) is effectively one algorithm from the spec's list — a
crude Mood Radio, built by trying each registered `IQueueBuilder`
(`SmartPlaylistPlugin` then `QueuePresetPlugin`) until one returns a
non-empty queue. None of the spec's other named algorithms (Similar
Track/Artist, Album/Artist/Genre Radio, Discovery, Deep Cuts, Forgotten
Favorites, Rediscover, New Releases, Daily/Weekly Mix, Energy Flow)
exist anywhere — confirmed via repo-wide search, zero matches. No
provider-neutral recommendation framework/interface. `favorites_plugin.dart`
and `ratings_plugin.dart` store real signal data but nothing consumes
it for recommendations.

**40. Sonic similarity** — Partial. `AudioAnalysisPlugin` extracts real
acoustic features (BPM/key/mood/genre) via Essentia — genuine
audio-derived data, not just tags. But there is no embedding/vector and
no similarity/distance computation anywhere in either repo — nothing
does actual "find tracks that sound like this." What consumes these
results (`SmartPlaylistPlugin`/`QueuePresetPlugin`) is still tag-string
matching once the tags are populated, not fingerprint/vector similarity
the way Plexamp's Sonic Analysis (cited in the spec) works.

**41. Radio** — Genuine 0%. Confirmed by filename search (`*radio*`,
zero hits) and content search (`radio`/`Icecast`/`Shoutcast`/
`RadioBrowser`, only false positives — Flutter's own `RadioListTile`
widget, an unrelated code comment). No Radio Browser API integration,
no custom stream support, no Icecast/Shoutcast client, no station
browsing UI, no streaming-station playback path.

**42. Smart playlists** — Partial. Despite the name, `SmartPlaylistPlugin`
is a flat, user-editable list of mood strings matched via case-insensitive
substring against `track.mood` (one hardcoded special case: "focus"
also matches an `ambient` genre tag) — it directly powers the Moods
page, confirmed by cross-referencing doc comments in both files that
explicitly point at each other as the same feature. `QueuePresetPlugin`
is a complementary static genre-keyword/BPM-threshold fallback for the
same four preset names. There is no rule-based engine anywhere — no
`SmartPlaylistRule` class, no per-field condition model (genre/year/
rating/play-count/date-added operators), no ALL/ANY/NONE boolean
grouping. A user can add another mood label to match against; they
cannot define an arbitrary new multi-condition rule set.

**43. AI** — Genuine 0%. No `IAIProvider`, no AI-related class,
dependency, or code anywhere in either repo. Confirmed via repo-wide
search for the interface name and every capability the spec lists
(natural-language search, AI playlist creation, AI metadata cleanup,
voice control, etc.) — zero matches.

### Phase 7 — Advanced UX

**44. Themes** — Partial. A real declarative theme engine exists
(`lib/ui/theme/declarative/`: `ThemeManifest` parser, `ThemeInstaller`,
`ThemeManager`, rendered through the same pipeline as a built-in
preset), importable from a URL or local file. Four built-in presets:
`AppThemePreset { classic, midnight, aurora, sunset }` — only "Classic"
survives from the spec's named list of 6 (Pure/Drive/Karaoke/Future/
Audiophile don't exist as *themes*, though Drive/Karaoke exist as
separate *Now Playing layouts*, see item 45). The engine only changes
colors/typography/shape/motion/background — it does not touch
navigation type, Home layout, or Library layout the way spec §20/§28
("themes can alter navigation") demands; a theme and a layout are two
separate systems here, not the unified "Theme = composition + styling +
behavior + assets + layout rules" concept the spec describes.

**45. Layout builder** — Solid for Now Playing, 0% for Home. `lib/ui/player_layouts/`
has a genuinely complete declarative layout system: 6 bundled layouts
(Standard, Top Controls, Landscape, Full Art + Gestures, Karaoke
Gestures, Car Mode), install-from-URL/file, and — notably — a real
drag-and-drop visual editor (`LayoutEditorPage`): tap to add components
from a palette, drag freely, remove, name, save, all serializing to the
same manifest format an imported layout uses. Entirely scoped to Now
Playing, though — `home_dashboard_page.dart` is a hardcoded,
non-reorderable widget with fixed sections (no hide/show/reorder/resize
"widget canvas" per spec §6-8), and there's no sidebar customization
(add/remove/reorder/group nav items) either.

**46. Car mode** — Solid. `CarModeLayout`: a dedicated Now Playing
layout with an oversized button rail on either edge, large centered
artwork, deliberately dropping EQ/visualizer/lyrics to minimize
driving distraction. `DrivingModePlugin`: real GPS-speed-triggered
auto-activation (configurable threshold, default 20 km/h) and
auto-revert, with documented Android background-service limitations
(foreground-only; can't silently auto-connect Bluetooth since Android
13, surfaces a reminder instead). No separate Car *theme*, no voice
control, no Android Auto/CarPlay integration.

**47. TV mode** — Genuine 0%. No file, class, or string reference to
"TV," a 10-foot interface, or remote/D-pad navigation anywhere in
either repo.

**48. Accessibility** — Partial. A real, git-log-verified accessibility
pass (commit `e101b34`): tooltips added to every previously-unlabeled
icon button, `Semantics(label:/hint:)` wrapped around custom
gesture-driven tap targets (full-bleed/karaoke Now Playing layouts, the
mini-player bar, the waveform seek bar with custom increase/decrease
actions, the layout editor's drag handles), `ExcludeSemantics` around
decorative artwork/icons, and widget tests that actually assert on the
semantics tree. Working "Reduce motion" (globally collapses animation
durations to zero via `OmnisMotion`) and "Reduce transparency" settings.
Gaps: no dedicated Accessibility settings category (buried inside
Appearance & Layout), no high-contrast mode, no colorblind-safe state
option, no app-wide text-scale setting (only a 4-step lyrics-only text
size), and — significant — **zero keyboard navigation/shortcuts
anywhere** (no `Shortcuts`/`FocusTraversalGroup`/`CallbackShortcuts`
usage found), so the UI spec's global Ctrl+K search (§37) and command
palette (§38) don't exist either, on top of not being an accessibility
gap in their own right. No voice control, no switch-input support, no
RTL/localization wiring (`AppLocalizations` isn't used).

**49. Widgets** — Genuine 0%. This is OS-level home-screen widgets
(Android App Widgets / iOS WidgetKit), not in-app UI. No `home_widget`-
style package dependency, no Android widget provider manifest entry, no
iOS widget extension target.

**50. Automation** — Partial. Two real, working single-purpose
triggers: GPS-speed → Car Mode layout switch (`DrivingModePlugin`, see
item 46), and Bluetooth-connect → quick-play/EQ-preset prompt
(`BluetoothPlaybackPlugin`). Neither is the general-purpose
"automation rules" engine the spec's §48-49 describes (no time-based
triggers, no arbitrary condition→action rules, no UI-profile
export/import/auto-switch), and the Bluetooth trigger specifically
doesn't switch the UI/theme the way the spec's own example
("Bluetooth device connected → Activate Driving UI") describes — it
only offers quick-play and EQ switching.
