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
- **§7 — Queue engine depth.** `playNext()` exposure through
  `PluginContext` and a track context menu closed 2026-08-14; queue
  history (an automatic, capped rolling log) and queue snapshots
  (permanent, user-named saves) closed 2026-08-15 — see item 2's
  build-log entry. Still no smart/rule-based continuation (mood/artist/
  genre/similar-track auto-continuation), no advanced shuffle modes
  beyond what `ShuffleRepeatPlugin` already does, no queue rules/
  exclusions, no multiple queue sources.
- **§4/§41 — Real indexed database.** Every store is still a JSON file
  (now atomic-write-safe and per-entry-decode-safe, but not an indexed
  DB). Schema migration system closed 2026-08-14: `lib/core/
  schema_versioning.dart` gives every store (`LibraryStore`/
  `PlaylistStore`/`PlayHistoryStore`/`RecoveryJournal`) a versioned
  envelope (`{"schemaVersion": N, "data": payload}`) and a real
  migration-dispatch mechanism — no actual field/shape migrations exist
  yet (nothing has needed one), but the version detection, an old
  bare-shape file transparently reading as version 0, and the
  version-to-version dispatch loop are all real and tested, not just a
  number. Still no multi-source libraries, no SQL-like query layer, no
  scheduled integrity check.
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
  `year:`/`rating:` (the last joined 2026-08-13). Quoted multi-word
  field values (`album:"greatest hits"` — previously split into two
  AND'd terms) closed 2026-08-14: a small tokenizer keeps a `"..."` span
  intact (quotes stripped, internal whitespace preserved) instead of
  splitting on it — the field-value regex itself already accepted
  multi-word values, it just never got the chance to see one. Still
  missing: `bpm:`/`format:`/`bitrate:`/`lyrics:`/`missing:`/`duplicate:`
  operators (each needs a feature/data source that still doesn't
  exist), natural-language queries, and **no search scope beyond the
  Library page** — no global Ctrl+K command palette (§37/§38) searching
  settings/commands/playlists/moods in one place (the global keyboard
  *shortcuts* closed 2026-08-14 under item 48 are a separate thing —
  fixed playback bindings, not a searchable command palette).
- **§9 — `rating:>=4` search/smart-playlist operator not wired.**
  `RatingsPlugin.ratedAtLeast()` exists specifically as the building
  block for this, but `filterTracks` is a pure `BaseTrack`-only function
  with no plugin access — wiring it in means either the caller
  pre-joining ratings onto tracks before calling `filterTracks`, or a
  deliberate design decision about whether `filterTracks` should gain a
  plugin dependency at all.
- **§9 — Bulk "rate selected" action closed 2026-08-14.** Favorites'
  one-tap bulk toggle in selection mode doesn't fit ratings directly (a
  specific 1-5 value, not a binary), so a new "Rate selected" button
  opens the same `_StarPicker` dialog `_rateTrack` already uses for a
  single track, starting at `0` (no single "current" rating makes
  sense across a mixed-rating selection), and applies whichever star is
  tapped to every selected track via `RatingsPlugin.setRating`.
- **§13 — Playlist folders/groups** closed 2026-08-15: a new, main-
  repo-only `PlaylistFolderStore` (deliberately not a field on the
  shared `Playlist` model, to avoid a cross-repo version bump for a
  purely local UI concern) backs create/rename/delete-folder and
  "Move to folder…" actions on `PlaylistPage`. Collaborative playlists
  and XSPF/PLS import/export still don't exist (M3U/M3U8 does, plus a
  full `SmartPlaylistPlugin`).
- **§11 — Metadata provider framework.** Only `MetadataEnrichmentPlugin`
  (MusicBrainz + optional Last.fm) exists — not the `IMetadataProvider`-
  pluggable-provider framework the spec describes (Discogs/Deezer/Genius
  etc. as swappable alternatives a user could install instead).
- **§12 — Artwork provider framework.** Embedded artwork, Android
  MediaStore artwork, and `ArtistImagePlugin` (Deezer search) exist —
  no `IArtworkProvider` framework (Cover Art Archive/Fanart.tv lookup),
  no manual/drag-drop artwork override.
