# Architecture

How Omnis is put together, and — more importantly — *why*, since most of
the interesting decisions here are trade-offs that aren't obvious from
reading the code alone. If you're looking for step-by-step instructions
to build a plugin, see [PLUGIN_GUIDE.md](PLUGIN_GUIDE.md) instead; this
document is the reference for how the pieces fit and the reasoning
behind them.

```
┌───────────────────────────────────────────────┐
│                   UI Layer                     │
│   Now Playing · Library · Plugins · Settings   │
├───────────────────────────────────────────────┤
│       omnis_plugins (Omnis-Plugins repo)       │
│  equalizer · lyrics · replay gain · scrobble   │
│  sleep timer · smart playlist · visualizer …   │
├───────────────────────────────────────────────┤
│  lib/plugin_api/ — thin re-export shim; the    │
│  real capability contracts now live in         │
│  packages/omnis_plugin_api/, so old imports    │
│  still compile unchanged.                      │
│  Depends on core; core never depends back.     │
├───────────────────────────────────────────────┤
│      lib/core/  — the kernel, plugin-agnostic  │
│  AudioEngine · PluginManager · Sandbox         │
│  PluginContext · ServiceRegistry · EventBus    │
└───────────────────────────────────────────────┘
```

The kernel never imports a concrete plugin. `lib/core/main_core.dart` has
exactly one plugin-side import — `createBundledPlugins()` from
`package:omnis_plugins/bundled_plugins.dart` — so **you add features by
editing the separate [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins)
repo (the `omnis_plugins` package this app depends on), never
`lib/core/`.** `lib/plugin_api/` in *this* repo is a thin re-export shim,
not where a feature's capability contract lives — see "Why interfaces
live in `omnis_plugin_api`" below for where it actually lives and why the
shim exists.

## Design rule

Before something becomes part of the Core, it has to survive one
question: **could someone reasonably want to replace this with a
different implementation?** If yes, it belongs behind a plugin (or, for
a capability other code needs to discover generically, an interface). If
there's genuinely only one sensible way to implement something — a
countdown timer, say — it stays a plain concrete plugin with no
interface, and a one-line pass-through with no realistic "swap the
implementation" story (crossfade, gapless, skip-silence, pitch) stays a
direct `AudioEngine` toggle, not a plugin. The goal is a Core that's
small and stops changing, not abstraction for its own sake — an
interface that provides no practical value is a cost, not a virtue.

## Core Kernel (`lib/core/`, indestructible)

- **AudioEngine** (`audio_engine.dart`): the whole queue is loaded as one `ConcatenatingAudioSource` and just_audio owns advancement; `audio_service` handler for lock-screen/notification controls. Unplayable files are skipped rather than wedging the player.
- **BaseTrack** (`base_track.dart`): unified schema — local files, Spotify tracks, and YouTube streams are the same `BaseTrack` object with a `TrackType` enum. `duration` is **seconds**.
- **PluginContext** (`plugin_context.dart`): the capability surface handed to every bundled plugin (playback control, composable gain contributions, `services`, `events` — see below). This is what keeps the kernel from knowing plugin names.
- **PluginStorage** (`plugin_storage.dart`): namespaced per-plugin persistence, so a plugin never needs an `AppSettings` change to remember something.
- **PluginSandbox** (`sandbox.dart`): every plugin hook runs in a try-catch. Failures log to a `PluginHealthRecord` dashboard, never crash the app.
- **PluginManager** (`plugin_manager.dart`): registration, hot-swap (enable/disable/uninstall at runtime, persisted across restarts), hook dispatch (`onTrackStart`, `onLibraryScan`, `uiSlot`), typed lookup via `bundled<T>()`, and owns the shared `services`/`events` instances below.
- **PluginInstaller** (`plugin_installer.dart`): paste a GitHub URL → downloads the repo as a zip → extracts (with a zip-slip guard) → validates `omnis_plugin.yaml` → registers.
- **PluginRuntime** (`plugin_runtime.dart`): executes downloaded plugin Dart code at runtime via `dart_eval` (a full Dart bytecode interpreter). Downloaded plugins are sandboxed — they cannot import `package:omnis` or `dart:ui`, and only get the permissions their manifest declares.

## Capability interfaces: `ServiceRegistry` and `EventBus`

`bundled<T>()` finds the registered instance of a *concrete* plugin class — real, and used throughout, but it means a caller has to know which plugin implements a feature. Swap `LyricsPlugin` for a future `LrclibLyricsPlugin` and every `bundled<LyricsPlugin>()` call site would need to change. `ServiceRegistry` (`lib/core/service_registry.dart`) and `EventBus` (`lib/core/event_bus.dart`) generalize the same "ask for a capability, don't hardcode who provides it" idea `PluginContext` already applied to playback:

- **`ServiceRegistry`** — a lookup keyed by *interface* type, not concrete class. A plugin registers itself under an interface it implements (`context.services.register(ILyricsProvider, this)`, always the interface, never the concrete type — a class can implement several); a caller asks for the interface (`pluginManager.services.get<ILyricsProvider>()`) without ever naming the plugin. More than one implementation can register at once — `get<T>()` returns the first (primary), `getAll<T>()` returns every one. Registration lifecycle mirrors how plugins already manage gain contributions: register in `initialize()`/`enable()`, unregister in `disable()`/`dispose()` — the registry has no opinion about a plugin's enabled state, the plugin already does.
- **`EventBus`** — typed publish/subscribe (`context.events.emit(SomeEvent(...))`, `pluginManager.events.on<SomeEvent>().listen(...)`), matched by exact runtime type. Lets a plugin *announce* something happened without knowing (or caring) whether anything is listening — the piece `bundled<T>()`/`services.get<T>()` alone can't do, since those only support pulling current state, not being told when it changes.

