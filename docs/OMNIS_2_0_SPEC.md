 to being # Omnis 2.0 — Master Product Specification

> **Status:** Canonical reference for the Omnis 2.0 direction.
> This document is the product vision and requirements contract. It is
> deliberately aspirational in places — not everything here is built yet.
> The [Architecture](ARCHITECTURE.md) document describes what exists
> today; this document describes where Omnis is going and why.
>
> **The Omnis 2.0 build always uses these three references together:**
>
> 1. This document — [OMNIS_2_0_SPEC.md](OMNIS_2_0_SPEC.md), the product
>    specification (everything the Core must do).
> 2. [OMNIS_2_0_UI_SPEC.md](OMNIS_2_0_UI_SPEC.md), the UI/UX Master
>    Design Specification (how the interface must look, feel, and be
>    customized).
> 3. [OMNIS_2_0_PLUGINS.md](OMNIS_2_0_PLUGINS.md), the Plugin
>    Architecture & Developer Guide (the plugin platform, marketplace,
>    and plugin hub).
>
> Read all three before building any Omnis 2.0 feature.

## 1. Product philosophy

Omnis should be designed around these non-negotiable principles:

### 1. Playback must always work

If every plugin is disabled, Omnis should still be an excellent music player.

Core must be able to:

* Discover local music.
* Read metadata.
* Display artwork.
* Build a queue.
* Play audio.
* Pause.
* Resume.
* Seek.
* Skip.
* Previous.
* Shuffle.
* Repeat.
* Handle gapless playback.
* Recover from corrupt/unplayable files.
* Continue after a bad track.
* Preserve queue state.
* Restore playback state after restart.
* Integrate with OS media controls.
* Work without Internet.
* Work without accounts.
* Work without API keys.
* Work without optional plugins.

**Nothing optional should be capable of taking down playback.**

The current architecture already explicitly attempts to make plugin
failures non-fatal and skip unplayable files. Keep this philosophy, but
make it much more comprehensive.

---

# 2. What belongs in Core

The Core should be formalized into several immutable subsystems.

## A. Playback Kernel

This is the most protected part of the application.

Core owns:

* Audio decoding orchestration
* Audio output
* Queue state
* Current track
* Playback state
* Position
* Duration
* Seeking
* Play/pause/stop
* Next/previous
* Queue insertion/removal
* Queue persistence
* Gapless playback
* Basic crossfade infrastructure
* Repeat state
* Shuffle infrastructure
* Volume
* Playback speed
* Pitch
* Skip silence
* Error recovery
* Playback interruption recovery
* Audio focus
* Headphone/Bluetooth disconnect behavior
* OS media controls
* Lock screen controls
* Notification controls
* Media session
* External media keys
* Resume after application restart

The existing `AudioEngine` already provides a large amount of this
functionality, including streams and transport controls exposed through
`PluginContext`.

### New requirement: playback watchdog

Add a permanent internal watchdog.

It should detect:

* Player stuck loading
* Position stopped advancing
* Decoder exceptions
* Queue advancement failure
* Audio session interruption
* Output device disappearance
* Native player exceptions
* Track timeout
* Invalid duration
* Impossible position
* Queue corruption
* Repeated failures

Recovery should happen automatically.

Example:

```text
Playback failure
       ↓
Identify failure type
       ↓
Attempt local recovery
       ↓
Reload current source
       ↓
Reinitialize decoder
       ↓
Retry once
       ↓
If still failing → mark track failed
       ↓
Advance queue
       ↓
Record diagnostic
       ↓
Continue playback
```

The user should almost never see an error unless **their action actually
requires their attention.**

---

# 3. Media model needs to become significantly richer

The current `BaseTrack` is intentionally simple.

For the next generation, make the internal model capable of representing:

### Track identity

* Internal Omnis ID
* File ID
* URI/path
* Content hash
* File fingerprint
* Source ID
* Provider ID
* Provider track ID
* MusicBrainz recording ID
* MusicBrainz release ID
* ISRC
* Spotify ID
* YouTube ID
* Discogs ID
* ReplayGain identifiers
* Original creation/import timestamp

### Audio information

* Codec
* Container
* Bit depth
* Sample rate
* Channels
* Channel layout
* Bitrate
* Average bitrate
* Lossless/lossy
* Duration
* Encoder
* Encoder settings
* ReplayGain track gain
* ReplayGain album gain
* Peak
* Loudness
* Dynamic range
* True peak
* BWF information where available

### Music metadata

* Title
* Sort title
* Artist
* Sort artist
* Album
* Album artist
* Sort album
* Composer
* Conductor
* Lyricist
* Genre
* Mood
* Grouping
* Comment
* Copyright
* Publisher
* Label
* Year
* Original release year
* Track number
* Disc number
* Total tracks
* Total discs
* Compilation
* Movement
* Movement number
* Work
* Edition
* Release type
* Release country
* Release date

### Relationship metadata

A track should be able to reference:

* Artists
* Album artists
* Featured artists
* Composers
* Albums
* Releases
* Labels
* Genres
* Playlists
* Collections
* Sources

This matters enormously for classical music, compilations, soundtracks
and modern music.

---

# 4. Library needs to be a real database, not just a scanner

The current architecture already has `LibraryRepository`, `LibraryStore`,
`MediaScanner`, playlist storage, and history storage.

The next evolution should use a proper indexed database architecture.

The library should support:

### Sources

