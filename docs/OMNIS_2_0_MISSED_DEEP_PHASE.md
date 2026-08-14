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
  still undone. Originally deferred because touching the crossfade/queue
  state machine felt too risky without a real device to smoke-test on —
  as of 2026-08-13 that's now half-outdated: Android smoke testing is
  confirmed working in this dev environment (a debug APK built,
  installed, and ran clean on an emulator, including a genuine live
  network round-trip via the new Radio feature — see `docs/BUILDING.md`).
  Windows desktop specifically is still blocked, but for a confirmed,
  narrow reason (Flutter SDK 3.27.4 doesn't recognize the installed
  Visual Studio Build Tools 2026's version and falls back to a CMake
  generator string that doesn't exist on this machine — also documented
  there). The bigger `AudioEngine` split is still real, separate work
  not attempted in this pass, but "no way to smoke-test it at all" is no
  longer the blocker — only "hasn't been done yet."
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

**22. Bit-perfect mode** — Partial, informational half only (2026-08-13).
`BaseTrack` now carries real `codec`/`sampleRateHz`/`bitDepth`/
`bitrateKbps`/`channels` fields (`plugin-api-v0.6.0`), populated by a new
pure-Dart `AudioFormatReader` (`lib/core/audio_format_reader.dart`) that
parses real file headers — FLAC STREAMINFO (exact sample rate/bit depth/
channels, average bitrate from file-size/duration), WAV fmt chunk (exact,
including a real byte-rate-derived bitrate), and MP3 frame headers
(sample rate/channels from the first valid frame, average bitrate from a
Xing/Info VBR header's frame/byte counts when present, not just the
misleading first-frame value for VBR files). Surfaced via a new
"Audio info" dialog on each track (`library_page.dart`'s track menu).
Still gaps: M4A/AAC, OGG/Opus, WMA, and AIFF only get a codec label from
their extension — full MP4-box/Ogg-page/ASF-header parsing for those
containers is real, separate work, deliberately not attempted here to
avoid shipping wrong numbers. And the DSP/output half is still fully 0%:
no source→DSP→resampling→output *chain* display, no exclusive/
WASAPI-style output mode. Also found and left as-is (out of scope for
this pass): `BaseTrack`'s `==`/`hashCode` compare list fields
(`artists`/`genres`) with plain `List.==`, which Dart doesn't override
for content equality — so two structurally-identical tracks built from
separate list literals are never `==`-equal unless they share list
instances. Harmless today (every real call site compares tracks by
`.id`, never by `==`/in a `Set`), but a latent trap for future code that
assumes value equality.

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

**29. Plugin updates** — Partial (was genuine 0%, closed 2026-08-13).
Real update detection now exists: `PluginInstaller.fetchRemoteManifest`
resolves a plugin's GitHub source URL to its raw
`raw.githubusercontent.com/.../omnis_plugin.yaml` location and fetches
just that one file — orders of magnitude lighter than the full zip
`installFromUrl` downloads, since a version check has no reason to pull
an entire repo. `PluginManager.checkForUpdates()` compares the fetched
manifest's version against every installed *external* plugin's own
`version` (bundled plugins are never checked — they update with the app
itself) using a new `lib/core/semver.dart` numeric comparison (`"1.10.0"
> "1.9.0"`, unlike a plain string compare, which gets that backwards).
`updatePlugin(id)` re-downloads and replaces the plugin — a fresh
install, not just a version-string swap, so it also picks up any code
change alongside a version bump — while explicitly *not* touching
`AppSettings`'s persisted enabled/disabled choice for that plugin id (a
real bug avoided during design: naively reusing `disablePlugin()` to
tear down the old instance would have persisted "disabled" and
silently left a previously-enabled plugin disabled after every update).
Wired into a "Check for updates" button and a per-plugin "Update
available: vX" banner + button on the Plugins page.

Gaps: no backup-before-update (a bad update isn't reversible — no
snapshot of the old, working plugin directory is kept), no
rollback-on-failed-update, no automatic/background/scheduled checking
(purely user-initiated, one tap at a time), and — a real, structural
limit, not a missed detail — update detection only works for a GitHub
`tree/branch[/subfolder]` or bare-repo source URL; a plugin installed
from a direct `.zip` link has no general way to derive a single raw
file's location from an arbitrary zip URL, so `fetchRemoteManifest`
returns `null` for those (silently skipped in `checkForUpdates`, not
reported as a failure).

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