- **§20 — Guided "Music Library Cleanup" report.** Closed 2026-08-15.
  The spec describes a one-button "Analyze Library" producing a report
  ("1,421 missing artwork, 832 inconsistent artists, ..." style) with
  guided cleanup — now real: `LibraryCleanupAnalyzer` computes all
  eight named categories from already-scanned data, and
  `LibraryCleanupReportPage` (reached from the Library page's tools
  menu) lists each with a drill-down that either fixes the track
  directly (via the existing `TagEditorDialog`/`_editTags`) or points
  at `library_page.dart`'s pre-existing narrower duplicate/short-track
  cleanup tool for the categories that tool already covers, rather than
  a second implementation of the same merge logic.

  Undo/backup/restore for tag edits closed 2026-08-14 (item 17):
  `TagEditorPlugin.writeTags` snapshots the pre-write tag field values
  (decoded from bytes already in memory, not a second disk read) on
  every successful write, keyed by file path — a small JSON blob, not a
  full-file byte copy, since a whole-file backup per edited track
  wouldn't scale to a library-wide batch operation. New
  `undoLastEdit`/`hasUndoSnapshot`, wired into both a real single-track
  "Undo last edit" button (`TagEditorDialog`) and a real "Undo" action
  on the batch auto-tag completion snackbar (`library_page.dart`),
  reverting every track a batch actually changed — file and in-memory/
  persisted library both. Two real bugs caught purely by writing tests
  against a real ID3 file: restoring a field to `null` silently left
  the edited value in place (title/artist/album are unconditionally
  passed to the encoder regardless of null-ness, unlike a custom
  `TXXX` field, so only an empty string genuinely clears them); and an
  early version deleted the undo snapshot using a stale in-memory copy
  read before the restore's own write ran, erasing the fresh snapshot
  that write had just correctly saved — the identical "lost update from
  a stale read" bug class this session already fixed in
  `LibraryStore`/`PlayHistoryStore` the same day, recreated by hand and
  caught the same way.

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
`BaseTrack.replayGain` (populated from existing file tags via
`TagEditorPlugin`/`MediaScanner`) and applies it as a gain multiplier,
plus a user preamp (-6..+6 dB). Album-gain mode toggle closed
2026-08-15: `trackGain` and `albumGain` were both already being parsed
into `BaseTrack.replayGain`, but `setReplayGain` only ever read
`trackGain` — a persisted toggle now prefers `albumGain` when enabled,
falling back to `trackGain` for a track with no album gain tag. Omnis
still never *scans*/computes ReplayGain itself — it only consumes
values some other tool already wrote — and there's still no true-peak/
limiter clip protection.

**20. EQ** — Partial. `EqualizerPlugin` has two real modes: hardware
(Android only, drives the OS `android.media.audiofx.Equalizer` via
`HardwareEqBand`) and virtual (a fixed 3-band ±12dB trim as a gain
contribution, everywhere else). Bands persist *per connected device*
(via `IDeviceConnectivityProvider`/`BluetoothPlaybackPlugin`) — real
per-device profiles, but not per-artist/per-album. No selectable band
count, no parametric mode, no EQ at all on desktop beyond the 3-band
trim (no `AVAudioUnitEQ`, no WASAPI APO).

**21. Output devices** — Partial (closed 2026-08-14, was 0% for device
*selection*). Real Settings → Playback & Audio → "Output devices" page
(`lib/ui/settings/output_devices_page.dart`) plus its controller
(`lib/core/output_device_controller.dart`).

The pleasant surprise here: this needed **zero new native
platform-channel code**, unlike the home-screen-widget increment built
immediately before it in the same session. `audio_session` — already a
transitive dependency via `just_audio`, doing nothing more exotic than
what `BluetoothPlaybackPlugin` already used it for — turns out to
expose real device *listing* cross-platform
(`AudioSession.getDevices()`, `devicesChangedEventStream`) and real
device *selection* on Android via `AndroidAudioManager
.setCommunicationDevice()` (API 31+). That method's name is misleading:
despite "communication," it's documented as the modern,
general-purpose replacement for the older per-`AudioTrack`
`setPreferredDevice()`, and it's what this app's actual playback
session routes through — not a voice-call-only API as the name might
suggest.

Design: `OutputDeviceSource` is a new seam interface (same
"small, purpose-specific interface + a fake for tests" pattern already
established by `PlaybackEngine`/`HomeWidgetTrackSource` elsewhere in
this app) with a real `AudioSessionOutputDeviceSource` implementation
and a `FakeOutputDeviceSource` test double
(`test/fakes/fake_output_device_source.dart`). `classifyOutputDeviceType`
maps `audio_session`'s dozen-plus raw `AudioDeviceType` values down to
six UI-facing kinds (speaker/wired/bluetooth/usb/hdmi/other) — the one
piece of this feature with no platform channel involved at all, and so
the one piece with real, direct, non-faked unit tests.

**Honest about the selection API's real limits, not just "not yet
built"**: `selectDevice`/`useSystemDefault` explicitly check
`Platform.isAndroid` and fail soft with a specific, surfaced-in-the-UI
reason on anything else (iOS/desktop) or on pre-31 Android (where
`setCommunicationDevice` throws rather than returning false) — the
`supportsDeviceSelection` getter also greys out every radio tile
up-front so a user isn't invited to tap something that can't work. The
device *list* itself keeps working on every platform regardless — only
the "pick one" half is Android-31+-only, because that really is the
current state of Android's public API surface for this (there is no
general "force output to device X" call below API 31, and no
equivalent at all on iOS/desktop through this dependency).

A real, if minor, finding while writing tests (not an app bug): the
"System default" radio tile's `value` is `null`, matching the page's
initial `groupValue` of `null` — so a test that taps "System default"
as its very first action sees no `onChanged` call at all, because
Flutter's `Radio` correctly treats tapping an already-selected option
as a no-op. Fixed by having the test select a different device first,
then tap back to "System default" as a genuine state change.

