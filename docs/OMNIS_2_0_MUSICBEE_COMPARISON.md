# Omnis vs. MusicBee — Feature Comparison & Backlog Source

> **Status:** Reference document, not a tracker. Pasted in verbatim from
> user-supplied external research (2026-08-15) comparing Omnis against
> MusicBee's official feature set and add-on ecosystem. It is a
> **backlog source**, not ground truth about Omnis's current state —
> parts of it may already be stale (Omnis has shipped real features
> since this comparison was written, e.g. real playlist folders, PLS/
> XSPF import/export, a real similarity engine, favorites snapshots for
> non-local tracks). Before treating any gap named here as real and
> picking it as a survey target, verify it against the actual current
> code the same way every other survey in this session has —
> `docs/OMNIS_2_0_FINISHED_TASK.md`'s own item table is still the
> authoritative record of what's actually built; this document is where
> to look for *additional* candidate gaps once that table's own named
> items run thin, not a replacement for checking real code state.
>
> The recommended architectural stance (§49–§50 below) is worth reading
> even for engineers not picking a specific feature: keep the kernel
> small, add capability through `ServiceRegistry`/`PluginContext`
> interfaces, and grow the plugin ecosystem rather than the core.

---

Yes. I compared the current [MusicBee official site](https://getmusicbee.com/) and its current add-on ecosystem against both [Omnis](https://github.com/MrIvoe/Omnis) and [Omnis-Plugins](https://github.com/MrIvoe/Omnis-Plugins).

The important conclusion is:

> **Omnis already has a stronger architectural foundation than MusicBee, but MusicBee has an enormous amount of mature music-management functionality that Omnis currently doesn't have.**

MusicBee 3.6.9668 is still actively released as of June 20, 2026, and its official feature set covers playback, library management, tagging, DSP, device synchronization, CD ripping, podcasts, web radio, SoundCloud, add-ons and extensive customization.

Your current Omnis README describes a substantially smaller implemented surface: playback, library basics, lyrics, tagging, several metadata/streaming plugins, ratings/favorites, ReplayGain, smart queues, visualizer, Spotify/YouTube and the plugin infrastructure.

## 1. Biggest gaps

Here is the high-level comparison.

| Area                             | MusicBee                | Omnis                           | Priority            |
| --------------------------------- | ------------------------ | -------------------------------- | -------------------- |
| Local music library              | Excellent               | Good foundation                 | 🔴                  |
| Advanced tagging                 | Excellent               | Basic/medium                    | 🔴                  |
| Auto-tagging                     | Excellent               | Partial metadata enrichment     | 🔴                  |
| Auto-organize files              | Excellent               | Missing                         | 🔴                  |
| Library monitoring/watch folders | Excellent               | Needs expansion                 | 🔴                  |
| Smart playlists                  | Excellent               | Real rule engine (item 42)      | 🟡                  |
| Playlist management              | Excellent               | Folders + M3U/PLS/XSPF (item 13)| 🟡                  |
| Audio DSP                        | Excellent               | Basic EQ                        | 🔴                  |
| WASAPI/ASIO/exclusive output     | Yes                     | Missing/limited                 | 🔴                  |
| ReplayGain                       | Yes                     | Yes                             | ✅                   |
| Gapless                          | Yes                     | Yes                             | ✅                   |
| Crossfade                        | Yes                     | Yes                             | ✅                   |
| CD ripping                       | Yes                     | Missing                         | 🔴                  |
| CD burning                       | Yes                     | Missing                         | 🟠                  |
| Audio conversion                 | Yes                     | Missing                         | 🔴                  |
| Device sync                      | Excellent               | Missing                         | 🔴                  |
| Podcast management               | Yes                     | Missing                         | 🔴                  |
| Internet radio                   | Yes                     | Yes (RadioPlugin, item 41)      | ✅                   |
| Audiobooks                       | Yes                     | Missing/limited                 | 🔴                  |
| UPnP/DLNA                        | Yes via ecosystem       | Client only (item 35)           | 🟠                  |
| Chromecast                       | Ecosystem               | Missing                         | 🟠                  |
| Remote control                   | Ecosystem               | Foundation possible             | 🟠                  |
| Lyrics                           | Yes                     | Yes                             | ✅                   |
| Scrobbling                       | Yes                     | Yes                             | ✅                   |
| Visualizers                      | Yes                     | Yes                             | 🟡                  |
| Music statistics                 | Excellent               | Limited                         | 🔴                  |
| History                          | Yes                     | Real (PlayHistoryStore)         | 🟡                  |
| Audio analysis                   | Plugins                 | Plugin exists (Essentia)        | 🟡                  |
| BPM/key                          | Yes/ecosystem           | Plugin                          | 🟡                  |
| Mood analysis                    | Ecosystem               | Plugin                          | 🟡                  |
| Multiple libraries               | Yes                     | Needs work                      | 🟠                  |
| Portable mode                    | Yes                     | Needs packaging                 | 🟠                  |
| Skins/layouts                    | Excellent               | Strong architecture             | 🟡                  |
| Plugin ecosystem                 | Mature                  | Architecturally superior        | 🟡                  |
| Cross-platform                   | Windows-focused         | Android/Windows/Linux/macOS/iOS | **Omnis advantage** |
| Plugin isolation                 | Traditional DLL plugins | Sandboxed runtime               | **Omnis advantage** |
| Open source                      | No                      | Yes                             | **Omnis advantage** |

*(Note: the Smart playlists/Playlist management/Internet radio/History rows above have been annotated with this session's actual current state — this comparison document predates items 13/41/42's recent closures.)*

---

## 2. Library management is the biggest missing piece

This is where MusicBee is considerably ahead.

MusicBee isn't merely a player. It is fundamentally a **music-library management system**.

Omnis currently has:

- Songs
- Albums
- Artists
- Genres
- Folders
- duplicate detection
- short-track detection
- artwork
- tag editing
- metadata enrichment

That's a very good foundation.

But I would add:

### 🔴 Library sources

- Multiple library locations
- Multiple independent libraries
- Watch folders
- Recursive folder scanning
- Network shares
- removable drives
- external USB drives
- NAS libraries
- per-folder inclusion/exclusion
- per-folder scan settings
- ignore folders
- ignore file patterns
- hidden-file handling
- automatic library updates
- filesystem watcher
- manual rescan
- full database rebuild
- missing-file detection
- relocated-file detection
- library relocation tool

### 🔴 Library health center

Create something like:

**Library → Health**

with:

- Missing files
- Duplicate files
- Duplicate songs
- Duplicate albums
- Missing artwork
- Missing artist
- Missing album artist
- Missing genre
- Missing year
- Missing track number
- Invalid track numbers
- Invalid disc numbers
- Bad filenames
- Bad folder structure
- Unsupported formats
- Corrupt files
- Zero-duration files
- Very short tracks
- Very large files
- Low bitrate files
- inconsistent tags
- inconsistent capitalization
- inconsistent artist names
- inconsistent album names

This would be extremely valuable.

*(Note: `LibraryCleanupAnalyzer`/`library_cleanup_report_page.dart` — item 17 — already covers several of these: missing artwork, inconsistent artist/genre, duplicate tracks, missing year, malformed track numbers, duplicate albums, and a corrupt-file heuristic. The rest of this list — watch folders, per-folder scan settings, network shares, filesystem watcher, relocated-file detection, bad filenames/folder structure — is still genuinely open.)*

---

## 3. Auto-tagging needs to become a major system

MusicBee's auto-tagging is one of its major selling points. The official site specifically highlights automatic tagging for cleaning up messy libraries.

Omnis currently has:

- MusicBrainz
- Last.fm
- Discogs
- metadata enrichment
- ID3 editing

That's good, but it's not yet a **full auto-tagging workflow**.

You need:

### 🔴 Auto Tagger

A dedicated interface:

**Select tracks → Analyze → Compare → Preview → Apply**

Show:

```text
Current                    Proposed

Artist:    Linkin Park     Linkin Park
Album:     Hybrid Theory   Hybrid Theory
Year:      2000             2000
Genre:     Rock             Alternative Rock
Track:     01               01
Title:     Papercut         Papercut
Artwork:   ❌               ✅
```

Then:

- Apply selected fields
- Apply all
- Ignore
- Save as preset
- automatic confidence score
- metadata source priority
- artwork source priority

### Even better:

**Metadata conflict resolution**

MusicBrainz says:

> Alternative Rock

Last.fm says:

> Rock

Discogs says:

> Alternative

Omnis should determine:

> **Alternative Rock**

based on configurable source priority.

---

## 4. File organization is a huge missing feature

This should be one of the first major plugins.

### 🔴 Auto Organizer

MusicBee has extensive organization functionality, and its ecosystem has additional tooling around tags and file organization.

Omnis needs templates such as:

```text
Music/
 └── Artist/
     └── Year - Album/
         └── Disc-Track - Title.ext
```

But make it completely configurable:

```text
$AlbumArtist/
$Artist/
$Album/
$Year/
$DiscNumber/
$TrackNumber/
$Title/
$Genre/
```

Examples:

```text
Music/$AlbumArtist/$Year - $Album/$Disc-$Track - $Title
```

or:

```text
$Genre/$Artist/$Album/$Track - $Title
```

### Include:

- preview before moving
- rename
- move
- copy
- merge folders
- sanitize filenames
- illegal character replacement
- capitalization rules
- disc handling
- multi-artist handling
- compilation handling
- VA handling
- duplicate collision handling
- undo
- transaction log

**Undo is extremely important.**

---

## 5. Advanced tag manipulation

Your TagEditor is currently much more basic than the mature MusicBee tagging ecosystem.

MusicBee's plugin ecosystem includes extremely sophisticated operations such as copying/swapping tags, regular-expression search/replace, multi-step replacements, virtual tags, reports, tag backups and tag restoration.

Omnis should eventually have:

### 🔴 Tag Tools

- Copy tag
- Swap tags
- Move tag
- Merge tags
- Split tags
- Search & replace
- Regex replacement
- Multi-step replacements
- Case conversion
- Trim whitespace
- Normalize punctuation
- Normalize artist names
- Normalize genres
- Normalize featuring artists
- Bulk tag editor
- Tag templates
- Custom fields
- Virtual tags
- Calculated tags
- Tag history
- Undo tag changes

### 🔴 Tag backup

Before bulk changes:

```text
Backup created:
2026-08-14 18:44

Tracks: 4,382
Fields changed: 21,902
```

Then:

**Restore previous metadata**

This could become one of Omnis' killer features.

---

## 6. Smart playlists need to be much more powerful

Your current SmartPlaylistPlugin now has a real ALL/ANY/NONE multi-condition rule engine over title/artist/album/genre/mood/year/rating (item 42, closed this session), with `equals`/`contains` operators on string fields. QueuePresetPlugin separately covers BPM/genre presets plus the "Forgotten Favorites"/"Rediscover" history-based recommendations.

MusicBee-style smart playlists should support additionally:

### 🔴 Rules

AND/OR/NOT (Omnis currently has ALL/ANY/NONE as top-level match types, not nested groups):

```text
Genre = Rock
AND
Rating >= 4
AND
Play Count > 10
AND
Last Played > 30 days ago
```

Or (nested groups — not yet supported):

```text
(
  Genre = Rock
  OR Genre = Metal
)
AND
Year >= 2000
AND
Rating >= 4
```

### Conditions not yet in `RuleField`

- play count
- skip count
- BPM
- key
- duration
- bitrate
- sample rate
- codec
- file size
- path
- folder
- file type
- energy
- loudness
- replay gain
- favorite
- lyrics available
- artwork available
- custom tags

### And:

- limit number of tracks
- limit duration
- weighted random
- sort order
- refresh interval
- lock playlist

---

## 7. Statistics are a major missing system

MusicBee is very strong at library information.

Omnis needs a dedicated:

# Statistics

### Library

- Total tracks
- Total albums
- Total artists
- Total genres
- Total duration
- Total storage
- Average bitrate
- Average track length
- Lossless percentage
- Hi-res percentage

### Listening

- Most played
- Least played
- Never played
- Recently played
- Recently added
- Most skipped
- Most replayed
- Most favorited
- Most rated
- Favorite artists
- Favorite albums
- Favorite genres

### Time

- Today
- Yesterday
- This week
- This month
- This year
- All time

### Visualizations

- listening hours
- listening by genre
- listening by artist
- listening by decade
- listening by year
- listening by hour
- listening by day
- listening streaks

---

## 8. Playback/DSP is a major gap

MusicBee explicitly supports:

- 10/15-band EQ
- DSP effects
- WASAPI
- ASIO
- gapless
- stereo → 5.1 upmixing
- resampling
- logarithmic volume
- normalization
- Winamp plugins

Omnis currently has EQ, ReplayGain, gapless, crossfade, pitch, speed and skip silence (item 18's own tracker entry: "a flat named-multiplier gain-composition system, not the spec's staged, independently-replaceable chain").

### 🔴 Add an Audio DSP Pipeline

```text
Source
 ↓
Decoder
 ↓
ReplayGain
 ↓
Preamp
 ↓
Equalizer
 ↓
Bass Boost
 ↓
Compressor
 ↓
Limiter
 ↓
Stereo Enhancer
 ↓
Crossfeed
 ↓
Virtualizer
 ↓
Resampler
 ↓
Output
```

And make every stage pluggable.

---

## 9. High-end audio output

This is particularly important if Omnis wants to compete with MusicBee/foobar2000.

### 🔴 Windows

- WASAPI Shared
- WASAPI Exclusive
- ASIO
- DirectSound
- Windows Audio
- device selection
- per-device volume
- exclusive-mode settings
- sample-rate selection
- bit-depth selection
- channel configuration

### 🔴 Linux

- PipeWire
- PulseAudio
- ALSA

### 🟠 macOS

- CoreAudio
- exclusive/hog mode where appropriate

### Android

- AudioTrack
- AAudio
- USB DAC
- Bluetooth codecs where available

---

## 10. Format support needs to become first-class

Create a **Format Matrix**.

Support and test:

- MP3, AAC, M4A, FLAC, OGG Vorbis, Opus, WAV, AIFF, ALAC, WMA — already real (item 22's `AudioFormatReader`)
- APE, WV, MPC, TTA, DSF, DFF, MKA, WebM audio, MIDI — still open

### Audio information

Already shown via the "Audio info" dialog (item 22): codec/sampleRateHz/bitDepth/bitrateKbps/channels.

---

## 11. CD functionality is completely missing

This is a big MusicBee feature gap.

### 🔴 CD Ripper

- detect CD
- track listing
- MusicBrainz lookup
- Discogs lookup
- album art
- secure ripping
- drive offset
- error detection
- AccurateRip-style verification
- FLAC/ALAC/WAV/MP3/AAC output
- custom encoder profiles
- automatic tagging
- automatic folder organization
- multi-disc detection

### 🟠 CD Burner

- audio CD
- data CD
- playlist → CD
- gap handling
- normalization
- CD-Text

---

## 12. Audio conversion

MusicBee can convert media for devices, and device sync can convert formats on the fly.

Omnis needs a dedicated:

# Converter Plugin

Presets:

```text
FLAC → MP3 320
FLAC → MP3 V0
FLAC → AAC 256
FLAC → Opus 160
WAV → FLAC
ALAC → FLAC
```

Include:

- batch conversion
- folder conversion
- playlist conversion
- metadata preservation
- artwork preservation
- ReplayGain preservation
- custom FFmpeg profiles
- queue/progress/cancellation
- parallel conversion
- filename templates

---

## 13. Device synchronization is a gigantic opportunity

MusicBee supports syncing music, playlists, podcasts and audiobooks, including two-way syncing and automatic conversion.

### 🔴 Device Manager

Detect Android/iPhone/USB storage/SD cards/portable players/network devices, then sync with format conversion.

---

## 14. Podcasts

MusicBee supports podcasts. Omnis currently has none.

### 🔴 Podcast plugin

RSS subscriptions, OPML import/export, episode download, playback speed, resume position, chapters, offline mode.

---

## 15. Internet radio

**Already real** (item 41, `RadioPlugin` + custom station entry) — Radio Browser directory search/top-stations, custom stream URL entry, favorites. Remaining gaps: single fixed API mirror (not full DNS-round-robin discovery), no station recording, no automatic genre classification.

---

## 16. Audiobooks

MusicBee supports audiobook synchronization; Omnis has no comparable subsystem.

### 🔴 Audiobook mode

author/narrator/series/chapter model, resume position, bookmarks, sleep timer, playback speed, M4B + embedded chapters.

---

## 17. CUE sheets

```text
album.flac
album.cue
```

as multiple logical tracks without physically splitting the file. Embedded + external cuesheets, UTF-8/legacy encodings, CD offsets/gap handling.

---

## 18. Network music

### 🟠 NAS/network libraries

SMB, WebDAV, SFTP, HTTP/HTTPS, NAS discovery, offline caching, reconnect.

---

## 19. UPnP/DLNA/Chromecast

Omnis already has a DLNA/UPnP **client** (item 35). Still missing: UPnP server/renderer roles, Chromecast, AirPlay, Sonos, Home Assistant integration, "Play To → device" from within Omnis.

---

## 20. Remote control/API

This is an especially interesting opportunity — build this **into the architecture from the beginning**.

### 🔴 Omnis Remote API

REST (`/play`, `/pause`, `/queue`, `/library/search`, `/now-playing`, ...) + WebSocket events (`trackChanged`, `playStateChanged`, `queueChanged`, ...). Would let third parties build phone/desktop/web remotes, Stream Deck plugins, Home Assistant integration, Discord/OBS integration, smart speaker control. Fits Omnis's plugin architecture well.

---

## 21. Party Mode

```text
OMNIS PARTY
Scan QR Code
Josh's Party
🎵 Now Playing — Artist - Song
👍 23  ❤️ 12  🔥 8
Guests can: vote / add songs / skip / request
```

Host controls everything.

---

## 22. Search needs to be much more powerful

Omnis already has real qualifier-based search (`lib/core/library_search.dart`, item 10) — `artist:`/`album:`/`genre:`/`title:`/`mood:`/`year:` (exact or range), AND-combined.

# Universal Search (still open)

Extend search to also cover playlists, folders, lyrics, plugins, settings, commands, radio, podcasts, streaming services — a single command-palette-style entry point (see items 10/45/48's existing command-palette gap).

Additional operators worth adding: `rating:>=4`, `bpm:120..140`, `format:flac`, `favorite:true`.

---

## 23. Queue management needs expansion

AudioEngine is architecturally strong here (playNext/addTrack/setQueue, item 2's queue history/snapshots already real). Still open:

- queue groups, save/load queue as a distinct concept from playlists
- drag/drop reordering, remove duplicates, clear played
- move to top, shuffle remaining
- queue-to-playlist / playlist-to-queue conversion
- queue rules: "don't repeat artist", "don't repeat album", energy/BPM progression

---

## 24. ReplayGain should become much deeper

Already real: track/album gain modes (item 19, this session), preamp.

### 🔴 Loudness Analysis (still open)

Track/album LUFS, true peak, dynamic range, clipping detection, loudness range.

---

## 25. Advanced audio analysis

`AudioAnalysisPlugin` already gets real BPM/key/mood/genre via a self-hosted Essentia service (item 23). Still open: danceability, valence, arousal, acousticness, instrumentalness, speechiness, spectral centroid/rolloff, beat grid, onset detection, waveform, fingerprint — then feed all of it into smart playlists/DJ mode/radio/recommendations/visualizer/statistics.

---

## 26. DJ functionality

This is a major opportunity to surpass MusicBee.

### 🟠 DJ Mode

BPM/key/beat-grid/waveform, cue points, hot cues, loops, A/B loops, crossfade, automix, beat/key/energy matching, transition suggestions.

---

## 27. A/B loop needs more power

Real A-B repeat already exists (`AbRepeatController`). Still open: saved/named loops, multiple loops per track, loop presets, MIDI controller support.

---

## 28. Hotkeys

### 🔴 Global shortcuts (partial — item 48 mentions "Enable keyboard shortcuts" already exists)

Verify coverage: play/pause/next/prev/seek/volume/mute/favorite/rating/queue/search/lyrics/EQ/visualizer/window toggle.

---

## 29. Hardware/media-key integration

Already real: Windows SMTC + `audio_service` notification/lock-screen controls (item 7), a Home-screen widget. Still open: comprehensive cross-platform parity (headset controls, Bluetooth buttons, Android Auto, CarPlay).

---

## 30. Bluetooth intelligence

`BluetoothPlaybackPlugin` already exists. Still open: per-device EQ/volume/position profiles, auto-resume/pause/play, car detection vs. headphone detection.

---

## 31. Car mode

Already real: `DrivingModePlugin` (GPS-speed auto-activation) + `CarModeLayout` (item 46). Still open: voice control, steering wheel buttons, Android Auto/CarPlay integration, driving-specific playlists.

---

## 32. Artwork management

Real embedded-artwork extraction/display already exists (item 12). Still open: an artwork-provider framework (Cover Art Archive/Fanart.tv lookup), manual/drag-drop override, multiple artwork types (back cover, CD image, booklet), artwork cache/compression tuning.

---

## 33. Album/artist metadata pages

Rich Artist/Album detail pages (biography, similar artists, credits, statistics) — still open.

---

## 34. Credits

Composer/lyricist/producer/engineer/mixer/label/catalog-number/ISRC/cross-service-id fields — still open, `BaseTrack` doesn't model these yet.

---

## 35. Multiple artists need a proper model

Featured-artist separator rules already exist. Still open: a real primary/featured artist model (not a joined display string) and proper "Various Artists" compilation modeling.

---

## 36. Ratings need more than 0–5 stars

`RatingsPlugin` (0-5 stars) is real. Still open: half stars, thumbs up/down as a separate signal, album/artist-level ratings, a distinction between user rating and a calculated one.

---

## 37. Listening history needs to become a database

`PlayHistoryStore`/`ScrobblePlugin` already track play count, last played, position, and per-play records. Still open: skip tracking, completion-rate calculation, source/device/playlist attribution per play.

---

## 38. "Forgotten music" system

**Partially real** — `QueuePresetPlugin`'s "Forgotten Favorites" preset (item 39) already does exactly this for most-played-but-not-recent tracks. Still open: a dedicated "you haven't played these in N months" browsing view (not just a play-queue action), and the same idea applied more broadly (any owned track, not just former favorites).

---

## 39. Discovery engine

Item 39's own tracker entry lists what's real (Forgotten Favorites, Rediscover, Similar Track — item 39/40, this session) vs. still-missing (Similar Artist, Daily/Weekly Mix, Discovery, Deep Cuts, New Releases, Energy Flow). A unified "Play Something" entry point surfacing all these as named buttons is still open.

---

## 40. MusicBee's plugin ecosystem itself is a feature gap

MusicBee's ecosystem contains plugins for additional tagging, VST effects, UPnP, remote control, visualizers, A-B loop, scheduling, playlist history, automixing, genre tools, loudness analysis, Discogs tagging, BPM tapping, quick tagging, party functionality, system-volume linking.

Omnis's architecture is better positioned to absorb these capabilities, but the actual ecosystem is still comparatively small (~2 dozen plugins as of this document, several self-flagged unverified against real devices/accounts — Spotify/YouTube).

The goal should not be "build more plugins" — it should be **"build the capability contracts that make hundreds of plugins possible."**

---

## 41. Plugin APIs worth adding

`ServiceRegistry`/`EventBus`/`PluginContext`/`PluginStorage`/sandboxing/runtime plugin loading already exist. Capability interfaces that don't yet exist: `IAudioDecoder`, `IAudioOutput`, `IAudioDSP`, `ILibraryScanner`, `IPlaylistProvider`, `IRecommendationProvider`, `IStreamingProvider`, `IPodcastProvider`, `IAudiobookProvider`, `IDeviceProvider`, `IDeviceSyncProvider`, `ICDReader`, `ICDBurner`, `IAudioConverter`, `INetworkRenderer`, `IRemoteControlProvider`, `ISearchProvider`, `ITagProvider`, `IFileOrganizer`, `IBackupProvider`, `IStatisticsProvider`, `IVoiceControlProvider`, `IAutomationProvider`.

(`IArtworkProvider` mentioned separately in item 12's own gap; `ILyricsProvider`/`IPlayHistoryProvider`/`IQueueBuilder`/`IMetadataProvider`/`IAudioAnalysisProvider`/`IFileTagWriter`/`IVisualizerProvider`/`IArtistImageProvider`/`IDeviceConnectivityProvider`/`IAIProvider`/`IRatingsProvider` already exist in `packages/omnis_plugin_api/lib/service_interfaces.dart`.)

---

## 42. Automation is almost completely unexplored

Item 50's own tracker entry: two real single-purpose triggers exist (GPS-speed → Car Mode, Bluetooth-connect → quick-play/EQ prompt) but no general rules engine, no time-based triggers.

### Automation plugin (still open)

```text
When: Track starts
If: Genre = Rock
Then: EQ = Rock, Volume = 80%, Visualizer = Spectrum
```

---

## 43. Scheduling

start/stop playback at a time, wake playback, scheduled playlist/radio/podcast, recurring/day-of-week rules — still open (distinct from the existing sleep timer, which only counts down).

---

## 44. Backup/restore

Real already (item 4's `backup_service.dart` + Settings → Backup page): library/playlists/play-history/recovery-journal, validated before overwrite. Still open: exporting to CSV/OPML/MusicBrainz-compatible formats, plugin-settings backup.

---

## 45. Import from other music players

Real already: Spotify playlist import (item 36), YouTube Music playlist import (item 37). Still open: MusicBee, foobar2000, iTunes/Apple Music, Windows Media Player, MediaMonkey, Winamp, VLC, AIMP, Plex, Jellyfin importers, preserving ratings/play-counts/history where the source format has them.

---

## 46. Export to other players

M3U/M3U8/PLS/XSPF export real already (item 13, this session). Still open: CSV/JSON export, MusicBee/Plex/Jellyfin-native export.

---

## 47. Portable installation

Installer/portable/store editions — still open, no packaging work done yet.

---

## 48. Multi-user profiles

```text
Omnis
 ├── Josh
 ├── Guest
 └── Family
```

Each with own playlists/ratings/history/favorites/settings/EQ. Still open — no user-profile concept exists at all today.

---

## 49. The feature I would NOT copy from MusicBee

Don't copy MusicBee's architecture. This is where Omnis has a major advantage — the kernel is deliberately small, with capability interfaces in `plugin_api`, generic service discovery through `ServiceRegistry`, typed events through `EventBus`, per-plugin storage, sandboxing and runtime plugin loading. **Keep that.**

```text
MusicBee feature → Omnis capability → Plugin → ServiceRegistry → UI
```

---

## 50. Recommended priority order

If the goal is "make Omnis the ultimate all-in-one music player":

### 🔴 Tier 0 — Core music-manager foundation
Library database v2, watch folders, library scanner improvements, missing-file detection, library health (partially real — item 17), advanced search (real qualifiers exist — item 10; universal/command-palette search still open), smart playlist engine (real — item 42), playlist system v2 (real — item 13), statistics, history database (real — `PlayHistoryStore`).

### 🔴 Tier 1 — MusicBee-killer functionality
Auto Tagger, File Organizer, Advanced Tag Tools, tag backup/restore, Artwork Manager, Audio Converter, format analyzer (real — item 22), CUE sheet support, CD ripping, audiobook system.

### 🔴 Tier 2 — Audiophile
DSP pipeline, WASAPI, ASIO, exclusive output, advanced ReplayGain (real — item 19), EBU R128, resampling, limiter, compressor, stereo tools, VST support.

### 🔴 Tier 3 — Ecosystem
Podcast system, Internet Radio (real — item 41), UPnP/DLNA (client real — item 35), Chromecast, AirPlay, device synchronization, NAS/SMB, remote API, mobile remote, Home Assistant, Party Mode.

### 🟠 Tier 4 — Intelligence
Recommendations (partial — items 39/40), DJ mode, automix, forgotten music (partial — QueuePresetPlugin), mood engine (partial), discovery engine, listening predictions, automatic queue, automatic tagging, automatic organization.

### 🟡 Tier 5 — Power-user ecosystem
Automation (partial — item 50), scripting, command palette (open — items 10/45/48), global hotkeys (partial), MIDI, Stream Deck, plugin marketplace, plugin ratings/reviews, plugin dependencies (real — item 26), plugin update manager (real — item 29), plugin permissions (real), plugin rollback.

---

### Bottom line

**Omnis isn't missing a few features. It's missing several entire subsystems.**

The most serious gaps as of this comparison: Library management → Auto-tagging → File organization → Statistics → Advanced DSP → Conversion → Device sync → Podcasts → Audiobooks → CD tools → Network playback (server/Chromecast side) → Remote API.

But the architecture already built is unusually well suited to fixing this. The current `ServiceRegistry`, `EventBus`, plugin storage, capability interfaces and sandboxed runtime are exactly the pieces needed before attempting this scale of feature expansion — grow the plugin ecosystem, not the Core.