* Internal storage
* External storage
* SD cards
* USB drives
* Network shares
* SMB
* WebDAV
* FTP
* NAS
* UPnP/DLNA
* HTTP libraries
* Self-hosted servers
* Cloud storage
* Provider libraries
* Removable drives

### Multiple libraries

Allow:

```text
My Music
 ├── Local Music
 ├── NAS Music
 ├── USB Music
 └── Streaming Sources

Audiobooks
 ├── Local
 └── Server

Kids
 └── Local
```

Navidrome demonstrates the usefulness of multiple libraries and per-user
access controls, while OpenSubsonic gives a strong example of
interoperability through a standardized API.

---

# 5. Scanning needs to be industrial-grade

Scanning should support:

* Initial scan
* Incremental scan
* Filesystem watchers
* Scheduled scanning
* Manual scan
* Rescan changed files only
* Detect renamed files
* Detect moved files
* Detect deleted files
* Detect duplicates
* Detect corrupt files
* Detect metadata changes
* Detect artwork changes
* Detect external tag changes
* Hash verification
* Library repair
* Database rebuild
* Missing-file management

### Critical feature

**Never identify a song exclusively by its path.**

Paths change.

Use a hierarchy:

```text
Omnis ID
↓
Content fingerprint
↓
File hash
↓
Provider IDs
↓
Metadata identity
↓
Path
```

That lets users move:

```text
D:\Music
```

to:

```text
E:\Music
```

without losing:

* Play history
* Favorites
* Ratings
* Playlists
* Lyrics
* Artwork
* Statistics
* User tags

---

# 6. Search should be one of Omnis' killer features

Build a universal search engine.

Search across:

* Songs
* Albums
* Artists
* Genres
* Playlists
* Lyrics
* File names
* Tags
* Comments
* Labels
* Composers
* Moods
* Ratings
* Play history
* Metadata providers
* Online services

Support:

```text
queen
```

```text
artist:queen
```

```text
album:greatest hits
```

```text
genre:rock
```

```text
year:1990..1999
```

```text
rating:>=4
```

```text
bpm:120..140
```

```text
format:flac
```

```text
bitrate:>=1000
```

```text
lyrics:"love"
```

```text
missing:artwork
```

```text
duplicate:true
```

And natural-language queries eventually:

> "Show me 90s rock songs I haven't played in six months."

---

# 7. Queue system should become one of Omnis' defining features

Do not treat the queue as merely "the list of songs."

Build a proper queue engine.

Support:

* Manual queue
* Play next
* Add to queue
* Play after current
* Queue reordering
* Queue persistence
* Queue history
* Queue snapshots
* Multiple queue sources
* Queue rules
* Queue exclusions
* Smart queue
* Auto continuation
* Mood continuation
* Artist continuation
* Album continuation
* Genre continuation
* Similar-track continuation

### Advanced shuffle

Spotify's current shuffle system demonstrates why basic randomization
isn't enough: it offers standard shuffle, reduced-repeat shuffle, and
Smart Shuffle.

Omnis should go further:

```text
Random
Balanced
Fewer Repeats
Never Repeat Until Complete
Artist Balanced
Album Balanced
Genre Balanced
Discovery
Familiarity
Mood
Energy
Smart
Custom
```

And expose the algorithm settings.

---

# 8. Playlists

Core playlist infrastructure should support:

* Static playlists
* Smart playlists
* Rule-based playlists
* Nested playlists
* Playlist folders
* Playlist groups
* Collaborative playlists
* Imported playlists
* Exported playlists
* M3U
* M3U8
* XSPF
* PLS
* Provider playlists
* Server playlists

Smart playlist rules should support:

```text
ALL / ANY / NONE
```

with conditions:

* Artist
* Album
* Genre
* Mood
* Year
* BPM
* Key
* Rating
* Play count
* Skip count
* Last played
* Date added
* File type
* Bitrate
* Duration
* ReplayGain
* Favorite
* Lyrics
* Artwork
* Location
* Provider
* Composer
* Label
* Energy
* Loudness

---

# 9. Ratings and listening history

Built-in data model:

* Favorite
* Rating 0–5
* Play count
* Skip count
* Completion percentage
* Last played
* First played
* Last skipped
* Last queued
* Last added
* Play duration
* Total listening time

And importantly:

**Do not force Last.fm/ListenBrainz to be the history database.**

Those should consume Omnis history.

---

# 10. Audio quality needs to compete with audiophile players

foobar2000 currently supports extensive DSP, ReplayGain, gapless playback,
advanced tagging, network audio and component extensions. MusicBee
similarly emphasizes EQ/DSP, WASAPI/ASIO and gapless playback.

Omnis needs a proper audio pipeline.

### DSP architecture

Create a DSP chain:

```text
Source
 ↓
Decoder
 ↓
Format conversion
 ↓
ReplayGain
 ↓
Preamp
 ↓
EQ
 ↓
Tone
 ↓
Compressor
 ↓
Limiter
 ↓
Crossfeed
 ↓
Convolver
 ↓
Spatializer
 ↓
Visualizer tap
 ↓
Output
```

Every stage should be independently replaceable.

---

# 11. DSP plugins

Potential plugins:

### Equalizer

* 3 band
* 5 band
* 10 band
* 15 band
* 31 band
* Parametric EQ
* Graphic EQ
* Per-device profiles
* Per-headphone profiles
* Per-artist profiles
* Per-album profiles

### Other DSP

* Bass boost
* Treble boost
* Loudness
* Compressor
* Limiter
* Crossfeed
* Stereo widening
* Mono
* Balance
* Channel mixer
* Resampler
* Spatial audio
* Convolver
* Room correction
* Headphone correction
* Speaker correction
* Dynamic range processing
* Vinyl simulation
* Tape simulation
* Tube simulation