Still missing: no USB DAC sample-rate/bit-depth negotiation UI (item
22's remaining DSP-chain gap is closely related but distinct — this
increment is about *which device*, not *what bit depth to that
device*), no per-device volume (only the pre-existing per-device-name
EQ keying from item 20), and no HDMI/Cast/DLNA/AirPlay output beyond
whatever `audio_session`'s device list already reports as connected —
none of those are alternate *routes* this app can initiate, only
things the OS might already be doing. **Not exercised against real
hardware** — same "protocol/API-level correctness only" caveat this
session has applied consistently to `BluetoothPlaybackPlugin` and
every server-connectivity plugin (OpenSubsonic/Jellyfin/Plex/DLNA).

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
AIFF/AIFC parsing closed 2026-08-14 (was the first of the four
extension-only formats to get real parsing, chosen since it's the
closest cousin to the already-parsed WAV — both simple, linear,
chunk-based containers): walks `FORM`/`COMM` chunks, big-endian and
word-aligned the same way RIFF chunks are, for real channels/bit-depth/
sample-rate, and a computed PCM bitrate (`sampleRate * channels *
bitDepth`, since unlike WAV's `fmt` chunk, AIFF's `COMM` has no
byte-rate field to read directly). The one piece needing genuinely new
decoding: AIFF stores its sample rate as an 80-bit IEEE 754
extended-precision float (explicit rather than implicit leading
mantissa bit, unlike ordinary 32/64-bit floats) — decoded with a new,
from-scratch `_decodeExtended80`. AIFC (the compressed variant, sharing
AIFF's container shape plus a `compressionType` field appended to
`COMM`) is distinguished via the `FORM` chunk's own type field and only
gets a computed bitrate when its declared compression is actually
uncompressed (`NONE`, or `sowt` — byte-swapped PCM); a genuinely
compressed codec (e.g. `ima4`) still reports real channels/rate/depth
but leaves `bitrateKbps` `null` — the same "don't guess what can't be
derived honestly" stance the MP3/WAV readers already hold, extended
here rather than reused, since AIFC's bitrate genuinely can't be
computed from the same formula. Two real bugs, both caught purely by
testing against independently hand-packed bytes (a from-scratch
`BigInt`-based 80-bit-float encoder, not the reader's decode logic run
backwards) rather than by inspecting the parsing code: an off-by-two
`COMM` field offset (bit-depth/sample-rate read two bytes past where
they actually start — a well-formed test file silently decoded to
all-null fields instead of throwing, the harder class of bug to catch)
and a missing `'aifc'` case in the format-dispatch `switch` (every
`.aifc` file silently fell through to the generic unknown-extension
path, never reaching the new reader at all). 7 new tests.

Ogg Vorbis/Opus parsing closed the same day, as the second format
(after AIFF): reads the first Ogg page (`OggS` capture pattern, a fixed
header, and the segment-table lacing values summed to get the exact
packet length) and parses its payload — the stream's identification-
header packet — sniffed by signature (`"\x01vorbis"` vs `"OpusHead"`)
rather than trusted from the `.ogg`/`.opus` extension, so a
mismatched extension still identifies correctly. Real sample rate and
channel count for both; no bitrate for either, a deliberate scope
decision: Vorbis's header "nominal bitrate" field is spec-documented
as a non-binding encoder hint, not a real derivable number the way
MP3's Xing-derived or FLAC's file-size/duration-derived averages are
(a real Ogg average would need the *last* page's granule position — a
backward scan near EOF for variable-sized pages, genuinely separate
work), and Opus's header has no bitrate field at all. Opus always
reports `48000`Hz regardless of its header's own "input sample rate"
field, since the decoder always outputs at 48kHz and that field is
just informational provenance about the source material. A page whose
payload matches neither signature (a real Ogg FLAC or Theora stream)
degrades to a generic `'Ogg'` label rather than misreporting or
crashing. 6 new tests, all passing on the first real run — zero bugs
found this time, worth noting against AIFF's two, as a data point that
getting the pattern right once (hand-packed independent-encoder tests,
real header-format research) pays off on the next format.

Still gaps (M4A closed 2026-08-14, the same day as this note's prior
gap list): `AudioFormatReader._readM4a` now walks the real MP4 box
tree (`moov`→`trak`→`mdia`→`minf`→`stbl`→`stsd`) to find the audio
sample entry, reading AAC's real sample rate/channels from `esds`'s
buried `AudioSpecificConfig` (overriding the sample entry's own
placeholder legacy fields, a well-documented MP4 quirk) and ALAC's
bit depth/channels/sample rate/bitrate directly from its magic-cookie
box — see item 22's build-log entry for the full detail. A bare
`.aac` file (an ADTS elementary stream, not an MP4 container at all)
is still label-only, deliberately out of this scope. WMA closed
2026-08-15 too, the fourth and last remaining container:
`AudioFormatReader._readWma` parses ASF's flat GUID-object header
(simpler than M4A's box nesting, once written — turned out to have
less surface area than expected) down to the audio Stream Properties
Object's embedded `WAVEFORMATEX` structure for real sample rate/
channels/bit depth, plus a real encoder-declared average bitrate. With
this closed, every container `AudioFormatReader` recognizes now gets
real header parsing except a bare `.aac` ADTS elementary stream, which
remains deliberately out of scope (not a container format at all). And
the DSP/output half is still fully 0%:
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

**26. Dependency resolution** — Partial (both the manifest-declared
gaps this section originally flagged are now closed, 2026-08-14; the
bundled-plugin case below is unchanged). Bundled-plugin ordering is
still code-level, not manifest-driven: `MusicPlugin.requiresSequentialInit`
plus `PluginManager.initializeAll()`'s two-round init, used for two
documented real dependencies (`QueuePresetPlugin` after
`SmartPlaylistPlugin`; `EqualizerPlugin` after `BluetoothPlaybackPlugin`)
— no handling of a dependency disappearing there either (disabling
`BluetoothPlaybackPlugin` just makes `EqualizerPlugin`'s device-profile
lookup silently return null, no warning); that's a distinct, still-open
gap this section originally didn't separate from the manifest case.