**31-32. OpenSubsonic / Navidrome** — Solid but unverified (closed
2026-08-13, was genuine 0%). New `OpenSubsonicPlugin`
(`Omnis-Plugins/lib/opensubsonic_plugin.dart`) is a real client to the
OpenSubsonic/Subsonic REST API — the protocol Navidrome, Airsonic, and
the original Subsonic all implement, so one client covers all of them;
no Navidrome-specific code exists or is needed, matching the tracker's
own earlier prediction that Navidrome would "piggyback on OpenSubsonic."
Auth uses the recommended token scheme (`t = md5(password + salt)`, a
fresh random salt per request) rather than sending the plaintext
password on every call, though the password itself is still stored
locally in this plugin's own `PluginStorage` — no secure-keystore
integration exists anywhere in this app, the same limitation
`MetadataEnrichmentPlugin`'s API keys already have. `search3.view`
returns genuinely playable `BaseTrack`s (new `TrackType.subsonic` on
`plugin-api-v0.8.0`): each track's `streamUrl` is the server's own real
`stream.view` endpoint, so `AudioEngine` plays it with zero
special-casing — unlike `SpotifyImportPlugin`'s metadata-only imports
(Spotify's catalog is DRM-protected), this is a fully working provider,
not just a browsable library. Settings UI (server/username/password,
"Test connection," inline search-and-play) reached through the Plugins
page's existing per-plugin settings slot — no new bottom-nav tab or
Core changes needed. 17 tests against a mocked HTTP client, including
one that independently recomputes the MD5 token from the salt actually
sent in the request to prove the auth math is correct, not just that
*some* token was sent. **Not exercised against a real Navidrome/
Subsonic/Airsonic server** in this environment — what's verified is
protocol-level request/response handling, the identical caveat already
applied to Spotify/YouTube (item 36 below).

**33. Jellyfin** — Solid but unverified (closed 2026-08-13, was genuine
0%). New `JellyfinPlugin` (`Omnis-Plugins/lib/jellyfin_plugin.dart`) is
a real client to Jellyfin's own REST API — deliberately a separate
plugin from `OpenSubsonicPlugin` rather than a shared client, because
the two protocols only look similar at a glance: Jellyfin uses
session-token auth (`POST /Users/AuthenticateByName` with a
`MediaBrowser Client="...", Device="...", DeviceId="...", Version="..."`
header, returning an `AccessToken` + `User.Id` pair) where OpenSubsonic
computes a fresh per-request MD5 token from a salt; the search
endpoints return differently-shaped JSON (`Items`/`Artists`/
`RunTimeTicks`/`IndexNumber` vs. `searchResult3`/`song`/`artist`/
`duration`/`track`); and duration needs a unit conversion OpenSubsonic
doesn't (`RunTimeTicks` is in 100-nanosecond ticks — divide by
10,000,000 for seconds, done once in `_itemToTrack`, verified by a test
asserting the exact converted value, not just "some duration").

The session access token is kept in memory only (never persisted,
unlike the username/password themselves, which — like
`OpenSubsonicPlugin`'s password — live in this plugin's own
`PluginStorage` with no secure-keystore backing, since none exists
anywhere in this app yet), and is transparently re-authenticated
exactly once on a `401` mid-search. That "exactly once" bound was
deliberate and specifically tested: a naive retry-on-401 that
re-authenticates and retries unconditionally would infinite-loop
against a server that keeps rejecting every request for some other
reason (e.g. a disabled/deleted user account whose stale password is
still saved locally) — a `retried` flag threaded through a private
recursive helper caps it at one retry, and
`jellyfin_plugin_test.dart` has a dedicated test asserting exactly 2
auth calls and 2 search calls (not 3, not an unbounded number) against
a mock server that always returns 401.