Both live on `PluginManager` and are handed to every plugin via the same `PluginContext` instance, so a plugin registering a service and a page looking it up share one object, not two. **This mechanism is the whole point, and it's deliberately the only part of it that lives in `lib/core/`.**

### Why interfaces live in `omnis_plugin_api`, not `lib/core/`

The six interfaces below each used to mean adding a file to `lib/core/` — one per capability, plus a result-type file for the ones that needed a return type. That's a real problem: it means the kernel grows forever, one file per feature, which is exactly what "the Core stays small and never needs to change" is supposed to prevent. `ServiceRegistry`/`EventBus` themselves haven't changed once across all six additions and have no reason to change for a seventh — they're the generic, stable *mechanism*. The interfaces (`ILyricsProvider`, `IQueueBuilder`, ...) are not that: they're capability-specific knowledge that keeps growing as the plugin ecosystem grows.

So they live in `packages/omnis_plugin_api/` instead of `lib/core/` — a small standalone package that depends on nothing but `BaseTrack` (also defined there) and that neither `lib/core/` nor a plugin depends back on. It has to be a genuinely separate *package*, not just a separate directory in this repo, because the interfaces now need to be visible from two different git repositories: this app, and the bundled plugins themselves, which live in the separate [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) repo as the `omnis_plugins` package. A plugin implements an interface by depending on `omnis_plugin_api` directly (`import 'package:omnis_plugin_api/service_interfaces.dart'`); this app's UI code imports the very same interface through `lib/plugin_api/service_interfaces.dart`, a one-line re-export shim (`export 'package:omnis_plugin_api/service_interfaces.dart';`) kept around so every pre-existing `import 'package:omnis/plugin_api/service_interfaces.dart'` in this codebase keeps compiling unchanged. Adding an eighth interface means adding a file to `packages/omnis_plugin_api/` — `lib/core/` doesn't change, doesn't grow, nothing about the kernel needs re-review, and this app's own shim doesn't need touching either, since it re-exports the whole file rather than naming symbols one by one. Result types an interface needs to name (`PlayRecord`, `EnrichmentResult`, `AudioAnalysisResult`) live in `omnis_plugin_api` alongside the interfaces themselves, for the same reason.

Real migrations exist today, not just unused infrastructure:

- **`ILyricsProvider`**: `LyricsPlugin` registers itself; `NowPlayingPage`'s *display* path (`_lyricsProvider`) asks for the interface, while the *edit* path (`_lyricsEditor`) still looks up the concrete `LyricsPlugin` — editing is specific to this plugin's storage format, not part of the generic "read the current lyric" contract, so only the reusable half moved.
- **`IPlayHistoryProvider`**: `ScrobblePlugin` registers itself; the Playlists page's "Recently played"/"Most played" smart lists ask for the interface.
- **`IQueueBuilder`**: `SmartPlaylistPlugin` (curated `BaseTrack.mood`-tag matches) and `QueuePresetPlugin` (objective BPM/genre matching, so a preset still produces *something* on a freshly scanned library with zero mood data) **both** register under this one interface — the first proof that `getAll<T>()`, not just `get<T>()`, does real work: `HomePage._MoodsPageState._playMood` tries every registered builder in order and keeps the first non-empty result. Registration order is therefore meaningful and deliberate (`bundled_plugins.dart` lists `SmartPlaylistPlugin` before `QueuePresetPlugin`) — `QueuePresetPlugin`'s fallback is *never* empty, so if it registered first it would silently swallow every query before the curated matcher got a chance.
- **`IMetadataProvider`** / **`IAudioAnalysisProvider`**: `MetadataEnrichmentPlugin` and `AudioAnalysisPlugin` register under their own interfaces — two distinct capabilities (web-lookup metadata vs. real audio-content analysis) kept as two distinct interfaces rather than forced into one, since unifying result types that don't actually mean the same thing is exactly the "abstraction for its own sake" the design rule above exists to avoid. Library page's per-track and bulk enrich/analyze actions ask for the interfaces; each plugin's own credential/config-specific hint (`hasAnyCredential` for Last.fm/Discogs) stays a concrete lookup, same reasoning as the lyrics edit path.
- **`IVisualizerProvider`**: `VisualizerPlugin` registers itself; `VisualizerBars` reads through the interface. `emitLevels` (how a provider *produces* levels — injected today, could be real FFT analysis from a future source) stays plugin-specific, the same read/write split as lyrics.
- **`FavoriteChangedEvent`**: `FavoritesPlugin` emits one on every real change; the Playlists page's "Favorites" smart list — kept alive alongside the Library page in `HomePage`'s `IndexedStack`, so it never gets disposed-and-rebuilt when a favorite changes elsewhere — subscribes and updates immediately instead of only catching up the next time something unrelated triggers a rebuild.

## `PluginContext`: a complete playback surface, and `PluginStorage`

`ServiceRegistry`/`EventBus` solve "new capability, no Core change" for
cross-plugin communication. Two more gaps needed the same fix: reaching
playback, and persisting state.