For *external* (downloaded) plugins, both originally-flagged gaps are
now real: `PluginManifest.dependencies` (a plugin-id list) is enforced
at install time (`PluginManager._registerInstalledPlugin` throws,
naming exactly which declared dependencies aren't installed) and
re-checkable on demand via `PluginManager.missingDependenciesFor` (the
Plugins page warns if a dependency's since been uninstalled — not just
a one-time install-time gate). `minOmnisVersion` is now enforced too,
in the same `_registerInstalledPlugin` gate: compared against a new
`omnisCoreVersion` constant (`lib/core/omnis_version.dart`, manually
kept in sync with `pubspec.yaml`'s `version:` — reading it live would
need a new `package_info_plus` dependency for one narrow check) via the
existing `compareVersions` semver comparator already used for
update-checking; a plugin requiring a newer Omnis than is running is
refused at install/update time with a message naming both versions.
Still no dependency *graph*/resolver (a single flat list, not
transitive resolution) and a missing dependency is detected/surfaced,
never auto-resolved (no "install this for me" flow) — both real,
distinct, still-open follow-ups.

**27. Permissions** — Solid. Manifest `permissions:` map to real
`dart_eval` grants (`FilesystemPermission`, `LibraryReadPermission`,
`EventsPermission`, `PlaybackControlPermission`, and now
`NetworkPermission`), checked via `PluginRuntime.hasPermission`/
`Runtime.assertPermission`. Plain-English disclosure via
`plugins_page.dart`'s `_confirmPermissions` dialog, shown *before* any
plugin code executes. Granular network scoping closed 2026-08-15:
`network:host.example.com`-shaped manifest entries (exactly the spec's
own `network:musicbrainz`-style ask) grant a real, per-host-enforced
`NetworkPermission.url(...)`, checked against the actual requested URL
by a new `httpGet` bridge function — the first bridged capability that
lets a sandboxed plugin reach the network at all. Remaining gap:
`storage` is still coarse/all-or-nothing (`FilesystemPermission.any`) —
dart_eval has no per-directory scoping at that layer the way it already
had a ready-made per-host primitive for network. No `privacy:`/
`data-collected:` manifest section parsed or shown.

**28. Plugin health** — Partial. `PluginSandbox.healthRecords` (capped
at 200) is populated automatically on every sandboxed failure, with a
live listener mechanism and a real "Plugin Health" section at the
bottom of the Plugins page (name, hook, human-readable reason, raw
message, timestamp, "Dismiss all").

Both named-open gaps closed 2026-08-14. Per-plugin retry/reset:
`PluginManager.resetPlugin()` — a genuine `disable()`→`enable()` cycle,
not a full re-`initialize()`, since most sandboxed failures are bad
runtime state a plugin's own `enable()` already resets — reached via a
"Reset" button on each health record's card, clearing that plugin's
health history afterward so the dashboard reflects its fresh start.
Auto-disable on repeated failure: `PluginManager` now listens to
`PluginSandbox`'s own health-change notifications and calls the real
`disablePlugin()` for any plugin that racks up 5 failures within a
rolling 5-minute window — window-based rather than a true
consecutive-since-last-success counter, since `PluginHealthRecord`s
only exist for failures with no "hook succeeded" event to reset a
consecutive counter against.

Still gaps: no dedicated health-center page (it's a section of the
general Plugins page, not the spec's separate 🟢/🟡/🔴-per-plugin view),
no heartbeat (health is purely reactive — a silently-hung plugin that
never throws is never detected).

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

Backup-before-update + rollback closed 2026-08-14. Root cause of the
original gap: `installFromUrl` resolves a plugin's directory name
*deterministically* from its own source URL, so re-installing the same
plugin during an update always targets the exact directory the working
version already lives in, and unconditionally deletes it before
extracting — a download failing partway (network drop, corrupt zip, a
newly-invalid manifest) previously left that directory empty or
partially written while the `ManagedPlugin` record stayed registered
with its services already torn down by `updatePlugin`'s own teardown
step: installed in name only, silently broken. Fixed with three new
`PluginInstaller` methods (`backupPluginDirectory`/
`restorePluginBackup`/`discardPluginBackup`, a recursive directory
copy to a location *outside* the plugins root — deliberately outside,
since `listInstalled()` treats every folder under the plugins root
containing an `omnis_plugin.yaml` as an installed plugin, and a backup
is a second copy of exactly that file). `updatePlugin()` snapshots
before attempting the download, discards the snapshot on success, and
on failure restores it and re-registers the plugin from the restored
directory (a full `installFromPath`/`_registerInstalledPlugin` cycle,
not just files copied back) before rethrowing — a failed update now
leaves the previous working version running, not a corpse. A rollback
that itself fails surfaces both failures in one message. 9 new tests,
all passing on the first real run.

Still gaps: no automatic/background/scheduled checking (purely
user-initiated, one tap at a time), and — a real, structural limit, not
a missed detail — update detection only works for a GitHub
`tree/branch[/subfolder]` or bare-repo source URL; a plugin installed
from a direct `.zip` link has no general way to derive a single raw
file's location from an arbitrary zip URL, so `fetchRemoteManifest`
returns `null` for those (silently skipped in `checkForUpdates`, not
reported as a failure).

**30. Marketplace/catalog** — Partial, narrower than when this section
was first written. A real permission-confirmation install flow exists
for two paths: a catalog (`PluginInstaller.fetchCatalog()`, closed
2026-08-14 — fetches a real, live `catalog.json` published at the root
of the `Omnis-Plugins` repo via `raw.githubusercontent.com`, falling
back to the hardcoded `officialPluginCatalog` list only when that fetch
fails) and a free-text "paste a GitHub/zip URL" field
(`PluginInstaller.installFromUrl` — zip-bomb/zip-slip guarded,
manifest-validated). The catalog is now searchable too (closed
2026-08-14, same day): `PluginsPage` filters the fetched/fallback list
by name or description via a `TextField` above it, case-insensitively,
with an explicit "no plugins match" message rather than a silent empty
list. `docs/PLUGIN_SECURITY.md` still states outright: "No plugin
registry or curation today... Installing means trusting whoever's
GitHub URL you pasted" — that half of this item is genuinely unchanged
and deliberately so; the two closures above only ever addressed
*discovery/browsing*, not curation/trust. Still no categories/featured/
ratings/screenshots, and no `omnis-plugin-hub` meta-repo — `Omnis-Plugins`
itself is still a flat package of plugin *sources*, not a hub of
references to separate plugin repos as spec §6.2 describes.

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

**38. Other providers** — Partial (Emby closed 2026-08-14, was genuine
0% as music providers). New `EmbyPlugin` (`Omnis-Plugins`) is a real
REST client to a self-hosted Emby server — session-token auth via
`/Users/AuthenticateByName`, `/Items` search returning genuinely
playable `BaseTrack`s (new `TrackType.emby` on `plugin-api-v0.13.0`,
real `streamUrl` at Emby's own `/Audio/{id}/stream`). Emby was
tractable where the rest of this list isn't: it's free and
self-hostable with no developer-registration gate at all, unlike every
other name here.

Deliberately **not** built by subclassing or sharing a client with
`JellyfinPlugin`, even though the two protocols are close enough that
`EmbyPlugin`'s request/response handling is close to line-for-line the
same as `JellyfinPlugin`'s (Jellyfin began in 2018 as a fork of Emby,
and Jellyfin's own client code still sends the `X-Emby-Authorization`
header name for backward compatibility with servers/tooling built
against Emby). Kept as two separate plugins for the same reason
`PlexPlugin`/`DlnaPlugin` are each their own plugin despite occasional
protocol-shape overlap elsewhere in this codebase: they're two
different real servers a user could each independently be running, and
collapsing them into one "smart" client would make the one thing this
whole self-hosted-server cluster's plugin descriptions promise —
"connect to *this specific* server" — murkier, not simpler, for a
real-and-honest gain of maybe 200 lines of code saved. 17 new tests
mirror `JellyfinPlugin`'s test suite's exact structure and coverage
(auth, search parsing, per-entry defensive decoding, the bounded-401-
retry test), generated from it via a scripted find/replace, then
verified passing on their own rather than assumed correct by
similarity.

Apple Music, SoundCloud, Bandcamp, Tidal, Qobuz remain genuine 0% as
music providers, and are judged **not tractable** from this
environment specifically because each requires a closed and/or paid
developer-account registration this environment cannot obtain (Apple
Music: paid Apple Developer Program membership; SoundCloud: new API
key registrations have been closed since 2023; Tidal/Qobuz: partner/
business API access, not self-serve; Bandcamp: no official public API
of any kind, unofficial-only) — a real, durable blocker, not a
scheduling choice, so this item stays partial rather than fully closed
regardless of how many future sessions revisit it, unless one of those
providers' access policies changes. `ArtistImagePlugin`'s Deezer call
remains explicitly documented as artist-photo lookup only ("not for
playback or any Deezer-catalog feature") — not a Deezer music
provider, and unaffected by this increment.

**Not exercised against a real Emby server** — protocol-level
correctness only (mocked HTTP client), the same caveat already applied
to every other self-hosted-server plugin this session
(OpenSubsonic/Jellyfin/Plex/DLNA).

### Phase 6 — Discovery

**39. Recommendations** — Partial. The "Moods" page (`_MoodsPage` in
`home_page.dart`) is effectively one algorithm from the spec's list — a
crude Mood Radio, built by trying each registered `IQueueBuilder`
(`SmartPlaylistPlugin` then `QueuePresetPlugin`) until one returns a
non-empty queue.

Two of the spec's other named algorithms closed 2026-08-14, both as new
presets on `QueuePresetPlugin`, alongside its original BPM/genre ones:
"Forgotten Favorites" (real most-played tracks, via
`IPlayHistoryProvider`, that have dropped out of the recent-plays
window) and "Rediscover" (tracks rated 4+ stars, via `IRatingsProvider`,
also absent from recent plays) — the first two real consumers of
`ScrobblePlugin`'s and `RatingsPlugin`'s persisted signal data for a
recommendation respectively. Deliberately distinct algorithms, not one
duplicated under two names: "Forgotten Favorites" ranks by objective
play count, "Rediscover" by explicit rating, so a track can qualify for
one without qualifying for the other (a five-star track played only
once would never rank among the *most played*, but is exactly what
"Rediscover" is for). Both share the same honesty stance — empty,
never a misleading whole-library-shuffle fallback, when the data they'd
need isn't available.

Still 0% for every other named algorithm (Similar Track/Artist, Album/
Artist/Genre Radio, Discovery, Deep Cuts, New Releases, Daily/Weekly
Mix, Energy Flow) — confirmed via repo-wide search, zero matches. No
provider-neutral recommendation framework/interface (each preset is
still its own bespoke method on `QueuePresetPlugin`, not built against
a shared "recommendation algorithm" abstraction). `favorites_plugin.dart`'s
data (as opposed to `ratings_plugin.dart`'s, now consumed by
"Rediscover") still isn't used by any recommendation.

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
traffic, but a documented simplification). Manual/custom stream URL
entry for a station not in the directory closed 2026-08-15 — see item
41's build-log entry: a new `CustomRadioStationStore` persists
user-entered name/URL pairs, converted to an ordinary `BaseTrack` so
favoriting/queueing/history all work with zero special-casing. Play history's "recorded but silently invisible on Home" half closed
2026-08-14. Root cause was confirmed broader than radio: any played
track never scanned/imported into `LibraryRepository` — not just a
station, but equally a Spotify/YouTube/Jellyfin/Plex/Subsonic/DLNA/Emby
track — shared the identical failure, since `HomeDashboardPage`'s join
only ever checked `libraryById[s.trackId]`. Fixed generally, not with a
radio-specific special case: new `TrackPlayStats.trackSnapshot` field —
`PlayHistoryStore.recordPlay` now captures a full `BaseTrack.toJson()`
at record time whenever `track.type != TrackType.local` (a local
track's complete metadata already lives in the scanned library, so a
second copy would be pure waste) — and the dashboard's join falls back
to `BaseTrack.fromJson(snapshot)` when the library lookup misses,
wrapped so a corrupted snapshot skips just that entry rather than
breaking the whole load. 6 new tests, including a widget test that
deliberately never calls `LibraryStore.save()` at all, so it can't
accidentally pass via the old library-join path instead of proving the
new snapshot fallback. Favorites integration closed 2026-08-14 too:
`radio_page.dart` now has a real per-station heart-icon toggle backed
by the same `FavoritesPlugin` every other track already uses. What's
still genuinely open is narrower than before: the Playlists page's
aggregate "Favorites" smart list only searches the scanned library, so
a favorited-but-unscanned station is correctly marked favorite but
still invisible in that one aggregate view — the same "recorded but
not surfaced" shape as the history gap this section already describes,
left unfixed here since `FavoritesPlugin` would need its own real
snapshot-storage addition (it only persists ids today) to close it
honestly, which is real, separate work.

**42. Smart playlists** — Partial (the rule-engine gap closed
2026-08-14). `SmartPlaylistPlugin` is still, as before, a flat,
user-editable list of mood strings matched via case-insensitive
substring against `track.mood` (one hardcoded special case: "focus"
also matches an `ambient` genre tag) — it still directly powers the
Moods page, and that matcher is untouched; `QueuePresetPlugin` remains
its complementary static genre-keyword/BPM-threshold fallback for the
same four preset names.

What's new is a genuinely separate, additive rule engine
(`Omnis-Plugins/lib/smart_playlist_rule.dart`):
`RuleField`/`RuleOperator`/`RuleMatchType`/`RuleCondition`/
`SmartPlaylistRule`, giving real ALL/ANY/NONE boolean grouping over
per-field conditions (title/artist/album/genre/mood/year/rating — not
yet play-count or date-added, since neither `BaseTrack` nor
`IPlayHistoryProvider` currently exposes a "date added" field, and
play-count would need `IPlayHistoryProvider` wired through the same way
`rating:` now is, left for a follow-up). Multi-valued fields
(artist/genre) match if any element satisfies the condition; string
fields support `contains`/`equals` (the builder UI only offers
`contains`); numeric fields (year/rating) support the full comparison
set; a rule with zero conditions matches nothing, not everything — a
setup gap distinct from `library_search.dart`'s "empty query = show
everything" convention, deliberately diverging since a *saved* rule
with nothing configured is a different situation than an empty search
box mid-typing.

The `rating:` condition needed to reach `RatingsPlugin`'s data from a
different plugin with no existing shared interface for it — closed by
adding `IRatingsProvider` to `packages/omnis_plugin_api`
(`plugin-api-v0.15.0`) and having `RatingsPlugin` register/unregister
against it through `enable()`/`disable()`/`dispose()` (previously it
only ever registered once in `initialize()`, so a disable-then-re-enable
cycle silently left it unregistered forever — fixed as part of this
same change, not a pre-existing bug worth its own separate entry since
nothing exercised that path before `SmartPlaylistPlugin` needed to).

Saved rules are named, persisted (per-entry-defensively-decoded JSON,
same convention as every other store in this app), and their membership
is recomputed fresh against the live library every time they're played
— not a fixed snapshot of track ids the way `PlaylistStore`'s ordinary
playlists are. Rule editing after creation closed 2026-08-14 (an Edit
button repopulates the create form and saves in place, reusing the
rule's existing id) and surfacing on the main Playlists page closed
2026-08-15 (a new "Smart playlists" section there, play/delete per
rule, a "Manage" link deep-linking to the plugin's own settings page
for create/edit rather than a second builder UI) — **still missing**:
no persistence as a real `PlaylistStore` entry a user could otherwise
manage, no import/export, and the builder UI's string-field operator
choice is narrower than the model (`contains` only, though `equals`
works if constructed directly).

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
display option, not moved here), no voice control, no switch-input
support, no RTL/localization wiring (`AppLocalizations` isn't used).

**Keyboard shortcuts closed 2026-08-14** (was the genuine "zero
`Shortcuts`/`FocusTraversalGroup`/`CallbackShortcuts` usage found"
gap). New `GlobalKeyboardShortcuts`
(`lib/ui/global_keyboard_shortcuts.dart`) wraps `HomePage`'s `Scaffold`
— all six tabs share the one `IndexedStack` under it, so this is
app-wide without per-page wiring. Bindings: Space and the hardware
media-play-pause key toggle play/pause; plain Left/Right arrows seek
±10s; plain Up/Down adjust volume ±5%; Ctrl+Left/Right and the hardware
media-next/previous keys skip tracks. A new **Keyboard** settings
category (`lib/ui/settings/keyboard_settings_page.dart`) holds
`AppSettings.keyboardShortcutsEnabled` (default on) plus a static
reference list of what each key does, wired into the search index the
same way Accessibility was.

Two real `CallbackShortcuts`/focus gotchas surfaced only by writing
genuine `tester.sendKeyEvent` tests, not from reading the API:

1. `CallbackShortcuts` deliberately never requests focus itself
   (`canRequestFocus: false`) — it only fires as part of the ancestor
   chain walked outward from whatever currently holds `primaryFocus`.
   In a touch-first app nothing holds focus by default, and the actual
   default holder (the current route's own `FocusScopeNode`) sits
   *above* `GlobalKeyboardShortcuts` in the tree, not below it — key
   dispatch never walks into children, so with nothing else focused
   these bindings would silently never fire. Every one of the first 9
   tests failed exactly this way (widget built correctly, nothing
   intercepted the key) before the fix. Fixed with a fallback anchor
   `FocusNode`, claimed only when `primaryFocus` is `null` or a bare
   `FocusScopeNode`.
2. The naive version of that fix — claiming in the very first
   post-frame callback — stole focus from a real descendant
   `autofocus: true` `TextField` in a dedicated nested-autofocus race
   test, because that widget resolves its own autofocus claim via a
   post-frame callback too, and an ancestor's `initState` (this
   widget's) always runs — and therefore registers its callback —
   before a descendant's, so the naive anchor's callback fired and won
   first. Fixed by deferring the actual claim one additional frame,
   letting the real widget's own callback settle first; the same test
   then passed.
3. Separately, even once focus correctly reached the widget: a focused
   `TextField` did **not** stop Space from also reaching the global
   handler. Ordinary character input isn't reliably marked "handled" by
   `EditableText`'s own key handling the way arrow-key cursor movement
   is — text composition goes through a separate IME channel the
   `Shortcuts`/`Actions` handled/ignored bubbling model doesn't see.
   Left unfixed, typing a space while searching the Library would have
   inserted the character *and* toggled playback. Fixed with an
   explicit `_typingInTextField` check (walks up from the focused
   context looking for an ancestor `EditableText`) ahead of every
   binding, rather than relying on propagation to stop it.

11 new tests in `test/global_keyboard_shortcuts_test.dart` (every
binding proven against a real fake-`AudioEngine` call, not just that
the widget renders), 2 more in `test/settings_page_test.dart`. Full
suite: 647 passing (was 634), `flutter analyze` clean. Main-repo-only,
no cross-repo bump needed.

Still 0% for per-shortcut remapping/conflict-detection UI, and for the
UI spec's global Ctrl+K search (§37) and command palette (§38) — both
distinct, materially larger features this increment didn't attempt.

**49. Widgets** — Partial (closed 2026-08-13, was genuine 0%). Real
Android App Widget: `home_widget: ^0.9.2+1` for the Dart↔native
SharedPreferences bridge, `OmnisWidgetProvider.kt`
(`android/app/src/main/kotlin/com/omnis/music/`) as the actual
`AppWidgetProvider`, plus `omnis_widget.xml`/`omnis_widget_info.xml`
and four vector-drawable transport icons.

`HomeWidgetService` (new, `lib/core/home_widget_service.dart`) listens
to a new narrow seam interface, `HomeWidgetTrackSource`
(`lib/core/home_widget_track_source.dart`) — `AudioEngine` now
`implements` it alongside `PlaybackEngine`, same "small,
purpose-specific interface" pattern that already exists for
`PlaybackWatchdog`/`PlaybackRecovery`, kept in its own file so
`audio_engine.dart` and `home_widget_service.dart` don't have to import
each other. On every track/play-state change it pushes
title/artist/playing into the widget's SharedPreferences and calls
`HomeWidget.updateWidget()`. Wired into `MainCore.initialize()`/
`dispose()` right alongside the other core (non-plugin) singletons.

The interesting design decision: Play/Pause/Next/Previous do **not**
round-trip through Dart at all. `home_widget`'s own documented pattern
for interactive buttons is a Flutter background-isolate callback
(`registerBackgroundCallback`) — rejected here because this app's
playback engine (`just_audio`, wrapped by `audio_service`) has no
supported story for running a second, widget-triggered background
isolate alongside the real one already driving playback; standing that
up would be new, unproven machinery for a feature this narrow. Instead
each button is a `PendingIntent.getBroadcast` sending a real
`android.intent.action.MEDIA_BUTTON` intent (with the matching
`KeyEvent`, e.g. `KEYCODE_MEDIA_PLAY_PAUSE`) explicitly targeted at
`com.ryanheise.audioservice.MediaButtonReceiver` — the exact receiver
this app's manifest already registers for the lock-screen notification's
own controls (see item 1's original audio_service wiring). A real
Bluetooth headset's hardware buttons reach this app the same way, so
this is proven, already-working plumbing, not a new integration.

Two real bugs found and fixed during this increment, both the kind
that only a real native build/inflate step catches — `flutter analyze`
and `flutter test` cannot exercise Android's manifest merger or XML
layout inflater at all:

1. **Manifest-merge minSdk conflict.** `home_widget`'s Android side
   transitively pulls in `androidx.work:work-runtime-ktx`, which
   declares `minSdkVersion 23`; this app deliberately keeps
   `minSdkVersion 21` (same reasoning as the pre-existing `audify`
   override — see AndroidManifest.xml's own comment on that line).
   Fixing this took three build attempts: first adding
   `androidx.work.ktx` to `tools:overrideLibrary` alongside `audify`
   using a **colon**-separated value (wrong — Android's manifest-merger
   syntax for multiple libraries is **comma**-separated, and the wrong
   separator silently broke `audify`'s own override too, surfacing as
   audify's original minSdk error again under a different guise); then
   fixing the separator but still hitting a *second*, non-ktx
   `androidx.work:work-runtime` artifact with the same minSdk
   requirement (the ktx artifact is a thin wrapper around the base one,
   and Gradle's manifest merger checks each merged library
   individually, not just the top-level dependency). Final working
   value: `tools:overrideLibrary="id.nabilfaris.audify,androidx.work.ktx,androidx.work"`.
   Safe for the same reason the audify override is safe: `HomeWidgetService`
   never calls `home_widget`'s background-worker/
   `registerBackgroundCallback` APIs — the only code paths that
   actually need WorkManager at runtime — so the higher-minSdk code
   inside the merged library simply never executes on a pre-23 device.

2. **`RemoteViews` rejects plain `View`.** The widget's layout used
   `<View android:layout_width="0dp" .../>` as a flexible spacer
   between the transport buttons (a completely ordinary pattern in a
   normal Flutter/Android layout). Real Android home-screen widgets
   render via `RemoteViews`, which only supports a fixed allow-list of
   view classes for security/remoting reasons — plain `View` is not on
   it. The build succeeded and `flutter analyze`/`flutter test` stayed
   green throughout, because none of that tooling parses or inflates
   Android layout XML; the only way this surfaced at all was actually
   pinning the widget to the emulator's home screen, where it showed a
   generic system "Can't load widget" error. `adb logcat` had the real
   exception: `android.view.InflateException: ... Class not allowed to
   be inflated android.view.View`. Fixed by switching both spacers to
   `<Space>`, which *is* on `RemoteViews`' allow-list and behaves
   identically for this purpose (a zero-content flex spacer).

**A genuine verification gap, left honest rather than papered over.**
After fixing bug 2, re-pinning the widget to confirm — visually, via
screenshot — that it now renders correctly and that its buttons
genuinely control playback could not be completed. The one successful
pin (which is how bug 2 was found in the first place) was achieved via
`adb shell input draganddrop <source> <dest> <duration>` dragging the
widget preview out of the emulator's Compose-based Pixel Launcher
widget picker sheet onto the home screen. After the fix, roughly a
dozen further attempts — `draganddrop` with the identical coordinates
and sequence that worked the first time, manual `motionevent`
DOWN→(long hold)→MOVE×N→UP sequences with varied hold durations
(0.5s/0.8s/1.2s/2.0s) and step counts, both from a search-result flow
and a Browse-tab alphabetical-list flow, with uiautomator-dumped exact
bounds re-verified at every step — never reproduced a successful drop;
each attempt left the picker sheet open and unchanged. This reads as a
timing-sensitive quirk in either the emulator's synthetic touch-event
handling or this specific launcher build's Compose drag-gesture
detector, not a reproduced app-level defect: the underlying pipeline
(widget registers, discoverable by name/size in the picker, binds,
attempts to inflate) is the same pipeline that produced the real,
diagnosable, now-fixed `<View>` exception on the one pin that did
succeed. Still, this means the fix's correctness rests on the standard,
well-documented nature of the `<View>`→`<Space>` `RemoteViews` fix
plus a successful `flutter build apk` (which does compile and
resource-link the layout, just not inflate it at runtime), **not** on
a fresh screenshot of a working widget. A real-device (not emulator)
manual check is the natural follow-up to close this gap for good.

Remaining scope gaps, independent of the verification question above:
no iOS widget (no WidgetKit extension target — `home_widget` supports
iOS too, but this increment only built and wired the Android side); no
lock-screen widget beyond what `audio_service`'s existing notification
already provides; exactly one fixed widget layout and size (`3×1`,
`resizeMode="horizontal|vertical"` is declared but no alternate
compact/expanded RemoteViews layout responds to it); no widget
configuration screen (`ACTION_APPWIDGET_CONFIGURE` isn't implemented —
every instance is identical, there's nothing to configure yet anyway
since there's only one Omnis "account"/library); album art is not
shown on the widget (would need `RemoteViews.setImageViewBitmap` fed a
real decoded bitmap from the track's artwork source, a materially
bigger increment than the text/controls built here).

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