Search results become plain `BaseTrack`s (new `TrackType.jellyfin` on
`plugin-api-v0.9.0` — a distinct value from `subsonic` rather than
reused for it, precisely because the two are different protocols under
the hood even though both are "directly playable self-hosted server"
tracks) with a genuine `streamUrl` at Jellyfin's own
`/Audio/{id}/stream?static=true&api_key=...` endpoint, so `AudioEngine`
plays these with zero special-casing, the same as every other
`streamUrl`-bearing track type. Settings UI (server/username/password,
"Test connection," inline search-and-play) uses the identical
per-plugin settings-slot pattern `OpenSubsonicPlugin`/Spotify/YouTube
import already established — no Core changes, no new nav tab. 17 tests
against a mocked HTTP client. **Not exercised against a real Jellyfin
server** in this environment — protocol-level correctness only, the
same caveat already applied to OpenSubsonic (items 31/32) and
Spotify/YouTube (item 36 below).

**34. Plex** — Solid but unverified (closed 2026-08-13, was genuine
0%). New `PlexPlugin` (`Omnis-Plugins/lib/plex_plugin.dart`) is a real
client to Plex Media Server's REST API — a third, separate plugin from
`OpenSubsonicPlugin`/`JellyfinPlugin` rather than sharing either,
because Plex's auth model and response shape are both distinct from
those two: a single account-scoped `X-Plex-Token` sent on every
request (not OpenSubsonic's per-request computed MD5 token, not
Jellyfin's session token from a login call), and Plex's `/search`
endpoint returns every media type it knows about in one flat
`Metadata` list (movies, shows, artists, albums, tracks — this plugin
filters to `"type": "track"` only), with track fields in different
places than either sibling plugin expects: artist on
`grandparentTitle` (not `artist`/`Artists`), duration in **milliseconds**
(not OpenSubsonic's seconds or Jellyfin's 100-nanosecond ticks — a
`~/1000` conversion, tested), and the actual playable file path nested
three levels down at `Media[0].Part[0].key` rather than a flat id this
plugin can build a stream URL from directly.

Deliberately does **not** implement Plex's full `plex.tv` sign-in/
PIN-pairing OAuth-like flow for obtaining an `X-Plex-Token` — the user
is expected to already have one, which is the standard, well-documented
entry point every third-party Plex client (Tautulli, PlexPy, countless
scripts) starts from, not a shortcut unique to this plugin. Building
that flow for real is separate, real work, not attempted here — this is
narrower in scope than `OpenSubsonicPlugin`/`JellyfinPlugin`, which
both take a username/password directly against the self-hosted server
itself, no separate account-linking step.

Search results become plain `BaseTrack`s (new `TrackType.plex` on
`plugin-api-v0.10.0`) with a genuine `streamUrl` at the real media file
Plex serves, so `AudioEngine` plays these with zero special-casing —
the same as every other `streamUrl`-bearing track type this session
added. Same settings-slot UI pattern as the other two server plugins.
18 tests against a mocked HTTP client, including one specifically
proving the type-filtering works (albums/artists/movies mixed into a
search response are correctly dropped, only the real track survives)
and one proving a `"type": "track"` entry with no `Media`/`Part` at all
(no playable file reference) is skipped rather than producing a track
with a broken stream URL. **Not exercised against a real Plex server**
in this environment — protocol-level correctness only, the same
caveat already applied to OpenSubsonic/Jellyfin (items 31/32/33) and
Spotify/YouTube (item 36 below).

**35. DLNA/UPnP** — Partial (closed 2026-08-13, was genuine 0%). New
`DlnaPlugin` (`Omnis-Plugins/lib/dlna_plugin.dart`) is a real client to
a genuinely different *kind* of protocol from OpenSubsonic/Jellyfin/
Plex — no JSON REST API, no username/token at all: discovery is SSDP
(a UDP multicast `M-SEARCH`, UPnP's own HTTP-over-UDP variant), and
browsing is a SOAP action (`ContentDirectory#Browse`) whose response
embeds DIDL-Lite XML as double-encoded escaped text inside another XML
document. This needed a new dependency (`xml: ^6.5.0`, added to
`Omnis-Plugins/pubspec.yaml` — no XML parser existed anywhere in either
repo before this) and a new I/O primitive not used anywhere else in
either codebase (`dart:io`'s `RawDatagramSocket` for raw UDP).

Discovery is behind an injected `SsdpTransport` interface (real impl:
`UdpSsdpTransport`, a fake in tests) — the same "wrap the one
non-mockable primitive so the surrounding logic stays fully unit-tested"
approach every `http.Client`-injecting plugin in this repo already uses,
just for a socket instead of an HTTP client. This is what let SSDP
response parsing, device-description XML parsing, SOAP request/response
handling, and DIDL-Lite parsing all get real test coverage without a
real socket or a real DLNA server anywhere near the test environment.

Caught and fixed a real bug during development, exactly the kind a
plugin like this actually needs tests to catch: `friendlyName` and
`URLBase` live under `<root><device>` in a real UPnP device-description
document, not as direct children of `<root>` itself. An initial
direct-children-only lookup (matching the pattern used elsewhere for
fields that genuinely are direct children, like a `<service>`'s own
`serviceType`/`controlURL`) silently missed both and fell back to using
the server's bare IP address as its display name — a test asserting
the real `friendlyName` value ("Test Media Server") came back caught it
immediately; fixed by switching those two specific lookups to a
recursive `findAllElements` search across the whole document.

Each track's `streamUrl` (new `TrackType.dlna` on `plugin-api-v0.12.0`)
is the real `<res>` URL a `Browse` response points at — playable with
zero `AudioEngine` special-casing, the same as every other
`streamUrl`-bearing type — and typically needs **no authentication at
all** on a trusted local network, unlike every self-hosted provider
this session added before it. UI is folder navigation (discover
servers → open one → browse into/out of containers → play a track),
not a search box like the other three server plugins: UPnP's optional
`Search` action isn't consistently implemented across real servers, so
`Browse`-based folder navigation is the only universally-correct
choice, not a shortcut.

16 tests, covering SSDP response parsing (including deduplicating
multiple responses pointing at the same `LOCATION`, and honoring an
explicit `URLBase` over the description document's own URL), a server
with no `ContentDirectory` service being skipped rather than treated as
usable, one server's description fetch failing without aborting
discovery of the others, real DIDL-Lite parsing (folders, tracks,
non-audio items filtered out, an item with no `<res>` skipped rather
than producing a track with no stream URL, missing
artist/album/genre/duration all degrading sensibly rather than
crashing), and the exact real SOAP request shape (`SOAPAction` header,
`ObjectID`/`BrowseFlag` body).

**A real, documented, and specifically more severe limitation than
every other Phase 5 plugin's "not exercised against a live server"
caveat**: Android filters incoming WiFi multicast packets by default,
and actually *receiving* SSDP responses on a real Android device
normally requires the app to hold an acquired
`WifiManager.MulticastLock` — obtained via a platform channel this
plugin does not implement (would mean new Kotlin code in
`android/app/src/main/kotlin/`, untouched anywhere else this session).
Without it, `discoverServers()` may find nothing on some real Android
hardware even with a real, reachable DLNA server present on the same
network, despite the SSDP/SOAP/DIDL-Lite protocol logic itself being
correct and fully tested. Deliberately did not add the
`CHANGE_WIFI_MULTICAST_STATE` manifest permission alone without the
corresponding lock-acquisition code — an unused permission declaration
would read as "handled" when it isn't; the honest record of this gap is
this doc entry and the plugin's own doc comment, not inert manifest
scaffolding. Real, separate work: a platform channel (or an existing
third-party Flutter plugin, if a suitable one exists) to acquire and
hold the lock for the discovery window.

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

**41. Radio** — Partial (was genuine 0%, closed 2026-08-13). New
`RadioPlugin` (`Omnis-Plugins/lib/radio_plugin.dart`) is a real client
to the free, keyless Radio Browser directory API
(`de1.api.radio-browser.info`) — `searchStations`/`topStations`/
`stationsByTag`, all real HTTP calls, per-entry defensive JSON decoding
(one malformed station in a response can't wipe the rest), converting
each station to a plain `BaseTrack` (`type: TrackType.radio` — a new,
additive `TrackType` value added in `plugin-api-v0.7.0`; `duration: 0`
since a live stream has none; `streamUrl` set to the station's real
Icecast/Shoutcast stream). Playback needed **zero** engine changes:
`AudioEngine.uriFor` already plays any track with a `streamUrl` set,
the exact path YouTube/Spotify tracks already use — a station is just
another track to the player. New "Radio" bottom-nav tab
(`lib/ui/radio_page.dart`): search box + a default "top stations" view,
tapping a result sets the queue starting at that station and plays.
Caught and fixed a real bug while writing this: the `bytag` endpoint's
tag was being run through `Uri.encodeComponent` *and then* handed to
`Uri.https`'s already-encoding `unencodedPath` parameter, which
would've double-encoded any tag with a space (e.g. "80s hits" →
literal `%2520` in the request path, silently returning zero results
for any multi-word tag) — a test asserting the decoded path segment
caught it immediately. Still gaps: talks to a single fixed API mirror
rather than the full DNS-round-robin server discovery Radio Browser's
own docs recommend at production scale (reasonable for one app's search
traffic, but a documented simplification); no manual/custom stream URL
entry for a station not in the directory. Play history is a real but
half-working case: `MainCore.recordPlay` fires unconditionally on track
start, so a played station's `radio:<uuid>` id does get a genuine
`PlayHistoryStore` entry, same as any other track — but
`HomeDashboardPage`'s "Recently Played"/"Most Played" rows join those
history entries against `LibraryRepository`'s persisted library
(`libraryById[s.trackId]`) to render them, and a radio station is never
saved into that library (it's fetched live from the API, not
scanned/imported) — so the entry is recorded but silently invisible on
Home. No favorites integration for stations either. Both are real,
distinct follow-up work, not attempted here.

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

**43. AI** — Partial (closed 2026-08-13, was genuine 0%). The spec
calls this "a major optional ecosystem" (§21) and names eight distinct
capabilities: natural language search, playlist creation, metadata
cleanup, tagging, recommendations, a library assistant, voice control,
and music discovery. This pass builds exactly one of them, deliberately
— playlist creation, the spec's own headline example almost verbatim
("Make me a two-hour workout playlist").

A real `IAIProvider` capability interface now exists
(`packages/omnis_plugin_api/lib/service_interfaces.dart`) — genuinely
async (`Future<List<BaseTrack>> buildPlaylistFromPrompt(prompt,
library)`), unlike `IQueueBuilder.buildQueueFor`, which is synchronous
by design (built for `SmartPlaylistPlugin`/`QueuePresetPlugin`'s
on-device deterministic matching, not a network round-trip) — a real
architectural reason this needed its own interface rather than reusing
the existing queue-building one.

The first implementation, `AIPlaylistPlugin`
(`Omnis-Plugins/lib/ai_playlist_plugin.dart`), calls Anthropic's real
Messages API with a user-supplied key (never an embedded one — the same
"bring your own credential" pattern `MetadataEnrichmentPlugin`'s
Last.fm/Discogs keys already established). The model is given a compact
JSON summary of the real library (id/title/artist/genres/mood/bpm/
duration — only fields `BaseTrack` actually has, nothing fabricated)
and told to reply with *only* a JSON array of track ids picked from
that list. Every returned id is checked against the library before use
— an id the model invented, or one outside the sample it was shown, is
silently dropped rather than producing a broken/missing track in the
queue. This is the load-bearing guarantee that makes the feature safe
to ship at all: a test asserts a fabricated id in the model's response
is dropped, not surfaced.

Two real, deliberate limits, both tested and documented in the plugin's
own doc comment: (1) the library sample sent to the model is capped at
300 tracks — a real constraint, not full-library coverage, since an
unbounded prompt would have unbounded token cost and no upper size
limit; a request like "find me the deep cuts" has no way to consider a
track outside the sample. (2) The model is instructed to reply with
*only* JSON, but LLMs routinely wrap output in a markdown code fence
anyway regardless of instructions — stripped defensively before
parsing rather than trusted to follow instructions, and specifically
tested.

14 new tests against a mocked HTTP client covering the real Anthropic
request shape (URL, `x-api-key` header, model, prompt+catalog in the
message body), response parsing (happy path, code-fence stripping,
non-JSON text, a non-200 response surfacing the API's own error
message), and the two guarantees above (never-invents-a-track, capped
sample).

Still genuine 0% for every other capability the spec names: natural
language *search* (as opposed to playlist creation), metadata cleanup,
tagging, a recommendation engine (§22, a separate, larger spec section
of its own — listening history/ratings/favorites/skips/BPM/key/mood/
acoustic-fingerprint-driven algorithms like Similar Track/Similar
Artist/Daily Mix), a conversational library assistant ("Which albums
have never been played?"), voice control, and artist-similarity
discovery. Each is real, separate work, not attempted here — the spec's
own framing ("a major optional ecosystem") was accurate; this closes
one deliberately narrow slice of it, not the whole item.

**Not exercised against the real Anthropic API** in this environment —
what's verified is protocol-level request/response handling against a
mocked HTTP client, not a live call with real spend attached (the same
caveat already applied to every other network-backed plugin this
session added).

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

**47. TV mode** — Partial (closed 2026-08-13, was genuine 0%). New
`TvModeLayout` (`lib/ui/player_layouts/tv_mode_layout.dart`) delivers
the UI spec's §44 "TV" requirement close to verbatim — "Large:
Artwork, Text, Controls, Remote navigation. No mouse assumptions." —
as a new selectable Now Playing layout, using the exact same extension
point `CarModeLayout` already established (a class in
`lib/ui/player_layouts/`, one line in `registry.dart`, zero Core
changes).

Deliberately does **not** hand-roll D-pad/keyboard key handling: any
`MaterialApp` already runs a `DefaultFocusTraversalPolicy` that moves
focus between focusable widgets on arrow-key input, and — this is the
part that actually makes "D-pad navigation" a real, not aspirational,
claim — a physical D-pad on a real Android TV/Fire TV device already
arrives at Flutter as those exact same logical arrow keys
(`KEYCODE_DPAD_LEFT`/`RIGHT`/`UP`/`DOWN`/`CENTER` map onto
`LogicalKeyboardKey.arrow*`/`select` before Flutter's widget layer ever
sees them). So the layout's actual, scoped job was: large,
individually-focusable transport buttons in a plain linear order (D-pad
traversal is 1D directional, not 2D-mouse-hover-aware, so layout order
matters more than visual position), with `autofocus: true` on
Play/Pause — a real, common first-run TV-app bug being deliberately
avoided is landing on a screen with *nothing* focused, forcing the
first D-pad press to do something invisible/undefined.

Caught and fixed a real overflow bug during development: the large
fixed sizes (320px artwork, 96px icon buttons) overflowed the default
test viewport's vertical space by 91px — `flutter test`'s own render
assertion caught it immediately, before this ever reached a device.
Fixed with the same `SingleChildScrollView` guard `LandscapeLayout`/
`TopControlsLayout` already use for exactly this "fixed-size content
might not fit every window size" reason, rather than inventing a new
pattern.

4 new dedicated tests do not just check that the layout renders —
one renders at a real phone's logical width (360dp, not this test
file's 800px default) and caught a *second* real overflow the first
fix missed: the button row itself overflowed 17px horizontally, because
sizing Play/Pause proportionally larger than Previous/Next without
reserving the extra width its larger size actually needs broke the
row's total-width budget. Fixed by solving for each button's size from
the real available width directly (a `LayoutBuilder`-driven proportional
split) rather than picking one more fixed number that happened to fit
whatever width was being tested at the time. The other three simulate
real `LogicalKeyboardKey.arrowRight`/`arrowLeft` key events via
`tester.sendKeyEvent` and assert the actual `FocusNode` that now holds
focus moved to the correct button (`Focus.of(element).hasFocus`), and
one sends `LogicalKeyboardKey.enter` (the keyboard-test-harness
equivalent of a D-pad's center/OK button) and asserts the real
`onPlayPause` callback fired, not just that some visual highlight moved.

**Verified end-to-end on the real Android emulator, not just in
widget tests** — the first genuine real-device D-pad verification any
UI work in this repo has had. Selected TV Mode via Settings, started a
real Radio station (MANGORADIO), and sent actual
`adb shell input keyevent KEYCODE_DPAD_RIGHT`/`KEYCODE_DPAD_CENTER`
against the running app. Confirmed *behaviorally*, not by reading
Android's accessibility-focus tree (which turned out not to reliably
reflect Flutter's internal keyboard-focus state at all — a real
discrepancy worth knowing about for any future on-device focus
verification: Android's a11y "focused" attribute via `uiautomator
dump` stayed frozen on the same bounds across a `DPAD_RIGHT` press
that widget tests prove really did move Flutter's internal focus, so
it's not a reliable oracle for this): pressing `DPAD_CENTER` toggled
real playback (pause icon → play icon, with a visible focus-highlight
ring drawn around the button), and pressing `DPAD_RIGHT` then
`DPAD_CENTER` genuinely skipped to a different station (MANGORADIO →
REYFM), proving both that focus really moved to Next and that
activating it really worked — not inferred from a screenshot alone.

**A separate, pre-existing bug spotted while verifying this on a real
device, unrelated to TV Mode**: the *Standard* layout's Now Playing
screen (the default layout, not touched by this change) overflows its
button row by ~4.6px on this same device/window size — the
"Visualizer" button clips off the right edge with a debug overflow
banner in debug builds. Not fixed here (out of scope for the TV Mode
increment that found it), but worth a dedicated fix later — the same
class of bug this increment's own `LayoutBuilder` fix addresses for TV
Mode specifically.

Still genuine 0% for a from-scratch, always-on TV/leanback shell — this
closes one selectable Now Playing layout among several (reached the
same way every other layout is, via Settings → Appearance → Player
layout), not a distinct app mode the whole UI automatically switches
into on a TV device. Specifically still missing: no Android TV
`<leanback_launcher>` intent filter or Fire TV-specific manifest
entries (so Omnis doesn't appear in a TV launcher's app row at all
today), no `banner`/leanback-required assets, no automatic TV-display
detection that would switch to this layout on its own the way §48's
"Multiple UI profiles" describes for a Bluetooth-triggered Car mode
switch, and no TV-specific navigation for any screen *other than* Now
Playing (Library/Settings/Playlist/Radio/Moods are all still the
touch-first phone/desktop layouts — a real D-pad user could still get
stuck trying to reach those, since Flutter's default focus traversal
only helps within whatever's already on screen, it doesn't redesign
those screens' layouts for 10-foot viewing or linear D-pad flow).

**48. Accessibility** — Partial. A real, git-log-verified accessibility
pass (commit `e101b34`): tooltips added to every previously-unlabeled
icon button, `Semantics(label:/hint:)` wrapped around custom
gesture-driven tap targets (full-bleed/karaoke Now Playing layouts, the
mini-player bar, the waveform seek bar with custom increase/decrease
actions, the layout editor's drag handles), `ExcludeSemantics` around
decorative artwork/icons, and widget tests that actually assert on the
semantics tree. Working "Reduce motion" (globally collapses animation
durations to zero via `OmnisMotion`), "Reduce transparency", and
"Haptic feedback" settings — now surfaced in a dedicated **Accessibility**
settings category (`lib/ui/settings/accessibility_settings_page.dart`,
closed 2026-08-13), per §45's taxonomy (`Appearance, Playback, Audio,
Library, ..., Accessibility, Keyboard, ...`) explicitly listing it as
its own top-level category, not a sub-section of Appearance. Moved (not
duplicated) verbatim from `appearance_settings_page.dart` — same
`AppSettings` properties, same behavior, only the surfacing location and
search-index `category` field changed. `AppSettings.reduceMotionEnabled`
etc. are unchanged. Found and fixed a real regression while adding the
new category card to `settings_page.dart`'s home list: the extra card
pushed "Plugins"/"Backup" (now the 6th/7th cards) past the default test
viewport's `ListView` sliver cache extent, breaking 3 pre-existing
widget tests in `settings_page_test.dart` that assumed those cards were
already mounted without scrolling — fixed by adding the same
`dragUntilVisible`/`ensureVisible` pattern the file's own "Plugins"
test had already established for exactly this situation (a real UI
behavior change in the running app too, not just a test artifact: those
two cards genuinely sit one card's height further down now on a small
screen). Still gaps: no high-contrast mode, no colorblind-safe state
option, no app-wide text-scale setting (only a 4-step lyrics-only text
size, `lyricsTextSize`, deliberately left in Appearance — it's a lyrics
display option, not moved here), and — significant — **zero keyboard
navigation/shortcuts anywhere** (no `Shortcuts`/`FocusTraversalGroup`/
`CallbackShortcuts` usage found), so the UI spec's global Ctrl+K search
(§37) and command palette (§38) don't exist either, on top of not being
an accessibility gap in their own right. No voice control, no
switch-input support, no RTL/localization wiring (`AppLocalizations`
isn't used).

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