### Advanced

Support VST/VST3/AU where platform allows.

---

# 12. Bit-perfect mode

This should eventually be a first-class capability.

Show:

```text
SOURCE
FLAC
24-bit / 96 kHz
     ↓
DSP
OFF
     ↓
RESAMPLING
OFF
     ↓
OUTPUT
USB DAC
24-bit / 96 kHz
```

Or:

```text
SOURCE 44.1 kHz
OUTPUT 48 kHz
⚠ OS RESAMPLING
```

The user should understand exactly what happens to their audio.

---

# 13. Metadata ecosystem

The current `MetadataEnrichmentPlugin` is a good beginning.

Expand this into a provider framework:

```text
IMetadataProvider
IArtworkProvider
IArtistProvider
IAlbumProvider
ILyricsProvider
IAudioAnalysisProvider
IReleaseProvider
IRecommendationProvider
```

Providers could include:

* MusicBrainz
* Cover Art Archive
* Discogs
* Last.fm
* Deezer
* Spotify
* YouTube
* Genius
* LRCLIB
* Fanart.tv
* AcousticBrainz-compatible services
* Local AI
* Self-hosted metadata services

But **users should never have to understand APIs.**

---

# 14. The "No API Keys" principle

This is one of the most important requirements.

The normal user experience should be:

> "Enable Spotify integration."

Not:

> "Create a Spotify developer application, copy the client ID, create a
> secret, configure redirect URI..."

The Omnis architecture should contain a **Managed Provider Gateway**.

For services that legally and technically permit this:

```text
Omnis
 ↓
Provider Manager
 ↓
Built-in OAuth configuration
 ↓
Secure credential storage
 ↓
Provider
```

The user only sees:

**Connect Spotify**

**Connect YouTube**

**Connect Last.fm**

**Connect ListenBrainz**

etc.

For providers that legally require the user to supply their own
credentials, Omnis should still:

1. Explain why.
2. Provide a guided setup.
3. Detect configuration automatically.
4. Validate credentials.
5. Test connectivity.
6. Store credentials securely.
7. Never expose raw secrets.
8. Provide a "Fix connection" workflow.

---

# 15. Streaming/provider architecture

Create a generic provider interface.

```text
IMusicProvider
```

Capabilities:

* Search
* Browse
* Artist
* Album
* Track
* Playlist
* Radio
* Recommendations
* Lyrics
* Artwork
* Playback
* Download
* Offline
* Authentication
* User library
* Favorites

Then providers can advertise capabilities.

Example:

```text
Spotify
✓ Search
✓ Playlists
✓ Library
✓ Recommendations
✓ Remote playback
✗ Local file access
```

Another:

```text
Local
✓ Search
✓ Playback
✓ Download
✓ Metadata
✓ Offline
✗ Cloud recommendations
```

The UI shouldn't care which provider supplied the data.

---

# 16. Self-hosted ecosystem

This is a major opportunity.

Add plugins/connectors for:

* Navidrome
* OpenSubsonic
* Jellyfin
* Plex
* Emby
* DLNA
* UPnP
* SMB
* WebDAV
* HTTP
* FTP

Navidrome's ecosystem shows the enormous value of a standardized music
API: its OpenSubsonic compatibility gives it access to dozens of clients
across desktop, mobile, web and automotive environments.

Omnis should therefore support **OpenSubsonic as a first-class plugin
ecosystem**, not just one server.

---

# 17. Cloud and offline system

Users should be able to say:

> Download this album.

And Omnis handles:

* Download
* Metadata
* Artwork
* Lyrics
* File verification
* Storage
* Offline database
* Cache management
* Resume
* Re-download
* Cleanup

Add:

### Smart caching

```text
Recently played
Frequently played
Favorites
Current playlist
Next N tracks
Albums being listened to
```

---

# 18. Lyrics needs to become a complete subsystem

Current Omnis already supports manual lyrics, LRCLIB lookup, synchronized
lyrics and embedding.

Expand it to:

* Embedded lyrics
* LRC
* Unsynchronized lyrics
* Synchronized lyrics
* Multiple lyric versions
* Translation
* Romanization
* Line synchronization
* Word synchronization
* Karaoke mode
* Lyrics editor
* Timing editor
* Auto timing
* Lyrics search
* Provider priority
* Local lyrics files
* Lyrics caching
* Offline lyrics
* Embed/remove lyrics
* Backup lyrics

---

# 19. Artwork

Artwork deserves its own plugin capability.

Support:

* Embedded artwork
* Folder.jpg
* Cover.jpg
* Front.jpg
* Artist.jpg
* Album artwork
* Disc artwork
* Back cover
* Booklet
* Multiple artwork
* Animated artwork where supported
* High-resolution artwork
* Artwork provider lookup
* Manual artwork
* Drag/drop artwork
* Automatic artwork selection
* Artwork caching
* Per-device artwork sizing

---

# 20. Tag editor

The existing `TagEditorPlugin` is already one of the stronger pieces of
the ecosystem.

Keep expanding:

* ID3v1
* ID3v2
* Vorbis Comments
* FLAC
* MP4/M4A
* OGG
* Opus
* WAV metadata
* AIFF metadata
* Custom fields
* Batch editing
* Rename files
* Move files
* Folder restructuring
* Filename templates
* Metadata templates
* Preview before writing
* Undo
* Backup
* Restore
* Tag validation
* Duplicate detection
* Missing tag detection

