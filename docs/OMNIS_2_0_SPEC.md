# Omnis — Ultimate All-in-One Music Platform

## Master Rebuild Specification v2.0

> **Status:** Canonical reference for the Omnis direction. Supersedes
> the original `OMNIS_2_0_SPEC.md` (retired 2026-08-15) — this is the
> **authoritative master build specification going forward**, not a
> wishlist appended to the old one. It merges:
>
> 1. The original Omnis/Omnis-Plugins architecture (Core, `plugin_api`,
>    `ServiceRegistry`, `EventBus`, `PluginContext`, plugin storage,
>    sandboxing, runtime plugin loading) — **preserved, not discarded**.
> 2. The previous "ultimate all-in-one music player" ambitions.
> 3. A full competitive gap analysis against MusicBee (see
>    [OMNIS_2_0_MUSICBEE_COMPARISON.md](OMNIS_2_0_MUSICBEE_COMPARISON.md)
>    for that analysis in full — this spec is built from it).
> 4. What's already implemented in Omnis today.
> 5. The plugin-first architecture and `ServiceRegistry`/`EventBus` work.
> 6. The cross-platform Flutter requirement (Android/Windows/Linux/macOS/iOS).
> 7. The no-API-key / minimal-setup requirement.
> 8. The customizable UI/theme/layout system.
> 9. Advanced audio/DSP/audiophile requirements.
> 10. Future AI, discovery, DJ, automation, device, streaming, podcast,
>     audiobook, radio and server ecosystem plans.
>
> Deliberately aspirational in many places — not everything here is
> built yet. **[OMNIS_2_0_FINISHED_TASK.md](OMNIS_2_0_FINISHED_TASK.md)
> is the authoritative record of what's actually implemented and
> verified**; this document describes where Omnis is going and why.
>
> **The Omnis build always uses these references together:**
>
> 1. This document — the product specification (everything the Core
>    must do, and the shape of the plugin ecosystem around it).
> 2. [OMNIS_2_0_UI_SPEC.md](OMNIS_2_0_UI_SPEC.md) — the UI/UX Master
>    Design Specification (how the interface must look, feel, and be
>    customized).
> 3. [OMNIS_2_0_PLUGINS.md](OMNIS_2_0_PLUGINS.md) — the Plugin
>    Architecture & Developer Guide (the plugin platform, marketplace,
>    and plugin hub).
> 4. [OMNIS_2_0_MUSICBEE_COMPARISON.md](OMNIS_2_0_MUSICBEE_COMPARISON.md)
>    — the competitive gap analysis this spec was built from.
> 5. [OMNIS_2_0_FINISHED_TASK.md](OMNIS_2_0_FINISHED_TASK.md) — the live
>    build tracker: what's actually built, phase by phase, with dated
>    evidence for every claim.
>
> Read all before building any Omnis feature.

---

### Core objective

Build **Omnis** as a complete, cross-platform music operating environment rather than simply another music player.

Target:

- Android
- Windows
- Linux
- macOS
- iOS

The application must be capable of functioning as:

- Music player
- Music library manager
- Tag editor
- Metadata manager
- File organizer
- Audio analyzer
- Audiophile player
- Playlist manager
- Streaming client
- Internet radio
- Podcast manager
- Audiobook player
- DJ system
- Music discovery engine
- Music statistics platform
- Device synchronization system
- Network music client/server
- Remote-controlled player
- Automation platform
- Plugin platform

while keeping the **core small, reliable and maintainable**.

---

# 1. FUNDAMENTAL ARCHITECTURE

The most important rule:

> **Core functionality required to play and manage local music belongs in Core. Optional functionality belongs in plugins.**

However, "plugin" does **not** mean every tiny feature needs to be separately installed.

Omnis should ship with a **curated first-party plugin bundle**.

The user should install Omnis and immediately have a complete experience.

No:

- API-key hunting
- manual dependency installation
- complicated configuration
- downloading 50 plugins individually
- editing configuration files

---

# 2. CORE

The Core owns only functionality that other functionality fundamentally depends upon.

## Core components

```text
lib/
├── core/
│   ├── audio/
│   ├── database/
│   ├── library/
│   ├── queue/
│   ├── playlists/
│   ├── history/
│   ├── metadata/
│   ├── search/
│   ├── services/
│   ├── events/
│   ├── plugins/
│   ├── storage/
│   ├── settings/
│   ├── permissions/
│   ├── networking/
│   ├── diagnostics/
│   └── platform/
│
├── plugin_api/
│
├── ui/
│
└── main.dart
```

---

# 3. EXISTING ARCHITECTURE MUST BE PRESERVED

The work already completed should **not be thrown away**.

Keep and expand:

### ServiceRegistry

Capability-based lookup:

```dart
context.services.register<ILyricsProvider>(provider);
```

Consumers request capabilities:

```dart
services.get<ILyricsProvider>();
```

Never make application code depend directly upon concrete plugin classes.

---

### EventBus

Typed application events:

```text
TrackStarted
TrackChanged
PlaybackStarted
PlaybackPaused
PlaybackStopped
PlaybackCompleted
QueueChanged
LibraryChanged
MetadataChanged
ArtworkChanged
RatingChanged
FavoriteChanged
PluginLoaded
PluginUnloaded
DeviceConnected
DeviceDisconnected
```

This becomes the nervous system of Omnis.

---

### PluginContext

Every plugin receives controlled access to:

- ServiceRegistry
- EventBus
- Storage
- Settings
- Logging
- Permissions
- platform services
- networking where permitted

---

# 4. PLUGIN CAPABILITY SYSTEM

The plugin API needs to eventually support:

```text
IAudioDecoder
IAudioOutput
IAudioDSP
ILibraryProvider
ILibraryScanner
IMetadataProvider
IArtworkProvider
ILyricsProvider
IPlayHistoryProvider
IRatingProvider
IFavoriteProvider
IPlaylistProvider
ISmartPlaylistProvider
IQueueProvider
IRecommendationProvider
IAudioAnalysisProvider
IStreamingProvider
IRadioProvider
IPodcastProvider
IAudiobookProvider
IDeviceProvider
IDeviceSyncProvider
ICDReader
ICDBurner
IAudioConverter
INetworkRenderer
INetworkServer
IRemoteControlProvider
ISearchProvider
ITagProvider
IFileOrganizer
IBackupProvider
IStatisticsProvider
IThemeProvider
ILayoutProvider
IVoiceControlProvider
IAutomationProvider
IScriptingProvider
IVisualizerProvider
IImportProvider
IExportProvider
```

This is the foundation that lets Omnis eventually absorb the entire MusicBee feature set without turning the Core into a monolith.

*(Already real as of this session, in `packages/omnis_plugin_api/lib/service_interfaces.dart`: `ILyricsProvider`, `IPlayHistoryProvider`, `IRatingsProvider`, `IQueueBuilder`, `IMetadataProvider`, `IAudioAnalysisProvider`, `IFileTagWriter`, `IVisualizerProvider`, `IArtistImageProvider`, `IDeviceConnectivityProvider`, `IAIProvider`. Everything else in the list above is still a gap — see `OMNIS_2_0_MUSICBEE_COMPARISON.md` §41 for the mapping.)*

---

# 5. RELIABILITY FIRST

Before expanding functionality, playback must become extremely reliable.

## Playback watchdog

Detect:

- decoder lockup
- output failure
- stalled playback
- invalid position
- buffer starvation
- stream timeout
- device disappearance
- plugin failure

Automatic recovery:

```text
Failure
 ↓
Detect
 ↓
Pause
 ↓
Reinitialize
 ↓
Restore position
 ↓
Resume
 ↓
Report diagnostic
```

A plugin crash must **never crash Omnis**.