- **`PluginContext` mirrors all of `AudioEngine`'s public surface**, not a
  hand-picked subset. Early on it exposed only what the first few plugins
  happened to need (`pause`/`play`/`setQueue`/gain contributions) — which
  meant *adding a plugin that needed `next()`* turned into *adding `next()`
  to `PluginContext` first*, the exact "editing the Core to add a plugin"
  problem this whole layer exists to prevent. It now forwards every
  stream (`trackStream`, `queueStream`, `positionStream`, `durationStream`,
  `playerStateStream`), every transport method (`play`/`pause`/`stop`/
  `next`/`previous`/`seek`/`playAt`/`addTrack`/`removeTrack`/`setQueue`),
  and every toggle (`volume`, `speed`, `pitch`, `skipSilenceEnabled`,
  `shuffleEnabled`, `repeatMode`, `crossfadeDuration`, `gaplessEnabled`,
  A-B repeat, hardware EQ bands). A plugin nobody has written yet — one
  that reacts to position ticks, or drives transport directly — already
  has what it needs today. Full reference:
  [PLUGIN_GUIDE.md](PLUGIN_GUIDE.md#plugincontext-reaching-playback).
- **`PluginStorage`** (`lib/core/plugin_storage.dart`) closes the same gap
  for persistence. Before it existed, a plugin that needed to remember
  something had no choice but to add a key plus a getter/setter pair to
  `AppSettings` itself — `favoriteTrackIds`, `autoTaggedTrackIds`, the
  lyrics-by-track map, and the play-history list are all exactly that.
  Every `MusicPlugin` now has a `storage` getter: a key-value store
  automatically namespaced as `plugin_<pluginId>_<key>`, backed by the
  same `SharedPreferences` instance `AppSettings` uses, so two plugins
  never collide and `storage.clear()` only ever wipes one plugin's own
  keys. `PluginManager` warms it before a plugin's `initialize()` hook
  runs, so a plugin can read persisted state from the first line of that
  hook; writes self-initialize even for a plugin built directly in a test.

**`ShuffleRepeatPlugin`** (`shuffle_repeat_plugin.dart`, `package:omnis_plugins`
in the separate [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) repo) is the
concrete proof both of these were worth building, and a worked example of
where the plugin/Core line actually sits. The *toggle itself*
(`setShuffleEnabled`/`setRepeatMode`) has to stay a thin call into
`AudioEngine`, because it forwards straight to just_audio's own shuffle/
loop mode, the only implementation that stays consistent with just_audio's
gapless auto-advance (see `AudioEngine`'s doc — a deliberate design
decision, not an oversight). What genuinely wasn't a Core concern was
*remembering* the toggle across restarts and the toggle/cycle behavior the
UI drives: previously split across `main_core.dart` (restoring
`AppSettings.shuffleEnabled`/`repeatMode` onto the engine at startup) and
`now_playing_page.dart` (inlining the repeat-cycle switch and writing
straight back to `AppSettings` on every tap). `ShuffleRepeatPlugin` now
owns all of that — `toggleShuffle()`/`cycleRepeat()`, backed by its own
`storage`, restored in its own `initialize()` — and the two
`AppSettings.shuffleEnabled`/`repeatMode` key/getter/setter pairs were
deleted outright, not deprecated.

Toggles evaluated the same way and left where they are: crossfade,
gapless, skip-silence, and pitch. Each is a one-line pass-through to a
just_audio setting with no realistic "swap the implementation" story —
plugin-izing them would be ceremony, not modularity. Shuffle/repeat only
differed in having non-trivial *behavior* (persistence + cycling) sitting
on top of the toggle; that behavior is what moved, not the toggle.

## A plugin's own settings page

Tapping a plugin in the Plugins list (`PluginsPage`) opens
`PluginSettingsPage` — a dedicated page for exactly that plugin, the same
"click the plugin to configure it" model RuneLite uses for its plugin
list. A plugin opts in by returning a widget from
`uiSlot('plugin_settings')` — see
[PLUGIN_GUIDE.md](PLUGIN_GUIDE.md#injecting-ui-uislotlocationid) for the
how-to.

`'plugin_settings'` behaves differently from every other `uiSlot`
location. `now_playing_overlay`, `library_header`, and the rest are
*aggregate*: `PluginManager.uiSlot(locationID)` asks every enabled
plugin and `PluginSlotView` renders whatever comes back, side by side.
`'plugin_settings'` is *singular*: `PluginSettingsPage` calls
`PluginManager.uiSlotForPlugin(plugin, 'plugin_settings')`, which asks
only the one plugin the user tapped — showing everyone's settings on one
page would defeat the purpose. It also works on a disabled plugin (every
other hook skips disabled plugins), so a plugin can still be reconfigured
or re-enabled from its own settings page. A plugin with nothing to
configure just returns `null`; the page shows "This plugin has no
configurable settings." instead of an empty screen.

This is what makes "settings live in the plugin, not the Core" true
rather than aspirational. Three real settings blocks that used to live
directly in `settings_page.dart` — Last.fm/Discogs/MusicBrainz
credentials, the Essentia service URL, and the featured-artist separator
list — moved into `MetadataEnrichmentPlugin`, `AudioAnalysisPlugin`, and
`TagEditorPlugin` respectively as `uiSlot('plugin_settings')`
implementations, backed by each plugin's own `storage` instead of
`AppSettings`. `settings_page.dart` no longer imports or knows about any
of the three; the corresponding `AppSettings` keys, getters, and setters
were deleted, not deprecated. A downloaded plugin gets the same
mechanism through the declarative-Map path `PluginSlotView` already
supports (`{'type': 'text', ...}` / `{'type': 'badge', ...}`) — real form
fields aren't available to a `dart_eval`-sandboxed plugin, but a
read-only settings summary is.

## Player layouts (`lib/ui/player_layouts/`)

Theming here goes beyond colors: the *arrangement* of Now Playing —
where buttons sit, whether there are visible buttons at all — is
swappable per user, the same "one file to edit" pattern as the plugin
registry.

`NowPlayingPage` is a thin controller: it owns the audio-engine
subscriptions and plugin lookups, packages the result into a
`PlayerLayoutData`, and hands rendering off entirely to whichever
`PlayerLayout` is selected (`AppSettings.playerLayoutId`, chosen in
Settings → Player layout). Six ship today:

| Layout | id | What it looks like |
|---|---|---|
| Standard | `standard` | The default. Album art fills the screen as a background layer (darkened with a scrim), title/controls sit fixed on top of it. Nothing scrolls except the lyrics panel — a full song's lyrics can be taller than the screen, so that's the one part of the screen meant to scroll. |
| Top Controls | `top_controls` | Same content, playback buttons pinned near the top instead of the bottom. |
| Landscape | `landscape` | Side-by-side art + info, controls pinned to a bottom bar. Also auto-selected for Standard/Top Controls while the device is rotated, if "Auto-switch to Landscape" is on. |
| Full Art + Gestures | `full_art_gestures` | Full-bleed artwork, **no visible buttons** — tap to play/pause, swipe to skip. |
| Karaoke Gestures | `karaoke_gestures` | Big synced lyrics dominate the screen; tap/swipe control playback the same way as Full Art. |
| Car Mode | `car_mode` | Oversized controls on one screen edge (left/right, per Settings) for safe reach while driving; deliberately drops everything else (EQ, visualizer, lyrics, sleep timer) that the other layouts show. |

**Bottom navigation auto-hide** (`HomePage`, `AppSettings.bottomNavAutoHide`,
on by default): in landscape or while Car Mode is the selected layout, the
tab bar hides itself instead of permanently covering more of a
already-cramped screen. A swipe up from the bottom edge, or the small
handle button that appears in its place, brings it back; it re-hides on
the next swipe down or by leaving that state (rotating back to portrait,
switching away from Car Mode).

There are **two ways to add a layout**, matching the same bundled-vs-downloaded
split as plugins — for the same underlying reason: a downloaded
(`dart_eval`) plugin is barred from touching `dart:ui`, so it cannot
construct a real, arbitrary widget tree, and a naive "layout" format would
just be arbitrary widget code with extra steps.

### Contributor-facing: a bundled `PlayerLayout` class

1. Create `lib/ui/player_layouts/my_layout.dart`, extending `PlayerLayout`
   and composing the shared widgets in `player_widgets.dart`
   (`PlayerAlbumArt`, `PlayerTrackInfo`, `PlayerControlsRow`,
   `PlayerProgressBar`, `PlayerLyricsPanel`, `PlayerExtrasRow`,
   `PlayerSleepTimerRow`, `PlayerCrossfadeStatus`) plus whatever custom
   arrangement you want:

```dart
class MyLayout extends PlayerLayout {
  @override
  String get id => 'my_layout';
  @override
  String get name => 'My Layout';
  @override
  String get description => 'One line shown in the picker.';
  @override
  IconData get icon => Icons.dashboard_customize;

  // Set this to true only if you handle tap/swipe yourself instead of
  // relying on Settings → Gesture mode.
  @override
  bool get definesOwnGestures => false;

  @override
  Widget build(BuildContext context, PlayerLayoutData data) {
    return Column(
      children: [
        PlayerAlbumArt(data: data),
        PlayerTrackInfo(data: data),
        PlayerControlsRow(data: data),
      ],
    );
  }
}
```

2. Add it to the list in `lib/ui/player_layouts/registry.dart`.

`PlayerLayoutData` carries the current track/position/settings, the
resolved plugin instances (already `null`-filtered for disabled plugins),
and callbacks (`onPlayPause`, `onNext`, `onPrevious`, `onSeek`,
`onOpenEqualizer`, `onEditLyrics`, `onActivateVisualizer`,
`onStartSleepTimer`, `onCancelSleepTimer`) — a layout never touches
streams or the service locator directly. Full source code, no sandbox
needed because it isn't downloaded — this is exactly as trusted as any
other file in the repo.

### End-user-facing: an importable declarative layout file (`lib/ui/player_layouts/declarative/`)

This is the actually-importable "build your own theme" path. A layout
file is **one YAML/JSON data file**, not code — `LayoutManifest`/
`DeclarativeLayoutRenderer` interpret a closed, fixed vocabulary of node
types (`column`, `row`, `stack`, `positioned`, `center`, `expanded`,
`padding`, `sized_box`, `safe_area`, `scroll`) and `component` references
(`album_art`, `track_info`, `controls_row`, `progress_bar`,
`lyrics_panel`, `extras_row`, `sleep_timer_row`, `crossfade_status`,
`plugin_slot_overlay`, `plugin_slot_bottom`, `state_icon`, `spacer`) — the
exact same building blocks the bundled layouts use. There is no escape
hatch: an unrecognised node degrades to an empty box, a rendering
exception shows an in-place error card, and nothing in the format can
reach the network, the filesystem, or any Core capability. That's what
makes it safe to import from a URL with **no permission dialog at all** —
unlike a downloaded plugin, a layout file cannot do anything beyond
rearranging the fixed components.

```yaml
id: my_layout
name: My Layout
description: One line shown in the picker
author: Your Name
version: 1.0.0
defines_own_gestures: false   # true = tap/swipe drive playback directly
background:
  type: color                 # 'color' | 'gradient'
  value: surface               # a ColorScheme role name, or "#RRGGBB"
root:
  type: column
  main_axis_alignment: center
  children:
    - { type: component, component: album_art, size: 200 }
    - { type: spacer, height: 24 }
    - { type: component, component: track_info }
    - { type: spacer, height: 16 }
    - { type: component, component: progress_bar }
    - { type: spacer, height: 16 }
    - { type: component, component: controls_row }
```

See `layouts/sample_minimal/omnis_layout.yaml` for a working starting
point, and `lib/ui/player_layouts/declarative/layout_manifest.dart` for
the full schema doc.

**Importing one**: Settings → Player layout → "Import a layout" → paste a
direct link to the file's raw text (a GitHub "raw" URL or a gist raw URL
— not a repo page, there's no archive to extract) or pick a local file.
`LayoutManager` merges imported layouts with the six bundled ones,
persists them under the app's own data directory, and rejects (before
writing anything to disk) an id that collides with a bundled layout.
Remove one from the same picker at any time.

## Downloaded plugin contract

See [PLUGIN_GUIDE.md](PLUGIN_GUIDE.md#downloaded-plugins) for the full
manifest/entrypoint reference and a publishing walkthrough. In short: a
downloaded plugin is a self-contained `plugin.dart` plus an
`omnis_plugin.yaml` manifest, hosted in any public GitHub repo, installed
by pasting the URL into the Plugins tab. It runs through `dart_eval`
against an isolated `package:default`, so it cannot import
`package:omnis` or `dart:ui`, and its `permissions:` list is shown to the
user before any of its code executes.

Plugins that declare `storage` get dart_eval's all-or-nothing
`FilesystemPermission.any` — there is no per-directory scoping at that
layer. If a plugin crashes, the failure appears in the **Plugin Health**
section of the Plugins tab; the music never stops.

## Feature status

What's real, what's approximated, and why — so nothing in the UI claims
more than it does.

### Playback

- **Gapless** — real. The whole queue loads as one `ConcatenatingAudioSource`
  and just_audio owns advancement.
- **Crossfade** — real. A second, otherwise-idle `AudioPlayer` preloads the
  next track and a volume ramp overlaps it with the outgoing track for the
  configured duration; when the primary player auto-advances onto that
  same track, the second player stops (see `AudioEngine`'s crossfade state
  machine and `crossfadeVolumes`, which has a standalone unit test since
  `AudioPlayer` itself can't run in a plain Dart test).
- **ReplayGain** — real, applied as a composable gain contribution.
- **Gapless "off"** — not honoured. The queue is always one concatenated
  source, which is inherently gapless; the setting is stored but has no
  effect yet.
- **Shuffle & repeat** — real, and delegated entirely to just_audio's own
  `setShuffleModeEnabled`/`setLoopMode`/`seekToNext`/`seekToPrevious`
  rather than a hand-rolled parallel index scheme — that's the only way
  manual skipping and the engine's own gapless auto-advance (which
  `AudioEngine` never intercepts; just_audio owns it) are guaranteed to
  agree on what "next" means once shuffle is on. One consequence of that
  choice: with repeat-one, pressing Next/Previous restarts the current
  track rather than skipping past the repeat, since just_audio ties both
  to the same loop-mode-aware index. Persisted via `ShuffleRepeatPlugin`'s
  own storage, not `AppSettings`; buttons live in `PlayerControlsRow`
  (Standard/Top Controls/Landscape layouts).
- **Independent pitch control & skip-silence** — real, native just_audio
  support (`AudioPlayer.setPitch`/`setSkipSilenceEnabled`), not something
  this project implemented — Poweramp-style separate tempo/pitch (speed
  and pitch are two different sliders in Settings → Playback, so changing
  one doesn't have to shift the other) and a podcast-player-style
  skip-silence toggle. Persisted via `AppSettings.pitch`/
  `skipSilenceEnabled`.
- **A-B repeat** — loops a marked section of the current track
  indefinitely, a common practicing/DJ feature in Poweramp, Musicolet, and
  most desktop players that `just_audio` has no built-in concept of.
  Implemented as a `positionStream` watcher in `AudioEngine`
  (`markLoopA`/`markLoopB`/`clearLoop`/`abRepeatRange`) — the same pattern
  the crossfade state machine already used — that seeks back to A once
  playback reaches B. Cleared automatically on any track change (skip,
  auto-advance, new queue) so a loop never silently carries over onto an
  unrelated track. The button in `PlayerExtrasRow` cycles off → A marked →
  looping → off.

### Tagging (`TagEditorPlugin`, `package:omnis_plugins/tag_editor_plugin.dart` in the [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) repo)

Reads and writes real ID3 tags via `id3_codec` (pure Dart, no native
build). Building this surfaced three real bugs/gaps in that third-party
package — found by writing `test/id3_codec_safety_test.dart` *before*
building application code on top of assumed behavior, not by inspection:

1. Its "no existing tag" write path throws on a file with no ID3v2 header
   at all (an ordinary case, not an edge case) — worked around by always
   seeding a minimal valid empty header first, so only its "edit existing
   tag" path (which doesn't have the bug) is ever exercised.
2. `File.readAsBytes()`'s fixed-length `Uint8List` crashes the encoder,
   which mutates its input in place — bytes are converted to a growable
   list before encoding.
3. The real one: `ID3MetataInfo.toTagMap()`'s APIC (artwork) entry is
   decorative only — the package computes the picture's base64 and then
   discards it, replacing it with the literal string `'<Has Picture
   Data>'`. There is no way to get real artwork bytes back through the
   package's own decode API. `TagEditorPlugin` parses the APIC frame
   directly from the raw tag bytes instead (read-only, so a parsing
   mistake fails to "no artwork found," never file corruption) — verified
   by a round-trip test, not assumed.

Given that, the write side is deliberately split: title/artist/album/
artwork go through the package's real, exercised native-frame write path;
every other field (genre, year, track #, disc #, composer, comment,
album artist, BPM, key, mood, plus anything typed into a "custom field" in
the editor) goes through its `TXXX` custom-frame mechanism instead of
hand-written native frames — hand-writing ID3 frames at the byte level was
considered and rejected, since a wrong size/encoding byte there means file
corruption this project has no way to verify against a real player.

- **Manual editor** (`TagEditorDialog`, Library page → track menu → "Edit
  tags"): every field above, plus artwork (pick a replacement image) and
  freeform custom key/value pairs, plus a read-only list of any other
  frame the file happens to already contain.
- **Automatic/bulk tagging** (Library page → toolbar → "Auto-tag
  library"/"Re-tag everything"): runs `cleanArtistFields` (see below)
  across the library and writes the result back to each file, not just
  the in-memory list, so it survives a rescan.
- **Smart re-tag skip**: `AppSettings.autoTaggedTrackIds` records which
  tracks the automatic pass already processed, so "Auto-tag library" skips
  them on a repeat run — `TagEditorPlugin.clearAutoTagged`/
  `clearAllAutoTagged` and the menu's "Re-tag everything" are the "redo it
  anyway" escape hatch.
- **Configurable artist separators** (`TagEditorPlugin.artistSeparators`,
  this plugin's own settings — tap "Tag Editor" in Plugins):
  `splitArtists`/`extractFeaturedArtistFromTitle`/`cleanArtistFields` pull
  a featured artist out of `"Artist1 feat. Artist2"` or `"Song (ft.
  Artist2)"` using whatever separators are configured — not a fixed guess
  at every naming convention in the wild.

### Real artwork and artist data

- **Artist on desktop** — `MediaScanner`'s filesystem-walk fallback
  (non-Android) reads real title/artist/album/genre/year/track/disc via
  `TagEditorPlugin` (skipping artwork extraction during the scan itself —
  decoding every embedded picture just to discard it during a bulk scan
  would slow the scan and bloat the persisted library JSON for no
  benefit).
- **Artwork everywhere** — `TrackArtwork`/`ArtworkProvider`
  (`lib/ui/widgets/track_artwork.dart`): on Android via the MediaStore
  (`on_audio_query`'s `queryArtwork`, keyed off the `mediastore://<id>`
  marker `MediaScanner` stores), on desktop via `TagEditorPlugin`'s
  embedded-picture reader. Results are cached in memory per track id (not
  persisted — decoded picture bytes have no business in the library JSON)
  since Now Playing rebuilds many times a second and would otherwise
  re-read the same file or re-query the same platform channel constantly.

### Library page (`lib/ui/library_page.dart`)

- **List/grid views**: Songs, Albums, and Genres each have an independent
  list/grid toggle and a 2–5 column density picker, persisted separately
  (`AppSettings.songsViewMode`/`albumsViewMode`/`genresViewMode` +
  matching `*GridColumns`). Artists and Folders stay list-only — a 3-level
  artist → album → track (or a plain directory listing) doesn't reduce to
  a flat grid the way the other three do.
- **Folders view**: groups local tracks by parent directory — a flat
  ("linear," in Musicolet's terms) listing, one section per unique folder,
  not a nested filesystem tree. Grouped by the *full* directory path (so
  two same-named folders in different locations, e.g. two albums' own
  "Disc 1," stay separate) but titled by just its last path segment.
  Tracks with no local file (streams) land in an "Unknown location"
  bucket rather than being silently dropped.
- **Duplicate detection** (`findDuplicateTracks`): groups tracks by
  matching title + primary artist (case/whitespace-insensitive). **Short
  track cleanup** (`findShortTracks`, threshold configurable in Settings,
  default 30s): flags likely ad stingers/bumpers rather than real songs.
  Both pure functions, unit-tested directly (`test/library_grouping_test.dart`)
  independent of any widget. The "Find duplicates & short tracks…" tool
  pre-selects a "smart" default (the shortest/most redundant copy in each
  duplicate group, every short track) while leaving every checkbox
  editable, then permanently deletes the selected files from disk after
  an explicit confirmation — not just from the library list.
- **Duration measurement**: local files' `duration` was always `0` on
  desktop (ID3 doesn't reliably carry one) — `0` means "unknown," not
  "confirmed short," so short-track cleanup silently found nothing on a
  desktop library until this existed. "Measure track durations" opens each
  file via just_audio once (cancellable) to fill in a real value. This is
  deliberately a separate, explicit, on-demand pass rather than part of
  the bulk scan — opening every audio file just to read its length would
  slow the initial scan down.
- **Multi-select**: long-press any track (or grid tile, which selects its
  whole group) to enter selection mode; the app bar switches to a
  selection count + delete/add-to-playlist/favorite actions. Same
  permanent-delete-with-confirmation path as cleanup.

### Playlists, favorites, and play history

- **Real playlists** (`PlaylistStore`, `lib/core/playlist_store.dart`):
  named, ordered track-id lists persisted to their own JSON file (same
  load/save shape as `LibraryStore`). Create, rename, delete, reorder
  (drag in the playlist detail view), remove individual tracks, play the
  whole thing or starting from a tap. A playlist's track ids that no
  longer resolve against the library (deleted file) are left in storage
  rather than dropped — if the file comes back, the entry rejoins instead
  of needing to be re-added by hand.
- **Favorites** (`FavoritesPlugin`, "Like" in Spotify, "top rated" in
  Musicolet): a persisted set of track ids (`AppSettings.favoriteTrackIds`),
  toggled via the heart icon on every Library row or the bulk multi-select
  action.
- **Play history / recently played / most played** (`ScrobblePlugin`):
  persists up to 500 real play events (`AppSettings.playHistory`,
  `PlayRecord {trackId, title, artist, playedAt}`) and exposes
  `recentlyPlayed()` (deduped, newest first) and `mostPlayedIds()` (by
  play count).
- All three — plus the live queue — are one tap away from the Playlists
  tab's index as "smart" entries above the user's own playlists, each
  playable as a whole or from any track.

### Startup speed

`main()` only awaits the one genuinely fast thing first-frame rendering
needs (`AppSettings.initialize()`, a single `SharedPreferences` read)
before calling `runApp()`. `HomePage`'s own `_coreReady` gate (a plain
spinner, not a branded splash) calls the rest of the bootstrap —
`AudioEngine` + `PluginManager` (including loading every plugin installed
on disk) + `LayoutManager` (including reading every imported layout
file) — in `initState()`, *after* something is already on screen.

### Equalizer

Two implementations behind one `EqualizerPlugin` API, chosen automatically:

- **Android**: real per-band hardware EQ via just_audio's built-in
  `AndroidEqualizer` (`android.media.audiofx.Equalizer`) — genuine
  frequency-band shaping, reported and controlled by the device itself.
  Wired through `AudioPipeline` at `AudioPlayer` construction and queried
  once a source has loaded.
- **Everywhere else**: a virtual bass/mid/treble trim applied as an overall
  gain contribution — `just_audio` has no per-band processing hook in pure
  Dart on iOS/macOS/Windows/Linux, and there's no native platform channel
  in this project for it (would need an `AVAudioUnitEQ` bridge / WASAPI
  APO). Both models persist their band gains via `AppSettings` and have a
  real sliders UI (`EqualizerSheet`, opened from Now Playing).

### Metadata enrichment (`MetadataEnrichmentPlugin`)

Real HTTP calls against the real public MusicBrainz, Last.fm, and Discogs
APIs, reachable from the Library page (per-track and "enrich all"). No API
key ships with the app or is assumed — enter your own from this plugin's
own settings (tap "Metadata Enrichment" in Plugins):

- **MusicBrainz** needs no key, only a descriptive contact string for its
  User-Agent (its API etiquette requires one). Fills in album/year when
  missing; never overwrites title/artist (a single search match isn't
  reliable enough for that).
- **Last.fm** needs a free API key (last.fm/api/account/create). Its
  community tags become `BaseTrack.genres`, and a tag matching a curated
  mood vocabulary becomes `mood` — this is what actually powers
  `SmartPlaylistPlugin`'s mood-based queues for a real library, since local
  files otherwise carry no mood/genre data at all (Android's embedded
  genre tag, read via `MediaScanner`/`on_audio_query`, is the other real
  source — free, no key, no network).
- **Discogs** needs a free personal access token
  (discogs.com/settings/developers). Its release genre/style tags merge
  into `genres` the same way.

A source is skipped, not fatal, when its credential is blank; a failed or
malformed response is treated as "no match," never an exception.

### Essentia (BPM / key / mood via real audio analysis)

Real, unmodified Essentia — not a native `dart:ffi` binding. Essentia's
own tutorials only support running it via Python on **Linux** (a prebuilt
`essentia-tensorflow` wheel) or **macOS** (source build); there is no
supported way to run Essentia inside a Windows desktop app or a mobile
Flutter binary at all, official or otherwise. Compiling it from source for
Android/iOS/Windows and binding it via `dart:ffi` is a native-build
project measured in days, so the app talks to Essentia over HTTP instead:

- **`package:omnis_plugins/audio_analysis_plugin.dart`** (`AudioAnalysisPlugin`,
  in the separate [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) repo): a
  real HTTP client, same shape as `MetadataEnrichmentPlugin` — POSTs a
  local track's audio to a URL you configure from this plugin's own
  settings (tap "Audio Analysis (Essentia)" in Plugins) and parses back
  `{bpm, key, scale, mood, genres}`. No default endpoint ships with the
  app; the plugin does nothing at all while the setting is blank, and a
  failed/unreachable/malformed response is treated as "no result," never
  an exception. Reachable from the Library page (per-track and "analyze
  whole library").
- **`tools/essentia_service/`**: a small FastAPI service running real
  Essentia — `RhythmExtractor2013` for BPM, `KeyExtractor` for musical
  key, and (optionally, if you download the model files) Essentia's own
  `TensorflowPredictMusiCNN` auto-tagging model for mood/genre tags,
  following [Essentia's own tutorial](https://essentia.upf.edu/tutorial_tensorflow_auto-tagging_classification_embeddings.html)
  exactly. You deploy this yourself (Docker, a Linux box, a NAS) —
  deployment instructions and a full explanation are in
  `tools/essentia_service/README.md`.

`MetadataEnrichmentPlugin`'s Last.fm tags remain a second, independent
source of mood/genre data (no self-hosted service required, just a free
API key) — the two are complementary, not either/or, and both write into
the same `BaseTrack.mood`/`genres`/`bpm`/`key` fields.

### Visualizer

Animated from UI-supplied levels (`VisualizerPlugin.emitLevels`), not real
FFT — `just_audio` exposes no PCM/frequency tap on any platform this app
targets. `emitLevels` is the injection point a future native audio tap
would feed.

### Lyrics auto-fetch (`LyricsPlugin`)

Real HTTP calls against [lrclib.net](https://lrclib.net) — free, no API
key, purpose-built for time-synced lyrics. An exact match (`/api/get`,
track/artist/album/duration) is tried first; a 404 falls back to a fuzzy
search (`/api/search`) and takes its first result. A response's
`syncedLyrics` (LRC format) is parsed into time-stamped lines
(`parseLrc`, unit-tested against real LRC syntax including multi-timestamp
lines and metadata-only lines it must skip); `plainLyrics` is stored as
the plain-text fallback. An `instrumental: true` response is treated as a
real, successful "no lyrics" result, not a failure.

Off by default — auto-fetch-on-track-start is an opt-in setting (this
plugin's own settings page), since an automatic network call every time a
track starts is worth choosing into, not assuming. A separate
"write into file tags" setting embeds fetched plain lyrics into the
track's own file via `IFileTagWriter` (implemented by `TagEditorPlugin`,
as a `TXXX:LYRICS` custom frame — same reasoning as every other
`TagEditorPlugin`-written field id3_codec can't write natively, see
"Tagging" above) — looked up through the interface, so `LyricsPlugin`
never depends on `TagEditorPlugin` by concrete type.

### Streaming integrations: Spotify and YouTube

Four plugins, deliberately split along two axes — Spotify vs. YouTube,
and *import* (metadata) vs. *playback* (audio) — because each pairing
answers a genuinely different question:

- **`SpotifyImportPlugin`** / **`YoutubeMusicImportPlugin`**: browse and
  import playlist/track *metadata* from your account (Spotify Web API /
  YouTube Data API v3). Imported items come back as real `BaseTrack`s
  (`TrackType.spotify`/`TrackType.youtube`, `spotifyId`/`youtubeId` set)
  — recognisable everywhere `BaseTrack` is used, but with no `localPath`,
  since neither API returns a decodable audio stream. YouTube's import
  plugin also supports plain public search with just an API key, no
  account connection, for anything that doesn't need your private
  library.
- **`SpotifyPlaybackPlugin`**: Spotify Connect remote control — play/
  pause/skip/seek/volume/device-transfer against whichever device is
  running the real Spotify app on your account. This is the honest
  ceiling of third-party Spotify "playback": the catalog is
  DRM-protected, so no third-party app can decode and play it directly;
  Spotify Connect is the same mechanism Spotify's own apps use to hand
  control to a speaker. The audio flows out of the real Spotify app, not
  through Omnis's `AudioEngine` — this plugin's settings page is its own
  small transport panel, deliberately not merged into Now Playing, since
  that would misrepresent what's actually playing where.
- **`YoutubePlaybackPlugin`**: plays a video through YouTube's own
  official embedded IFrame player (`youtube_player_iframe`, a WebView
  under the hood). This is the ToS-compliant ceiling for third-party
  YouTube playback — extracting a raw stream URL (yt-dlp/youtube-dl
  style) violates YouTube's Terms of Service and is exactly the kind of
  stream-extraction this project declines to build. Real audio+video,
  just through YouTube's UI, not Omnis's engine. Needs a platform with a
  Flutter WebView implementation (Android, iOS, web) —
  `YoutubePlaybackPlugin.isSupportedOnThisPlatform` reports `false` on
  Windows/Linux (no official Flutter WebView there) rather than
  attempting to construct one that would fail.

All four use Authorization Code + PKCE OAuth (`SpotifyAuth`/`YoutubeAuth`,
part of the `omnis_plugins` package in the separate
[Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins) repo), opened via
`flutter_web_auth_2` — a loopback HTTP
redirect on desktop, a custom URL scheme (`omnis://callback`, registered
in `android/app/src/main/AndroidManifest.xml`) on Android/iOS. Each
plugin holds its own Client ID/tokens in its own `PluginStorage`, entered
in its own settings page — see
[PLUGIN_GUIDE.md](PLUGIN_GUIDE.md#downloaded-plugins) if you're building
something with a similar credential-gated shape.

**Verification status**: none of the four have been exercised against a
real Spotify/Google developer account or a physical device in this
environment — no OAuth browser round-trip or WebView can be driven here.
Implemented against each service's published API documentation, and
tested at the layer that *is* testable without live credentials: PKCE/
token-refresh math, JSON response parsing, and URL/video-id parsing, all
with mocked HTTP (`test/spotify_plugins_test.dart`,
`test/youtube_plugins_test.dart`). Register a real developer app and run
each `connect()` once yourself before relying on it.

## Out of scope for now

App icon-pack swapping and AI vocal removal are not implemented. Vocal
removal needs a real-time audio-separation model (native/FFI territory,
same fundamental constraint as Essentia above, minus the "run it as a
service" escape hatch — vocal removal has to happen in the playback path,
not as an offline analysis step). (Rearranging the *layout* of Now
Playing — buttons, gestures, full-art mode — is implemented; see "Player
layouts" above. What's not built is icon-pack/asset-swap theming.)

Spotify/YouTube integration *is* implemented (see "Streaming
integrations" above) — but bounded by what's actually legitimate for a
third party to build: metadata import via each service's official API,
and playback only through mechanisms each service itself provides for
third parties (Spotify Connect remote control; YouTube's own embedded
player). Neither decodes the other service's audio inside Omnis's own
engine — that's not a gap this project chose to leave, it's a hard
platform/ToS ceiling.