### Add "Music Library Cleanup"

One button:

**Analyze Library**

Then:

```text
1,421 missing artwork
832 inconsistent artists
321 duplicate tracks
198 albums missing year
94 malformed track numbers
73 inconsistent genres
31 duplicate albums
12 corrupt files
```

Then provide guided cleanup.

---

# 21. AI subsystem

This should be a major optional ecosystem.

Create:

```text
IAIProvider
```

It can be:

* Local LLM
* Cloud LLM
* Embedded model
* User-provided model
* No AI

AI features:

### Natural language search

> "Find upbeat songs from the 2000s."

### Playlist creation

> "Make me a two-hour workout playlist."

### Metadata cleanup

> "Fix the artist names in this album."

### Tagging

> "Identify the genre and mood."

### Recommendations

> "Give me something like this but heavier."

### Library assistant

> "Which albums have never been played?"

### Voice control

> "Play my favorite Metallica songs."

### Music discovery

> "Find artists similar to Tool."

The AI system should never be required for normal functionality.

---

# 22. Recommendation engine

Create a provider-neutral recommendation framework.

Sources:

* Listening history
* Ratings
* Favorites
* Skips
* Genres
* BPM
* Key
* Mood
* Acoustic features
* Audio fingerprints
* Similar artists
* Similar tracks
* User playlists
* Time of day
* Device
* Current session

Algorithms:

```text
Similar Track
Similar Artist
Album Radio
Artist Radio
Genre Radio
Mood Radio
Discovery
Deep Cuts
Forgotten Favorites
Rediscover
New Releases
Daily Mix
Weekly Mix
Energy Flow
Workout
Sleep
Focus
Driving
```

Plexamp's Sonic Analysis demonstrates the value of analyzing the actual
audio rather than relying exclusively on tags.

---

# 23. Visualizer system

The current `VisualizerPlugin` already exists.

Expand:

* Spectrum
* Waveform
* Oscilloscope
* VU meter
* Spectrogram
* MilkDrop-compatible visualizations
* Shader visualizations
* Album-art reactive
* Particle visualizations
* Custom visualizer plugins
* Audio-reactive backgrounds

And separate:

```text
IAudioAnalysisProvider
```

from:

```text
IVisualizerProvider
```

The current architecture already recognizes this distinction, which is
the correct direction.

---

# 24. Car system

Driving Mode should become much more extensive.

Support:

* Android Auto
* Apple CarPlay
* Large controls
* Minimal text
* Voice
* Steering-wheel controls
* Bluetooth controls
* Automatic driving mode
* Speed detection
* Orientation changes
* High contrast
* Large artwork
* Queue shortcuts
* Favorites
* Recently played
* Downloaded music
* Safety lockouts

---

# 25. Bluetooth / hardware

Create a generic hardware capability layer.

Support:

* Bluetooth
* USB DAC
* USB audio
* HDMI audio
* Cast
* DLNA
* UPnP
* AirPlay where licensing/platform allows
* Network speakers
* Android Auto
* CarPlay
* Desktop output devices

Device-specific settings:

```text
Headphones
EQ preset
Volume
ReplayGain
DSP
Crossfeed

Car
EQ
Volume
Driving mode

USB DAC
Sample rate
Bit depth
Bit-perfect
```

---

# 26. Ripping and conversion

This is an area current players such as foobar2000 expose through their
advanced ecosystem.

Optional plugins:

* CD ripping
* Audio conversion
* FLAC conversion
* MP3 conversion
* AAC
* Opus
* WAV
* ReplayGain scanning
* Loudness analysis
* Batch conversion
* Transcoding
* Format migration

---

# 27. Internet radio

Plugin:

### Radio

Support:

* Radio Browser
* Custom streams
* HLS
* Icecast
* Shoutcast
* M3U streams
* Favorites
* Recording where legally permitted
* Station metadata
* Artwork
* History

---

# 28. Podcast / audiobook support

Even if Omnis is music-first, the ecosystem should be able to add:

### Podcast plugin

* RSS
* Episodes
* Downloads
* Subscriptions
* Playback position
* Speed
* Skip silence
* Chapters

### Audiobook plugin

* Chapters
* Resume position
* Bookmarks
* Sleep timer
* Narrator
* Series
* Disc/chapter organization
* Variable speed

---

# 29. Accessibility must be a first-class requirement

"Everyone can use it" means much more than large buttons.

Support:

* Screen readers
* Semantic labels
* Keyboard navigation
* Focus indicators
* High contrast
* Reduced motion
* Reduced transparency
* Large text
* Dynamic font sizes
* Colorblind-safe states
* Voice control
* Full keyboard shortcuts
* Switch/accessibility input
* Touch target sizing
* RTL
* Localization

Every UI component should have:

```text
label
hint
role
state
keyboard action
accessibility action
```

---

# 30. UI architecture

The UI should be **adaptive**, not simply responsive.

Desktop:

```text
┌──────────────┬──────────────────────────────┐
│ Navigation   │ Content                      │
│              │                              │
│ Home         │                              │
│ Library      │                              │
│ Playlists    │                              │
│ Downloads    │                              │
│ Servers      │                              │
│ Plugins      │                              │
│ Settings     │                              │
├──────────────┴──────────────────────────────┤
│ Mini Player / Queue                         │
└─────────────────────────────────────────────┘
```

Mobile:

```text
Content
──────────────
Mini Player
──────────────
Navigation
```

Tablet:

Adaptive split view.

Car:

Completely different interaction model.

TV:

10-foot interface.

---

# 31. Now Playing

Now Playing should be completely modular.

The existing layout system is a good foundation.

But expose layout components:

* Artwork
* Title
* Artist
* Album
* Progress
* Waveform
* Lyrics
* Queue
* Visualizer
* Controls
* Volume
* Speed
* Pitch
* EQ
* Rating
* Favorite
* Share
* Metadata
* Audio information

User should be able to create:

### Minimal

```text
Artwork
Title
Artist
Progress
Play/Pause
```

### Audiophile

```text
Artwork
Track
Format
24-bit / 96 kHz
ReplayGain
DSP
Output
Waveform
```

### Karaoke

```text
Lyrics
Artwork
Progress
```

### Car

```text
Huge artwork
Huge controls
Voice
Queue
```

---

# 32. Settings architecture

This needs a major redesign.

Instead of one giant Settings page, use:

## General

* Startup
* Language
* Theme
* Appearance
* Confirmations
* Notifications
* Privacy

## Playback

* Queue
* Shuffle
* Repeat
* Crossfade
* Gapless
* ReplayGain
* Speed
* Pitch
* Skip silence
* Resume
* Playback recovery

## Audio

* Output
* DSP
* EQ
* Volume
* Exclusive mode
* Bit-perfect
* Resampling
* Buffer
* Sample rate

## Library

* Sources
* Scanning
* Metadata
* Artwork
* Duplicates
* Missing files
* Database

## Appearance

* Theme
* Colors
* Density
* Artwork
* Animations
* Layouts

## Interface

* Navigation
* Tabs
* Gestures
* Keyboard
* Context menus

## Accessibility

* Text
* Contrast
* Motion
* Screen reader
* Input

## Downloads

* Cache
* Storage
* Quality
* Automatic downloads

## Services

* Connected accounts
* Provider management
* Authentication

## Plugins

* Installed
* Available
* Updates
* Permissions
* Health
* Dependencies

## Privacy

* Telemetry
* History
* Scrobbling
* Network
* AI
* Diagnostics

## Advanced

* Database
* Logging
* Debug
* Experimental
* Developer

---

# 33. Settings search

This should be extremely good.

User types:

> crossfade

Results:

```text
Playback
 └── Crossfade duration

Audio
 └── Crossfade DSP behavior

Plugins
 └── Crossfade plugin
```

Search should understand aliases:

```text
"gap between songs"
→ Gapless playback

"louder songs"
→ ReplayGain

"headphones sound"
→ Output / EQ / device profile
```

---

# 34. Plugin architecture needs to become an actual platform

The current plugin API already has the correct beginnings: interfaces,
results, events and capability registration.

Define these broad plugin categories:

### Playback

* Shuffle
* Repeat
* Crossfade
* Gapless enhancements
* Queue engines
* Smart queue

### Audio

* EQ
* DSP
* Resampler
* Limiter
* Compressor
* Spatial audio
* Convolver

### Library

* Scanner
* Metadata
* Artwork
* Tag editor
* Duplicate detector
* Cleanup
* Analyzer

### Discovery

* Recommendations
* Similarity
* Radio
* AI

### Lyrics

* Provider
* Translator
* Synchronizer
* Karaoke

### Services

* Spotify
* YouTube
* Apple Music where technically/legal
* Deezer
* SoundCloud
* Bandcamp
* Tidal where supported
* Qobuz where supported

### Servers

* Navidrome
* Jellyfin
* Plex
* Emby
* Subsonic
* OpenSubsonic
* DLNA

### Hardware

* Bluetooth
* DAC
* AirPlay
* Chromecast
* UPnP

### UI

* Themes
* Layouts
* Visualizers
* Widgets
* Panels
* Mini players

### Automation

* Driving
* Sleep
* Time-based
* Location
* Device
* Bluetooth
* Smart home

### Export

* M3U
* XSPF
* PLS
* CSV
* JSON
* Backup

---

# 35. Plugin permissions need to be much more granular

The current plugin installer already has manifest validation and
permission concepts.

Expand permissions into:

```text
network
network:provider
filesystem:read
filesystem:write
library:read
library:write
playback:control
playback:observe
metadata:read
metadata:write
history:read
history:write
microphone
location
bluetooth
notifications
accounts
credentials
device_output
background_tasks
external_process
```

And show them in plain English.

Example:

> **Lyrics Plus**
>
> ✓ Can read currently playing song
> ✓ Can connect to LRCLIB
> ✓ Can save lyrics
> ✗ Cannot modify your music files
> ✗ Cannot access your location

---

# 36. Plugin health center

This should become a flagship feature.

```text
Plugin Health

✓ Lyrics
✓ ReplayGain
✓ Favorites
⚠ Spotify — authentication expired
⚠ Visualizer — audio capture unavailable
✗ Metadata — provider timeout
```

Every failure gets:

* What happened
* Why
* Whether playback is affected
* Automatic recovery status
* Retry
* Disable
* Reset
* View log

---

# 37. Plugin dependencies

Support:

```text
Lyrics UI
   ↓
Lyrics Provider API
   ↓
LRCLIB Provider
```

If the provider disappears:

> "Lyrics Provider unavailable. Install another provider?"

No crash.

---

# 38. Plugin replacement

This is where Omnis can become exceptional.

User should be able to install:

**Lyrics Provider A**

and later:

**Lyrics Provider B**

without the rest of Omnis knowing.

Same for:

* Metadata
* Artwork
* Recommendations
* Audio analysis
* Scrobbling
* Streaming
* Visualizers

This is exactly the direction the `ServiceRegistry` is already moving
toward.

---

# 39. Plugin marketplace

Eventually:

```text
Omnis Plugins

Categories
Featured
Popular
Verified
New
Audio
Lyrics
Metadata
Streaming
UI
Tools
AI
```

Each plugin should show:

* Name
* Developer
* Version
* Compatibility
* Permissions
* Dependencies
* Privacy
* Verification
* Downloads
* Rating
* Last updated
* Source code
* Changelog

No user should need to paste a GitHub URL unless they deliberately want
developer mode.

The current GitHub URL installation is useful for developers, but the
consumer experience should become a proper catalog.

---

# 40. Automatic plugin updates

Support:

* Update checking
* Compatibility checking
* Backup
* Rollback
* Staged updates
* Failed-update recovery

Never allow an update to leave the user without a working plugin.

---

# 41. Database reliability

This is one of the areas to prioritize heavily.

Use transactional operations.

Never:

```text
write track
write history
write playlist
hope everything works
```

Instead:

```text
BEGIN
 ↓
validate
 ↓
write
 ↓
verify
 ↓
COMMIT
```

If failure:

```text
ROLLBACK
```

Add:

* Database integrity check
* Automatic backup
* Backup rotation
* Recovery
* Migration system
* Schema version
* Corruption detection
* Safe migration
* Export/import

---

# 42. Crash recovery

Omnis should maintain a tiny recovery journal.

Persist:

```text
current track
position
queue
queue index
playback mode
volume
output
```

frequently enough to recover from:

* crash
* power loss
* OS kill
* forced close
* battery death

The user should reopen Omnis and see:

> **Resume where you left off?**

---

# 43. Testing strategy needs to become enormous

The claim should eventually be:

> **Every critical subsystem is tested independently, under failure
> conditions.**

Test:

### Playback

* 1 track
* 10 tracks
* 100k tracks
* Empty queue
* Missing file
* Corrupt file
* Unsupported codec
* Zero-duration file
* Extremely long file
* Network timeout
* Bluetooth disconnect
* Device change
* Sleep/wake
* App background
* App kill
* Reboot

### Library

* 1 file
* 100 files
* 100,000 files
* 1,000,000 files
* Duplicate files
* Missing files
* Moved files
* Renamed files
* Invalid tags
* Unicode
* Emoji
* Multiple languages

### Plugins

Every plugin must be able to:

* Fail
* Timeout
* Crash
* Lose network
* Lose credentials
* Become unavailable
* Be disabled
* Be removed
* Be updated

without breaking Core.

---

# 44. Performance requirements

Set hard targets.

### Startup

Target:

**< 2 seconds** for normal startup on modern hardware.

### Playback

Audio playback must begin independently of:

* metadata enrichment
* artwork downloads
* lyrics
* recommendation engines
* plugin initialization

### Library

Never block UI while:

* scanning
* hashing
* tagging
* analyzing
* downloading
* indexing

Everything expensive is asynchronous.

---

# 45. Large-library architecture

Design for:

* 100 tracks
* 10,000 tracks
* 100,000 tracks
* 1,000,000+ tracks

Do not assume a library fits comfortably in memory.

---

# 46. Universal import

Omnis should import:

* Spotify playlists
* Apple Music playlists
* YouTube playlists
* YouTube Music playlists
* MusicBee
* foobar2000
* iTunes
* Windows Media Player
* MediaMonkey
* Plex
* Navidrome
* Jellyfin
* M3U
* XSPF
* PLS
* CSV
* JSON
* Folder structures

---

# 47. Universal export

Users should never fear leaving Omnis.

Export:

* Library
* Playlists
* Favorites
* Ratings
* History
* Tags
* Settings
* Plugin settings
* Layouts
* Themes

Prefer open formats.

---

# 48. Backup system

One click:

> **Backup Omnis**

Produces:

```text
omnis-backup.zip
├── database
├── playlists
├── history
├── favorites
├── settings
├── layouts
├── themes
└── plugin-state
```

And:

> **Restore Omnis**

with validation before overwriting anything.

---

# 49. Privacy should be a selling point

foobar2000 explicitly advertises no telemetry/data collection.

Omnis should make privacy equally understandable.

Settings:

```text
Telemetry
OFF

Crash reports
Ask

Listening history
Local only

Scrobbling
OFF

AI
OFF

Metadata lookup
Ask / Automatic

Artwork lookup
Ask / Automatic

Cloud sync
OFF
```

Do not make users wonder what Omnis is sending somewhere.

---

# 50. The Core should know nothing about Spotify

This is a key architectural test.

Bad:

```text
if (spotifyEnabled) ...
```

Good:

```text
providers.getAll<IMusicProvider>()
```

The same should apply to:

* YouTube
* LRCLIB
* Last.fm
* MusicBrainz
* Navidrome
* AI
* EQ
* Visualizer

---

# 51. Things to specifically change in the current architecture

### 1. Reduce `AppSettings`

The architecture has already moved some plugin-specific settings out of
`AppSettings`, which is exactly correct.

Continue aggressively.

`AppSettings` should contain only truly application-wide preferences.

Eventually something like:

```text
AppSettings
├── language
├── theme
├── startup
├── privacy
├── accessibility
└── core UI preferences
```

Everything else belongs to a subsystem/plugin.

### 2. Break up the large AudioEngine

The current `audio_engine.dart` is over 40 KB according to the repository
listing.