*(`PlaybackWatchdog`/`PlaybackRecovery`/`RecoveryJournal` already implement a real version of this — see item 1's tracker entry.)*

---

# 6. DATABASE

The database becomes the central source of truth.

## Track model

Store:

- ID
- URI/path
- filename
- title
- sort title
- artist
- album artist
- album
- sort artist
- sort album
- composer
- lyricist
- producer
- genre
- grouping
- year
- original year
- date added
- disc
- track
- total discs
- total tracks
- duration
- bitrate
- sample rate
- bit depth
- codec
- container
- channels
- file size
- ReplayGain
- loudness
- peak
- BPM
- key
- mood
- energy
- rating
- favorite
- play count
- skip count
- last played
- last skipped
- lyrics state
- artwork state
- metadata confidence
- provider IDs
- custom fields

*(`BaseTrack` in `packages/omnis_plugin_api/lib/base_track.dart` already covers a large subset: id, title, artists, album, duration, trackNumber, discNumber, year, genres, bpm, key, mood, coverArt, type, spotifyId, youtubeId, localPath, streamUrl, replayGain, albumArtist, releaseType, releaseDate, dateAdded, fileModifiedAt, codec, sampleRateHz, bitDepth, bitrateKbps, channels — with real value equality since this session's fix. Composer/lyricist/producer/grouping/original-year/energy/provider-confidence and true multi-role-artist modeling are still open, see §48.)*

---

# 7. MULTI-SOURCE LIBRARY

Support:

- local folders
- multiple drives
- removable drives
- NAS
- SMB
- network shares
- external storage
- server libraries
- streaming providers
- OpenSubsonic-compatible servers

Each source gets:

- enabled/disabled
- priority
- scan schedule
- inclusion rules
- exclusion rules
- offline state
- authentication
- cache settings

---

# 8. INDUSTRIAL LIBRARY SCANNER

The scanner must handle enormous libraries.

Support:

- incremental scanning
- filesystem watchers
- full scans
- hash detection
- file identity
- moved-file detection
- renamed-file detection
- missing-file detection
- duplicate detection
- corrupt-file detection
- metadata-only scan
- artwork-only scan
- audio-analysis scan

Scanning must be:

- cancellable
- resumable
- parallelized
- low-priority
- observable
- fault tolerant

---

# 9. LIBRARY HEALTH CENTER

New major system.

```text
LIBRARY HEALTH

Missing files             32
Duplicates                184
Missing artwork           91
Missing metadata          27
Invalid tags              16
Corrupt files              3
Short tracks              12
Low-quality files         48
Unorganized files         74
```

Every category should provide:

**Fix All / Review / Ignore**

with undo.

*(`LibraryCleanupAnalyzer`/`library_cleanup_report_page.dart` — item 17 — already covers missing artwork, inconsistent artist/genre, duplicate tracks, missing year, malformed track numbers, duplicate albums, and a corrupt-file heuristic. Missing-file detection, low-quality-file flagging, and unorganized-file detection are still open.)*

---

# 10. AUTO-TAGGER

Dedicated first-party metadata system.

Providers:

- MusicBrainz
- Discogs
- Last.fm
- embedded metadata
- other supported providers

Workflow:

```text
Analyze
 ↓
Find candidates
 ↓
Calculate confidence
 ↓
Compare metadata
 ↓
Preview changes
 ↓
Apply
```

Never silently destroy metadata.

*(`MetadataEnrichmentPlugin` already queries MusicBrainz/Last.fm/Discogs and merges results — item 11's tracker entry. The compare/preview/confidence-score workflow below and multi-source conflict resolution (§11) are still open; today's `library_page.dart` enrichment action applies results directly, additively, without a preview step.)*

---

# 11. METADATA CONFLICT ENGINE

If providers disagree:

```text
MusicBrainz → Rock
Discogs     → Alternative Rock
Last.fm     → Alternative
```

Omnis should use configurable provider priority plus confidence scoring.

The user can define:

```text
MusicBrainz
↓
Discogs
↓
Last.fm
↓
Embedded
```

---

# 12. ADVANCED TAG EDITOR

Support:

- bulk editing
- custom fields
- multi-value tags
- copy
- paste
- swap
- merge
- split
- regex
- search/replace
- capitalization
- normalization
- calculated tags
- virtual tags
- templates
- tag history
- undo

*(`TagEditorPlugin` already does real ID3v1/ID3v2/Vorbis/FLAC/MP4/OGG/etc. tag reading/writing — item 20's tracker entry. Regex search/replace, virtual/calculated tags, and tag history/undo are still open.)*

---

# 13. TAG BACKUP SYSTEM

Before bulk changes:

```text
Create Backup

4,382 tracks
21,902 fields

[Cancel] [Continue]
```

Allow complete restoration.

---

# 14. FILE ORGANIZER

Create an advanced template engine:

```text
$AlbumArtist/
$Artist/
$Year/
$Album/
$DiscNumber/
$TrackNumber/
$Title
```

Example:

```text
$AlbumArtist/$Year - $Album/$DiscNumber-$TrackNumber - $Title
```

Features:

- preview
- rename
- move
- copy
- merge
- sanitize
- duplicate collision handling
- undo
- transaction history

---

# 15. UNIVERSAL SEARCH

One search system across the entire application.

Search:

- tracks
- albums
- artists
- genres
- playlists
- folders
- lyrics
- podcasts
- radio
- streaming
- settings
- commands
- plugins

Advanced queries:

```text
artist:"Linkin Park"
genre:rock
year:2000..2010
rating:>=4
bpm:120..140
format:flac
favorite:true
```

*(`lib/core/library_search.dart` — item 10 — already supports free text plus `artist:`/`album:`/`genre:`/`title:`/`mood:`/`year:` qualifiers, AND-combined. `rating:`/`bpm:`/`format:`/`favorite:` qualifiers and a single search surface spanning playlists/lyrics/podcasts/settings/commands are still open — see §40's command-palette note too.)*

---

# 16. PLAYLIST ENGINE

Support:

### Static playlists

User-controlled. *(Real — `PlaylistStore`.)*

### Smart playlists

Rule driven. *(Real — `SmartPlaylistPlugin`, item 42.)*

### Dynamic playlists

Continuously generated. *(Partial — `QueuePresetPlugin`'s BPM/genre/history-based presets, item 39.)*

### Temporary playlists

Session-only.

### Queue playlists

Saved queue states. *(Real — `QueueHistoryStore`, item 2: auto-history + named permanent snapshots.)*

---

# 17. SMART PLAYLIST ENGINE

Support:

```text
AND
OR
NOT
```

Conditions:

- artist
- album
- genre
- year
- rating
- favorite
- BPM
- key
- mood
- energy
- play count
- skip count
- last played
- date added
- duration
- bitrate
- codec
- folder
- format
- lyrics
- artwork
- ReplayGain
- custom tags

Limits:

- number of songs
- total duration
- random
- weighted random
- artist repetition
- album repetition

*(`SmartPlaylistPlugin`'s `RuleCondition`/`RuleMatchType` — item 42 — already supports ALL/ANY/NONE over title/artist/album/genre/mood/year/rating with `contains`/`equals` and full numeric comparisons. Nested AND/OR/NOT groups, play-count/skip-count/BPM/key/duration/bitrate/codec/folder/format/lyrics/artwork/ReplayGain conditions, and result limits are still open — see `OMNIS_2_0_MUSICBEE_COMPARISON.md` §6.)*

---

# 18. QUEUE ENGINE

Advanced queue:

- drag/drop
- reorder
- play next
- play last
- clear played
- save queue
- restore queue
- queue history
- queue presets
- smart queue
- automatic queue
- BPM progression
- energy progression
- artist repetition prevention
- album repetition prevention

*(`AudioEngine.playNext`/`addTrack`/`setQueue`, `QueueHistoryStore` (item 2), and `QueuePresetPlugin` (item 39) already cover play-next/add-to-queue/queue history/presets. Drag/drop reordering in the UI, "don't repeat artist/album," and BPM/energy progression rules are still open.)*

---

# 19. PLAYBACK

Core playback:

- gapless
- crossfade
- fade-in
- fade-out
- ReplayGain
- volume normalization
- pitch
- speed
- A/B repeat
- skip silence
- sleep timer
- resume position
- per-track position

*(All real — `AudioEngine`/`AbRepeatController`/`ReplayGainPlugin`/`SleepTimerPlugin`/`RecoveryJournal`. Item 1's tracker entry has the detail.)*

---

# 20. AUDIO DSP PIPELINE

Create a standardized pipeline:

```text
Decoder
 ↓
ReplayGain
 ↓
Preamp
 ↓
EQ
 ↓
Bass
 ↓
Compressor
 ↓
Limiter
 ↓
Stereo tools
 ↓
Crossfeed
 ↓
Virtualizer
 ↓
Resampler
 ↓
Output
```

Every stage can be provided by a plugin.

*(Item 18's tracker entry: today this is a flat named-multiplier gain-composition system, `AudioEngine.setGainContribution` — not a staged, independently-replaceable chain. Zero compressor/limiter/crossfeed/convolver/spatializer/room-correction exists anywhere yet. This is one of the larger, genuinely deferred gaps.)*

---

# 21. AUDIOPHILE OUTPUT

Windows:

- WASAPI Shared
- WASAPI Exclusive
- ASIO
- DirectSound

Linux:

- PipeWire
- PulseAudio
- ALSA

macOS:

- CoreAudio

Android:

- AudioTrack
- AAudio
- USB DAC

iOS:

- AVAudioEngine/CoreAudio-compatible output

---

# 22. ADVANCED AUDIO ANALYSIS

The existing Essentia plugin should grow into:

- BPM
- key
- beat grid
- energy
- danceability
- valence
- acousticness
- instrumentalness
- speechiness
- loudness
- dynamic range
- spectral analysis
- waveform
- fingerprint

*(`AudioAnalysisPlugin` — item 23 — already gets real BPM/key/mood/genre from a self-hosted Essentia service. Everything else in this list is still open.)*

---

# 23. LOUDNESS

Support:

- ReplayGain Track
- ReplayGain Album
- LUFS
- integrated loudness
- loudness range
- peak
- true peak
- clipping detection
- dynamic range

*(Track/album ReplayGain modes are real — item 19, this session. LUFS/true-peak/clipping/dynamic-range measurement is still open.)*

---

# 24. AUDIO CONVERTER

First-class batch conversion.

Presets:

```text
FLAC → MP3 320
FLAC → MP3 V0
FLAC → AAC 256
FLAC → Opus 160
WAV → FLAC
ALAC → FLAC
```

Use FFmpeg where appropriate.

Preserve:

- metadata
- artwork
- chapters
- ReplayGain
- filenames

---

# 25. CD SYSTEM

### CD ripping

- secure ripping
- metadata lookup
- artwork
- AccurateRip-compatible verification where feasible
- drive offset
- FLAC
- ALAC
- WAV
- MP3
- AAC
- automatic organization

### CD burning

- Audio CD
- Data CD
- CD-Text
- playlist burning

---

# 26. CUE SUPPORT

Support:

- external CUE
- embedded CUE
- multi-track FLAC
- WAV
- APE
- disc indexes
- gaps

A single image file should appear as individual tracks to the user.

---

# 27. PODCAST SYSTEM

Support:

- RSS
- OPML
- subscriptions
- downloads
- automatic downloads
- episode history
- resume
- speed
- skip intro/outro
- chapters
- show notes
- artwork
- offline playback
- auto-delete

---

# 28. INTERNET RADIO

Support:

- Icecast
- Shoutcast
- M3U
- PLS
- XSPF
- direct streams

Features:

- search
- favorites
- history
- metadata
- artwork
- recording

*(Real already — `RadioPlugin`, item 41: Radio Browser directory search/top-stations/by-tag, favorites, custom stream URL entry. Recording and automatic genre classification are still open; single fixed API mirror rather than full DNS-round-robin discovery is a documented production-scale limitation.)*

---

# 29. AUDIOBOOK SYSTEM

Support:

- M4B
- chapters
- author
- narrator
- series
- bookmarks
- resume
- speed
- sleep timer
- chapter navigation
- audiobook-specific library

---

# 30. DEVICE MANAGER

Sync with:

- Android
- iOS
- USB storage
- SD cards
- portable players
- network devices

Sync:

- music
- playlists
- ratings
- favorites
- podcasts
- audiobooks

Conversion during sync:

```text
FLAC → AAC 256
```

---

# 31. NETWORK MUSIC

Support:

- SMB
- WebDAV
- SFTP
- HTTP
- HTTPS
- NAS
- OpenSubsonic
- Jellyfin
- Plex where practical

*(OpenSubsonic/Jellyfin/Plex clients are already real — items 31/32/33/34's tracker entries — all self-flagged as protocol-correct but not exercised against a live server. SMB/WebDAV/SFTP/NAS discovery are still open.)*

---

# 32. NETWORK PLAYBACK

Long-term:

- UPnP
- DLNA
- Chromecast
- AirPlay
- Sonos
- Spotify Connect
- network speakers

*(A DLNA/UPnP **client** already exists — item 35. Spotify Connect remote control is real too (`SpotifyPlaybackPlugin`, item 36, self-flagged unverified against a real account). UPnP/DLNA server role, Chromecast, AirPlay, and Sonos/Home Assistant integration are still open.)*

---

# 33. REMOTE API

This should be part of the Omnis platform.

REST:

```text
/play
/pause
/next
/previous
/seek
/queue
/search
/playlists
/library
/now-playing
/artwork
```

WebSocket:

```text
trackChanged
playbackChanged
queueChanged
volumeChanged
metadataChanged
```

This allows:

- phone remote
- web remote
- Stream Deck
- Home Assistant
- Discord integrations
- OBS
- smart-home integrations

---

# 34. PARTY MODE

QR-based joining.

Guests can:

- browse
- request
- vote
- add songs
- react

Host controls:

- skip
- remove
- reorder
- ban tracks
- restrict users

---

# 35. STATISTICS

Track:

- play count
- skip count
- completion percentage
- listening duration
- first played
- last played
- favorite
- rating
- source
- device
- playlist

Dashboard:

```text
Today
This Week
This Month
This Year
All Time
```

Charts:

- artists
- albums
- genres
- decades
- hours
- days
- listening streaks

*(`PlayHistoryStore`/`ScrobblePlugin` — item 16 — already track play count, last played, position, and per-play records with real hardening (atomic writes, per-entry decode safety, concurrency serialization). A dedicated statistics dashboard with charts is still open.)*

---

# 36. DISCOVERY ENGINE

Create:

### Play Something

- Familiar
- Forgotten
- New
- Deep Cuts
- Similar
- Chill
- High Energy
- Random
- Surprise Me

Recommendations use:

- history
- ratings
- favorites
- skips
- BPM
- key
- mood
- genre
- artist
- album
- listening patterns

*(Item 39's tracker entry lists what's real: "Forgotten Favorites," "Rediscover," and "Similar Track" (item 40, this session — `lib/core/track_similarity.dart`). Still missing: Similar Artist, Daily/Weekly Mix, Discovery, Deep Cuts, New Releases, Energy Flow, and a unified "Play Something" entry point surfacing all of these as named buttons.)*

---

# 37. FORGOTTEN MUSIC

Automatically find music the user owns but rarely plays.

Example:

> **147 tracks you haven't heard in 6+ months**

Button:

**Play Forgotten Music**

*(Real already, as a queue preset — `QueuePresetPlugin`'s "Forgotten Favorites," item 39. A dedicated browsing view (not just a play-queue action) is still open.)*

---

# 38. DJ MODE

Support:

- waveforms
- BPM
- key
- beat grid
- cue points
- loops
- hot cues
- beat matching
- automix
- key matching
- energy matching
- transition recommendations

---

# 39. AUTOMATION ENGINE

Rule:

```text
WHEN
    Bluetooth device = Car

IF
    Time between 6AM and 10AM

THEN
    Car Mode
    Playlist = Morning Drive
    Volume = 75%
```

Triggers:

- track started
- track ended
- device connected
- device disconnected
- time
- location where platform permits
- application launch
- plugin event
- library changed

Actions:

- play
- pause
- queue
- change EQ
- change volume
- enable mode
- launch playlist
- download
- sync
- execute automation

*(Item 50's tracker entry: two real, working single-purpose triggers exist today — GPS-speed → Car Mode layout (`DrivingModePlugin`), Bluetooth-connect → quick-play/EQ-preset prompt — but no general rules engine, no time-based triggers.)*

---

# 40. UI SYSTEM

The existing requested primary areas remain:

```text
Home
Library
Moods
Playlists
Now Playing
```

Plus:

- Albums
- Artists
- Genres
- Tracks
- Folders
- Podcasts
- Audiobooks
- Radio
- Devices
- Statistics
- Downloads
- Settings

*(Radio is already a real bottom-nav tab — item 41. Podcasts/Audiobooks/Devices/Statistics tabs are still open. A unified command-palette-style search across settings/commands/library — items 10/45/48's own tracker entries — is also still open.)*

---

# 41. CUSTOMIZABLE SIDEBAR

Users can:

- reorder
- hide
- add
- remove
- create sections
- create shortcuts
- create custom pages

---

# 42. UI MODES

Ship with:

### Simple

Minimal controls.

### Driving

Huge controls. *(Real — `CarModeLayout`, item 46.)*

### Karaoke

Lyrics-first. *(Real — one of the 6 bundled Now Playing layouts, item 45.)*

### Futuristic

Visualizer/album-art-focused.

Also:

- Desktop
- Tablet
- Mobile
- TV
- Compact
- Audiophile
- DJ

*(Item 45's tracker entry: the Now Playing layout builder is solid — a real drag-and-drop visual editor, `LayoutEditorPage`, 6 bundled layouts including Car Mode/Karaoke. The Home tab itself is still "0% for Home" — `home_dashboard_page.dart` is a hardcoded, non-reorderable widget with fixed sections, no widget-canvas equivalent.)*

---

# 43. USER-CREATED THEMES

Users can customize:

- colors
- fonts
- spacing
- cards
- borders
- corner radius
- artwork sizes
- animations
- backgrounds
- navigation
- controls

Allow exporting/importing themes.

*(Item 44's tracker entry: a real declarative theme engine already exists — import from URL/file, closed-schema colors/typography/shape/motion — but none of the spec's 6 named presets (Pure/Drive/Karaoke/Future/Audiophile) survive by name, only 4 original substitutes. Themes don't yet touch navigation/Home/Library layout the way "theme = composition" demands.)*

---

# 44. DYNAMIC THEMING

Album artwork can generate:

- primary color
- accent
- background
- text contrast
- gradients

---

# 45. NOW PLAYING

Now Playing becomes a customizable workspace.

Components:

- artwork
- waveform
- lyrics
- queue
- metadata
- visualization
- credits
- equalizer
- audio analysis
- controls

Users decide the layout.

*(Real — see §42's note on item 45's layout builder.)*

---

# 46. LYRICS

Existing lyrics capability should remain.

Expand:

- synchronized lyrics
- plain lyrics
- embedded lyrics
- translated lyrics
- lyric provider priority
- offline lyrics
- karaoke mode
- lyric editing
- timestamp editor

*(`LyricsPlugin` already supports manual entry, LRCLIB lookup, LRC parsing with synchronized playback, and file-metadata embedding via `IFileTagWriter`. Translation, provider priority among multiple sources, and a timestamp editor are still open.)*

---

# 47. ARTWORK

Support:

- embedded artwork
- external artwork
- artist images
- album artwork
- back cover
- booklet
- CD image
- genre images

Artwork manager:

**Find → Compare → Preview → Apply**

*(Item 12's tracker entry: `BaseTrack.coverArt`, Android `mediastore://` artwork, embedded-artwork extraction, `ArtistImagePlugin`, and `TrackArtwork` are all real. No artwork-provider framework (Cover Art Archive/Fanart.tv lookup) or manual/drag-drop override yet.)*

---

# 48. MULTIPLE ARTISTS

Don't store every collaboration as a single opaque artist string.

Internally model:

```text
Primary Artist
Featured Artists
Remixer
Composer
Producer
```

while maintaining compatibility with file tags.

*(Featured-artist separator rules already exist for parsing display strings. A real primary/featured-artist data model (not a joined display string) and proper "Various Artists" compilation modeling are still open.)*

---

# 49. IMPORT/EXPORT

Import:

- MusicBee
- foobar2000
- iTunes/Apple Music
- Windows Media Player
- MediaMonkey
- Winamp
- VLC
- AIMP
- Plex
- Jellyfin
- Spotify
- YouTube Music

Preserve where possible:

- playlists
- ratings
- favorites
- play counts
- history

Export:

- M3U
- M3U8
- XSPF
- PLS
- JSON
- CSV

*(M3U/M3U8/PLS/XSPF playlist import+export are real — item 13, this session. Spotify/YouTube Music playlist import are real too — items 36/37. Importers for other players (MusicBee, foobar2000, iTunes, WMP, MediaMonkey, Winamp, VLC, AIMP, Plex, Jellyfin) and CSV/JSON export are still open.)*

---

# 50. BACKUP

Backup:

- database
- playlists
- ratings
- history
- settings
- plugin data
- themes
- layouts
- metadata
- artwork

Automatic scheduled backups.

*(Real already — `backup_service.dart` + Settings → Backup page, item 4: one-click backup/restore of library/playlists/play-history/recovery-journal, validated before overwrite. Plugin-settings/theme/layout backup and automatic scheduling are still open.)*

---

# 51. SECURITY

Plugins receive explicit permissions.

Examples:

```text
Filesystem
Network
Microphone
Bluetooth
Device Access
Account Access
External Process
```

Plugin installation displays:

```text
This plugin requests:

☑ Network
☑ Music Library
☐ Microphone
☐ External Processes
```

*(Real already — item 25/27's tracker entries: real sandboxing (`PluginSandbox.run`), a real interpreted sandbox (`dart_eval`) for downloaded plugins, scoped network permissions (`network:host.example.com`, not just blanket `network`), and plain-English permission labels on the Plugins page.)*

---

# 52. PLUGIN HEALTH

Every plugin gets:

- version
- dependencies
- permissions
- status
- errors
- CPU usage
- memory usage
- last crash
- logs

Controls:

**Enable / Disable / Restart / Update / Rollback**

*(Item 25's tracker entry: real sandboxing catches + 8s-timeouts every hook and logs health, never propagating a crash. No formal state-machine enum yet (two booleans instead), and `dart_eval` runs on the same thread so a non-yielding downloaded-plugin loop can still hang the UI — documented in `docs/PLUGIN_SECURITY.md`. Plugin update checking/rollback are real — item 29 — but with no backup-before-update/automatic-checking yet.)*

---

# 53. PLUGIN MARKETPLACE

Eventually support:

- discovery
- search
- categories
- versions
- ratings
- screenshots
- permissions
- dependencies
- compatibility
- automatic updates

But Omnis must remain fully functional without third-party plugins.

*(Catalog search is real — item 30. A real marketplace (ratings, screenshots, categories, automatic updates) is still open — today's catalog is a curated list with search/filter, update checking, and manual GitHub-URL installation for anything outside it.)*

---

# 54. NO-API-KEY EXPERIENCE

This remains a hard requirement.

Whenever possible:

```text
Install plugin
↓
Ready
```

Not:

```text
Install
↓
Create account
↓
Find developer portal
↓
Generate key
↓
Copy secret
↓
Create OAuth app
↓
Configure redirect
```

For services that inherently require authentication, Omnis should provide a guided OAuth/login flow.

*(MusicBrainz needs no key at all. Spotify/YouTube already use real PKCE OAuth (`SpotifyAuth`/`YoutubeAuth`) rather than asking the user to register a developer app. Last.fm/Discogs/self-hosted-server credentials (OpenSubsonic/Jellyfin/Plex) still require the user to supply their own key/token — a documented, honest limitation, not an oversight — a fully "managed provider gateway" that hides even those behind a built-in OAuth configuration is still open and would need real backend infrastructure this project doesn't have.)*

---

# 55. OFFLINE-FIRST

Local music must work without Internet.

Offline capabilities:

- playback
- library
- playlists
- ratings
- favorites
- history
- artwork cache
- lyrics cache
- metadata already downloaded
- statistics
- smart playlists

Internet functionality should degrade gracefully.

*(Already true for everything except live-network-backed plugins, which already fail soft — e.g. `LyricsPlugin`'s `fetchLyrics` degrades to cached/manual lyrics on a network exception rather than throwing.)*

---

# 56. AI SYSTEM

AI should be **optional**, never required for core playback.

Potential capabilities:

- natural-language search
- playlist generation
- music recommendations
- metadata cleanup
- tag correction
- genre classification
- mood classification
- artist summaries
- album summaries
- conversational music discovery

Example:

> "Make me a 90-minute playlist of energetic 2000s rock without songs I've played this week."

Omnis generates a smart playlist.

*(`AIPlaylistPlugin` — item 43 — already does exactly this example via a real `IAIProvider` capability interface and Anthropic's Messages API: a natural-language prompt becomes a real queue, with every returned track id checked against the actual library so the model can never invent one. Self-flagged unverified against the real Anthropic API — protocol-level correctness only. Natural-language search, metadata cleanup, tagging, a conversational library assistant, and voice control are all still genuine 0%.)*

---

# 57. VOICE CONTROL

Eventually:

> "Play my favorite Linkin Park songs."

> "Add this to my driving playlist."

> "Play something I haven't heard in six months."

> "Turn the volume down."

---

# 58. ACCESSIBILITY

Required:

- screen reader support
- keyboard navigation
- high contrast
- scalable UI
- reduced motion
- large controls
- colorblind-safe states
- captions where applicable
- accessible lyrics
- voice controls

*(Item 48's tracker entry: "Reduce motion"/"Reduce transparency"/"Haptic feedback"/"High contrast" (closed 2026-08-15) all live in a dedicated Accessibility settings category. Keyboard shortcuts exist too. App-wide text scaling and full keyboard navigation are still open.)*

---

# 59. PLATFORM REQUIREMENTS

### Windows

- WASAPI
- ASIO
- media keys
- system tray
- notifications
- portable mode
- installer
- Windows media integration

*(SMTC integration is real. Windows build is currently blocked in this dev environment specifically by a Flutter-SDK/Visual-Studio-version CMake generator mismatch — documented in `docs/BUILDING.md` — not a code problem; GitHub Actions' `windows-latest` runner builds it independently in CI.)*

### Android

- background playback
- notification controls
- lock screen
- Android Auto
- Bluetooth
- widgets
- download manager

*(`audio_service` notification/lock-screen controls, a Home-screen widget, and `BluetoothPlaybackPlugin` are all real. Real-device smoke-testing confirmed working on an Android emulator this session. Android Auto is still open.)*

### iOS

- background audio
- lock screen controls
- CarPlay
- Siri integration where practical
- Files integration

### macOS

- CoreAudio
- media keys
- menu bar
- notifications
- AirPlay integration

### Linux

- PipeWire
- PulseAudio
- ALSA
- MPRIS
- desktop notifications

---

# 60. DEVELOPMENT RULE

Every feature must answer:

### Is this Core?

If another subsystem cannot function without it:

**Core.**

Otherwise:

**Plugin.**

Example:

**Audio playback engine**

Core.

**Spotify**

Plugin.

**MusicBrainz**

Plugin.

**DSP framework**

Core capability.

**Equalizer**

Plugin.

**Library database**

Core.

**Podcast provider**

Plugin.

**Playlist engine**

Core.

**Podcast UI**

Plugin/module.

---

# 61. IMPLEMENTATION PHASES

The rebuild should **not attempt everything simultaneously**.

## Phase 1 — Core stabilization

- ServiceRegistry
- EventBus
- PluginContext
- database
- audio engine
- playback watchdog
- settings
- plugin lifecycle
- diagnostics
- storage
- migrations

## Phase 2 — Library 2.0

- scanner
- watcher
- database
- multiple sources
- search
- duplicates
- missing files
- health center

## Phase 3 — Music management

- advanced tags
- auto-tagging
- artwork
- file organizer
- backup/restore
- CUE

## Phase 4 — Playlist/history

- smart playlists
- queue engine
- history
- statistics
- ratings
- favorites
- recommendations

## Phase 5 — Audio

- DSP pipeline
- ReplayGain
- loudness
- analysis
- WASAPI
- ASIO
- platform outputs
- conversion

## Phase 6 — Media expansion

- podcasts
- radio
- audiobooks
- CD ripping
- CD burning

## Phase 7 — Devices/network

- sync
- NAS
- OpenSubsonic
- UPnP
- DLNA
- Chromecast
- AirPlay
- remote API

## Phase 8 — Intelligence

- discovery
- AI
- natural language search
- DJ
- automix
- automation

## Phase 9 — Ecosystem

- marketplace
- plugin SDK
- developer documentation
- plugin certification
- plugin updates
- remote clients

*(This is the target phase shape going forward. `OMNIS_2_0_FINISHED_TASK.md`'s existing phase table — Phase 1 Reliability through Phase 7 Advanced UX — maps onto Phases 1-4 and 8-9 above fairly directly; Phases 5-7 above (Audio/DSP depth, Media expansion, Devices/network) are the newest, least-started ground this spec adds relative to the old tracker's phase list.)*

---

# 62. DEFINITION OF DONE

Omnis should **not** be considered complete simply because it launches and plays an MP3.

The ultimate release target is:

### Music Management

- Library
- Scanner
- Tagging
- Auto-tagging
- Artwork
- File organization
- Duplicates
- Search
- Smart playlists
- Statistics

### Playback

- Local playback
- Gapless
- Crossfade
- ReplayGain
- DSP
- Bit-perfect
- Audiophile output
- Multiple formats

### Media

- Music
- Podcasts
- Audiobooks
- Radio
- Streaming

### Connectivity

- Devices
- NAS
- Network servers
- Casting
- Remote control

### Intelligence

- Recommendations
- Discovery
- AI
- DJ
- Automation

### UI

- Desktop
- Mobile
- Driving
- Karaoke
- Futuristic
- Custom layouts
- Custom themes

### Architecture

- Plugin SDK
- ServiceRegistry
- EventBus
- Permissions
- Sandboxing
- Diagnostics
- Marketplace

---

# 63. THE NEW OMNIS POSITION

This changes the goal from:

> "Make a better music player than MusicBee."

to:

> **"Build an open, cross-platform music platform capable of everything MusicBee does, while adding modern streaming, mobile, AI, network, automation and plugin capabilities that MusicBee was never architecturally designed around."**

The competitive target becomes:

```text
             OMNIS
               │
   ┌───────────┼───────────┐
   │           │           │
MusicBee   foobar2000   Spotify
   │           │           │
   ├───────┐   │   ┌───────┤
   │       │   │   │       │
Plex    Music   │  YouTube  Apple
        players │  Music    Music
                │
             OMNIS
```

But **Omnis remains local-first, open, modular and user-controlled**.

---

## Most important change to the previous build direction

**Library 2.0 + Metadata/Tagging + Smart Playlist Engine + Audio/DSP + Plugin Capability APIs** are the immediate foundation.

Those five systems unlock almost everything else.

Because `ServiceRegistry`, `EventBus`, `PluginContext`, `ILyricsProvider`, `IPlayHistoryProvider`, plugin storage, migrations and the runtime plugin architecture already exist, **Omnis does not need to restart from zero**. The build migrates the current implementation into this larger specification rather than discarding the work already completed — the standing autonomous build directive continues to operate exactly as before: survey the actual current code state (this spec plus `OMNIS_2_0_MUSICBEE_COMPARISON.md` as additional candidate-gap sources once `OMNIS_2_0_FINISHED_TASK.md`'s own named items run thin), implement, test, document, commit, push, repeat.