That is a warning sign.

Don't necessarily make everything a plugin, but split implementation
responsibilities:

```text
AudioEngine
PlaybackController
QueueController
OutputController
AudioSessionController
PlaybackRecovery
PlaybackPersistence
PlaybackState
```

The public engine facade can remain tiny.

### 3. Introduce stable capability protocols

There are currently interfaces for things such as:

* Lyrics
* Play history
* Queue building
* Metadata
* Audio analysis
* Visualizers

Expand this carefully.

Don't create an interface just because you can.

Create one when another implementation is realistically possible.

### 4. Introduce `CapabilityDescriptor`

Every plugin should declare:

```text
Provides:
- ILyricsProvider

Consumes:
- ITrackMetadata

Permissions:
- Network
- Library read

Optional:
- Authentication
```

This allows Omnis to automatically understand the ecosystem.

---

# 52. The ultimate plugin manifest

Conceptually:

```yaml
id:
name:
version:
description:
author:

compatibility:
  omnis: ">=2.0.0"
  api: ">=2.0.0"

provides:
  - lyrics.provider

consumes:
  - track.metadata

permissions:
  - network

settings:
  ...

ui:
  ...

dependencies:
  ...

conflicts:
  ...

privacy:
  data_collected: []
  network_hosts: []

verification:
  source_verified: true
  signed: true
```

---

# 53. User experience rule

The user should almost never encounter technical terminology.

Don't say:

> OAuth credential missing.

Say:

> **Spotify needs to be connected.**
> Click Connect Spotify to sign in.

Don't say:

> Plugin dependency resolution failed.

Say:

> **Lyrics Plus can't start because its Lyrics Provider is missing.**
> Install a compatible provider.

Don't say:

> Permission denied.

Say:

> Omnis needs permission to access your music folder.

---

# 54. "Everything works automatically"

The first-run experience should be:

### Welcome

**Welcome to Omnis**

> Where is your music?

```text
[Automatically find music]
[Choose folders]
[Skip for now]
```

Then:

```text
Scanning music...
```

Then automatically:

* Find artwork
* Read tags
* Build library
* Detect duplicates
* Find lyrics
* Calculate ReplayGain if enabled
* Build playlists
* Restore existing playlists
* Detect providers

No API configuration screen.

No developer settings.

No database setup.

No complicated wizard.

---

# 55. Recommended plugin catalog for the ultimate ecosystem

## Essential

* Favorites
* Ratings
* History
* ReplayGain
* Shuffle/Repeat
* Sleep Timer
* Lyrics
* Metadata
* Artwork
* Tag Editor
* Smart Playlists
* Equalizer
* Visualizer

## Audio

* Parametric EQ
* DSP
* Crossfeed
* Compressor
* Limiter
* Convolver
* Spatial
* Bit-perfect
* Resampler
* Loudness analyzer
* Dynamic range analyzer

## Streaming

* Spotify
* YouTube Music
* YouTube
* Apple Music
* Tidal
* Qobuz
* Deezer
* SoundCloud
* Bandcamp

Subject to each service's technical and licensing constraints.

## Servers

* Navidrome/OpenSubsonic
* Jellyfin
* Plex
* Emby
* DLNA
* UPnP
* SMB
* WebDAV
* FTP

## Discovery

* Radio
* Artist radio
* Track radio
* AI recommendations
* Sonic similarity
* Mood radio
* Discovery playlists

## Utility

* Duplicate cleaner
* Library analyzer
* Tag fixer
* Artwork manager
* File organizer
* Converter
* CD ripper
* Backup
* Import/export

## Hardware

* Bluetooth
* DAC
* AirPlay
* Chromecast
* UPnP
* Android Auto
* CarPlay

## UI

* Themes
* Layouts
* Visualizers
* Widgets
* Desktop mini-player
* Floating player
* Lock-screen controls
* TV interface
* Car interface

---

# 56. Features other players demonstrate that Omnis should absorb

| Player/ecosystem                | What Omnis should learn                                                        |
| ------------------------------- | ------------------------------------------------------------------------------ |
| **foobar2000**                  | Extreme customization, components, tagging, DSP, network audio, advanced users |
| **MusicBee**                    | Powerful functionality without making normal users configure everything        |
| **Spotify**                     | Discovery, personalization, effortless UX, intelligent shuffle                 |
| **Plexamp**                     | Sonic analysis, beautiful music-focused experience                             |
| **Navidrome**                   | Huge-library architecture, server ecosystem, multi-library, open API           |
| **Poweramp**                    | Audiophile controls, output/DAC attention                                      |
| **OpenSubsonic**                | Standardized interoperability                                                  |
| **Community plugin ecosystems** | Replaceable implementations instead of hard-coded features                     |

---

# 57. What Omnis should NOT become

This is equally important.

Do **not** make Omnis:

* A giant monolith.
* Dependent on one music service.
* Dependent on the Internet.
* Dependent on an account.
* Dependent on AI.
* Dependent on a plugin marketplace.
* Dependent on GitHub.
* Dependent on API keys.
* Dependent on one metadata provider.
* Dependent on one lyrics provider.
* Dependent on one audio backend.
* Dependent on one UI layout.
* Dependent on one database implementation.

The Core should remain boring.

**Boring Core = reliable product.**

---

# 58. The ultimate architecture

Target:

```text
                         OMNIS
                           │
             ┌─────────────┴─────────────┐
             │       USER INTERFACE      │
             │                            │
             │ Desktop / Mobile / TV /   │
             │ Car / Accessibility       │
             └─────────────┬─────────────┘
                           │
                    Capability Layer
                           │
       ┌───────────────────┼────────────────────┐
       │                   │                    │
    Playback            Library             Services
       │                   │                    │
       │              Metadata              Spotify
       │              Artwork               YouTube
       │              Search                Navidrome
       │              Tags                  Jellyfin
       │              Playlists             Plex
       │              History               ...
       │
       └─────────────── CORE ──────────────────┐
                                               │
        Audio Engine                           │
        Queue                                  │
        Media Model                            │
        Database                               │
        Storage                                │
        Recovery                               │
        Events                                 │
        Services                               │
        Plugin Runtime                         │
        Permissions                            │
        Security                               │
        OS Integration                         │
                                               │
                  NOTHING OPTIONAL             │
                  CAN BREAK IT                 │
```

---

# 59. Development priority

Do **not** attempt to build all of this simultaneously.

Work in this order:

### Phase 1 — Reliability

1. Playback engine
2. Queue
3. Recovery
4. Database
5. Library scanning
6. Persistence
7. OS media integration
8. Error handling
9. Tests

### Phase 2 — Library

10. Search
11. Metadata
12. Artwork
13. Playlists
14. Favorites
15. Ratings
16. History
17. Tag editor

### Phase 3 — Audio

18. DSP pipeline
19. ReplayGain
20. EQ
21. Output devices
22. Bit-perfect
23. Audio analysis

### Phase 4 — Plugin platform

24. Capability interfaces
25. Plugin lifecycle
26. Dependency resolution
27. Permissions
28. Plugin health
29. Plugin updates
30. Marketplace/catalog

### Phase 5 — Connectivity

31. OpenSubsonic
32. Navidrome
33. Jellyfin
34. Plex
35. DLNA/UPnP
36. Spotify
37. YouTube
38. Other providers

### Phase 6 — Discovery

39. Recommendations
40. Sonic similarity
41. Radio
42. Smart playlists
43. AI

### Phase 7 — Advanced UX

44. Themes
45. Layout builder
46. Car mode
47. TV mode
48. Accessibility
49. Widgets
50. Automation

---

# 60. The highest-priority rule

> **Do not implement a feature merely because it works. Implement it so
> that failure is an expected operating condition.**

For every feature ask:

```text
What happens if:
- the network disappears?
- the file disappears?
- the plugin crashes?
- the provider changes its API?
- authentication expires?
- the database is corrupted?
- the user denies permission?
- the device disappears?
- the user uninstalls the plugin?
- the plugin is outdated?
- the data is malformed?
- the user has 1,000,000 songs?
- the user has zero songs?
- the user is offline?
```

If the answer is:

> "The application crashes."

**The implementation is not finished.**

---

# 61. Assessment of the current Omnis direction

### Architecture: **Excellent foundation**

The separation of:

* Core
* Plugin API
* Plugins
* Service Registry
* Event Bus
* Plugin Storage

is exactly the right general direction.

### Plugin ecosystem: **Strong beginning**

You already have a surprisingly broad collection:

* Audio analysis
* Bluetooth
* Driving mode
* EQ
* Favorites
* Lyrics
* Metadata
* Queue presets
* ReplayGain
* Ringtone
* Scrobbling
* Shuffle/repeat
* Sleep timer
* Smart playlists
* Spotify
* YouTube
* Tag editor
* Visualizer

The plugin repository currently documents roughly twenty plugin
implementations, while also honestly identifying several that still need
real-device/account verification.

That's actually a good sign: **the project is honest about what is
implemented versus verified.**

### Biggest architectural concern

The Core is still carrying more responsibility than the final philosophy
suggests.

In particular:

* `AudioEngine`
* `AppSettings`
* library persistence
* scanner
* playback state
* UI integration

need to be continually audited.

The architecture document already identifies this issue and has begun
moving functionality out of `AppSettings`.

---

# 62. The final product vision

The thing to ultimately market is not:

> "Another music player."

It is:

> **Omnis — Your Music. Your Way. One Player.**
>
> A powerful, private, universal music platform that plays your music
> reliably without requiring an account, subscription, API key, cloud
> service or plugin configuration.
>
> Start with a simple music player.
>
> Add anything you want.
>
> Change anything you don't.
>
> Your library remains yours.

That positioning separates Omnis from both sides of the market:

**Spotify-style users** get simplicity.

**MusicBee/foobar2000 users** get control.

**Audiophiles** get serious audio functionality.

**Power users** get plugins.

**Self-hosters** get open protocols.

**Casual users** don't have to know any of that exists.

---

## The single biggest design rule

**Complexity belongs behind the interface, never in front of the user.**

The user should see:

> **Lyrics**

not LRCLIB.

> **Music Services**

not OAuth.

> **Improve Metadata**

not MusicBrainz API.

> **Connect Server**

not Subsonic protocol.

> **Better Sound**

not DSP chain.

> **Equalizer**

not audio processing graph.

> **Install Plugin**

not Dart runtime.

> **Fix Problem**

not exception stack trace.

That is how Omnis can become something substantially better than simply
"foobar2000 with a modern UI" or "Spotify for local files."

The technical foundation already being built — especially the
capability-based architecture — is capable of supporting this. The next
step should be **turning this specification into an explicit
implementation contract for the AI agent**, with Core requirements,
plugin interfaces, database schema, event contracts, settings schema,
UI architecture, reliability requirements, testing requirements, and a
phased build order so the agent cannot gradually turn the project back
into a monolith.
