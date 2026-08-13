# Omnis y 2.0 — UI/UX Master Design Specification

> **Status:** Canonical reference for the Omnis 2.0 UI direction.
> This document is the UI/UX requirements contract. It is one of the three
> canonical references for the Omnis 2.0 build — read it together with
> [OMNIS_2_0_SPEC.md](OMNIS_2_0_SPEC.md) (the product specification) and
> [OMNIS_2_0_PLUGINS.md](OMNIS_2_0_PLUGINS.md) (the plugin architecture
> & developer guide). The [Architecture](ARCHITECTURE.md) document
> describes what exists today; these three documents describe where Omnis
> is going.

## 0. The central concept — a programmable music environment

> **Omnis 2.0 build reference:** This UI guide is one of the three required
> references for the Omnis 2.0 build. The others are the product spec —
> [OMNIS_2_0_SPEC.md](OMNIS_2_0_SPEC.md) — and the plugin architecture &
> developer guide — [OMNIS_2_0_PLUGINS.md](OMNIS_2_0_PLUGINS.md).
> Together they define where Omnis is going, how the interface must look,
> feel, and adapt, and how the plugin platform works.

Omnis should be a **programmable music environment** — not merely "a UI with themes."

It should have **three distinct layers**:


```text
┌─────────────────────────────────────────────┐
│               OMNIS UI SHELL                │
│                                             │
│  Navigation / Sidebar / Global Controls     │
│                                             │
├─────────────────────────────────────────────┤
│                                             │
│             USER EXPERIENCE                 │
│                                             │
│ Home / Library / Moods / Playlists           │
│                                             │
├─────────────────────────────────────────────┤
│                                             │
│              PLAYER SURFACE                 │
│                                             │
│ Current track / Queue / Lyrics / Visuals    │
│                                             │
└─────────────────────────────────────────────┘
```

But underneath:

```text
UI
 ↓
UI Components
 ↓
Capability System
 ↓
Omnis Core / Plugins
```

**The UI must never directly depend on a particular plugin implementation.**

The controlling concept:

> **A user opens Omnis and immediately feels like this is *their* music
> player. Every major visual element can be moved, resized, replaced,
> hidden, restyled, or transformed by a theme/design pack — without
> breaking the underlying functionality.**

And critically, **themes should not merely change colors.** A theme can
completely change the *composition and interaction model* while still
consuming the same Omnis capabilities.

---

# 1. The five primary destinations

Omnis should initially have five fundamental destinations:

### HOME

The user's personalized music dashboard.

### LIBRARY

Everything the user owns or has connected.

### MOODS

Music organized around how the user wants to feel.

### PLAYLISTS

All manually created and smart playlists.

### NOW PLAYING

Not necessarily a traditional page.

It should be a **universal player surface** that can appear as:

* mini-player
* bottom player
* full-screen player
* floating player
* side panel
* dedicated screen
* driving interface
* karaoke interface

---

# 2. The permanent navigation

Desktop default:

```text
┌────────────────────────────────────────────────────────────┐
│ OMNIS                                                     │
├───────────────┬────────────────────────────────────────────┤
│               │                                            │
│  🏠 Home      │                                            │
│  ♪ Library    │             MAIN CONTENT                   │
│  ◉ Moods      │                                            │
│  ♫ Playlists  │                                            │
│               │                                            │
│               │                                            │
│  + My Music   │                                            │
│  + Playlist   │                                            │
│  + Mood       │                                            │
│               │                                            │
│               │                                            │
│  ⚙ Settings  │                                            │
│               │                                            │
├───────────────┴────────────────────────────────────────────┤
│                 NOW PLAYING / MINI PLAYER                  │
└────────────────────────────────────────────────────────────┘
```

But this is only the **default theme**.

The navigation itself must be configurable.

---

# 3. Pop-out sidebar

This is one of the strongest ideas.

Make it a fundamental Omnis interaction.

There should be a **global sidebar drawer** that can be summoned from
anywhere.

Desktop:

```text
                  MAIN CONTENT
┌─────────────────────────────────────────────┐
│                                             │
│                                             │
│                                             │
│                                             │
│                                             │
│                                             │
└─────────────────────────────────────────────┘
                    ▲
                    │
                 sidebar
```

When opened:

```text
┌───────────────────┬─────────────────────────┐
│                   │                         │
│ OMNIS             │                         │
│                   │                         │
│ Home              │                         │
│ Library           │                         │
│ Moods             │                         │
│ Playlists         │                         │
│                   │                         │
│ ───────────────   │                         │
│ MY PLAYLISTS      │                         │
│                   │                         │
│ Workout           │                         │
│ Favorites         │                         │
│ Road Trip         │                         │
│ 90s Rock          │                         │
│                   │                         │
│ ───────────────   │                         │
│ MY MOODS          │                         │
│                   │                         │
│ Chill             │                         │
│ Energy            │                         │
│ Focus             │                         │
│ Driving           │                         │
│                   │                         │
│ + Add              │                         │
│ ⚙ Settings         │                         │
└───────────────────┴─────────────────────────┘
```

### Important:

The sidebar is **not just navigation.**

It is the user's personal music command center.

---

# 4. Sidebar customization

Users should be able to:

### Add

* Playlist
* Mood
* Smart playlist
* Library
* Provider
* Server
* Favorite album
* Favorite artist
* Radio station
* Shortcut

### Remove

Anything they don't want.

### Reorder

Drag:

```text
Home
Library
Moods
Playlists
```

into:

```text
Home
Playlists
Moods
Library
```

### Group

Example:

```text
MY MUSIC
────────────
Library

MY PLAYLISTS
────────────
Workout
Driving
Favorites

MY MOODS
────────────
Chill
Focus
Energy

SERVERS
────────────
My NAS
Navidrome
```

---

# 5. Sidebar modes

The sidebar should support:

### Expanded

```text
[icon] Home
[icon] Library
```

### Compact

```text
🏠
♫
◉
☷
```

### Floating

It overlays content.

### Pinned

It permanently occupies space.

### Hidden

Only accessible through a hotkey/gesture.

### Auto-hide

Appears when cursor reaches edge.

### Mobile drawer

Swipe from left.

---

# 6. Home page

Home should **not** be a boring list of albums.

It should feel alive.

Think:

> "What should I listen to right now?"

rather than:

> "Here's your database."

---

# HOME

Example:

```text
┌─────────────────────────────────────────────────────────────┐
│ Good evening, Josh                                         │
│ What are you listening to?                                 │
│                                                             │
│ [ Search music, artists, albums, playlists... ]             │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ CONTINUE LISTENING                                          │
│                                                             │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐               │
│ │ Album  │ │ Album  │ │ Album  │ │ Album  │               │
│ └────────┘ └────────┘ └────────┘ └────────┘               │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ YOUR MOODS                                                  │
│                                                             │
│ [ Chill ] [ Energy ] [ Focus ] [ Driving ] [ Sleep ]       │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ MADE FOR YOU                                                │
│                                                             │
│ Large personalized recommendation cards                     │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ RECENTLY ADDED                                              │
│                                                             │
│ Albums / songs / artists                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

But here's where customization becomes important.

---

# 7. Home is a widget canvas

Every Home section should be a **widget**.

For example:

```text
Home
 ├── Greeting
 ├── Search
 ├── Continue Listening
 ├── Quick Actions
 ├── Moods
 ├── Favorites
 ├── Recently Added
 ├── Recently Played
 ├── Most Played
 ├── Recommendations
 ├── New Releases
 ├── Artist Radio
 ├── Smart Mix
 └── Custom
```

Users can:

* Hide
* Show
* Reorder
* Resize
* Change layout
* Change appearance
* Change data source

---

# 8. Home layouts

### Classic

```text
Greeting
Search
Continue
Moods
Albums
Playlists
```

### Minimal

```text
Search

Continue Listening

Recently Played
```

### Album-heavy

Huge album artwork.

### Discovery

Recommendations dominate.

### Audiophile

Technical information dominates.

### Social

Listening history/playlists dominate.

---

# 9. Library

Library should be extremely powerful without feeling complicated.

Top:

```text
LIBRARY

[All] [Songs] [Albums] [Artists] [Genres] [Folders] [Composers]
```

Then:

```text
[ Search Library ]

Sort:
Recently Added ▼

View:
▦ Grid
☷ List
≡ Compact
```

---

# 10. Library views

Users should be able to choose:

### Album grid

Large artwork.

### Dense grid

Small artwork, many albums.

### List

```text
Title             Artist           Album           Duration
-----------------------------------------------------------
Song               Artist           Album            3:42
```

### Compact

Designed for enormous libraries.

### Folder tree

Traditional filesystem-style browsing.

### Artist-centric

```text
Artist
 ├── Albums
 ├── Singles
 ├── Compilations
 ├── Similar Artists
 └── Biography
```

---

# 11. Library customization

Users should be able to choose:

```text
Display:
☑ Artwork
☑ Artist
☑ Album
☑ Year
☐ Genre
☐ Bitrate
☐ Format
☐ Rating
☐ Play count
☐ ReplayGain
```

And reorder metadata columns.

---

# 12. Moods

Moods should **not simply be genres renamed.**

This needs to be a unique Omnis feature.

The page should visually communicate emotion.

Example:

```text
MOODS

How do you want to feel?

┌──────────────┐ ┌──────────────┐
│              │ │              │
│   CHILL      │ │   ENERGY     │
│              │ │              │
└──────────────┘ └──────────────┘

┌──────────────┐ ┌──────────────┐
│              │ │              │
│   FOCUS      │ │   HAPPY      │
│              │ │              │
└──────────────┘ └──────────────┘

┌──────────────┐ ┌──────────────┐
│              │ │              │
│   SAD        │ │   ROMANTIC   │
│              │ │              │
└──────────────┘ └──────────────┘
```

---

# 13. User-created moods

Users can create:

> **Late Night Drive**

and define:

```text
Mood name:
Late Night Drive

Genres:
Rock
Synthwave
Alternative

Energy:
40–75%

Tempo:
80–130 BPM

Mood:
Dark
Relaxed
Focused

Time:
9 PM – 3 AM

Rating:
≥ 3

Exclude:
Played in last 7 days
```

Then:

**Play Late Night Drive**

becomes an intelligent queue.

---

# 14. Mood visuals

Every mood can have:

* Color
* Background
* Artwork
* Icon
* Animation
* Gradient
* Sound behavior
* Playlist rules

So:

### Chill

Soft animation.

### Energy

Fast animated background.

### Driving

Large controls.

### Sleep

Dark, minimal interface.

---

# 15. Playlists

Playlists should have two types:

### Static

User controls everything.

### Smart

Omnis generates the contents.

---

# 16. Playlist page

Example:

```text
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│       [PLAYLIST ARTWORK]                                    │
│                                                             │
│       ROAD TRIP                                             │
│       143 songs • 9h 42m                                    │
│                                                             │
│       [▶ PLAY] [SHUFFLE] [+ ADD] [•••]                      │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ #   TITLE              ARTIST          ALBUM          TIME   │
│                                                             │
│ 1   Song               Artist          Album          3:42   │
│ 2   Song               Artist          Album          4:10   │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

# 17. Playlist customization

Users should be able to:

* Change artwork
* Change color
* Add description
* Add mood
* Add rules
* Reorder tracks
* Sort tracks
* Shuffle
* Duplicate
* Merge
* Export
* Share
* Make collaborative
* Pin to sidebar

---

# 18. Now Playing must be extraordinary

This is the visual centerpiece of Omnis.

The default Now Playing:

```text
┌────────────────────────────────────────────────────────────┐
│                                                            │
│                    [ ALBUM ART ]                           │
│                                                            │
│                    Song Title                              │
│                    Artist                                  │
│                                                            │
│             ───────●────────────────                       │
│                                                            │
│       ◀◀        ◀     ▶     ▶        ↻                    │
│                                                            │
│                 ♡  +  •••                                  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

But this is only **one skin**.

---

# 19. Now Playing components

Every component becomes independently controllable.

```text
NowPlaying
├── Background
├── Artwork
├── TrackInfo
├── ArtistInfo
├── Progress
├── Waveform
├── PlaybackControls
├── QueueButton
├── LyricsButton
├── Favorite
├── Rating
├── Volume
├── Device
├── AudioInfo
├── DSP
├── Visualizer
└── CustomWidgets
```

---

# 20. Theme engine

This is the most important UI architecture decision.

**Do not build themes as color schemes.**

Build:

> **Theme = UI composition + styling + behavior + assets + layout rules**

A theme can define:

```text
Theme
├── Colors
├── Typography
├── Shapes
├── Icons
├── Animations
├── Backgrounds
├── Components
├── Layouts
├── Navigation
├── Player
├── Home
├── Library
├── Moods
├── Playlists
├── Settings
└── Interactions
```

---

# 21. Theme packs

A theme pack should be capable of saying:

```yaml
theme:
  id: futuristic

navigation:
  type: floating

home:
  layout: dashboard

nowPlaying:
  layout: immersive

library:
  layout: dense-grid

animation:
  enabled: true

colors:
  primary: ...
```

But ultimately the implementation should use strongly typed schemas
rather than letting arbitrary theme files manipulate Flutter widgets
directly.

---

# 22. Theme presets you should build

I strongly recommend creating **at least six** official themes.

---

## THEME 1 — OMNIS CLASSIC

Purpose:

Show users what the normal Omnis experience is.

Characteristics:

* Clean
* Modern
* Familiar
* Dark/light
* Album art
* Traditional navigation
* Bottom mini-player
* Standard library

This should be the default.

---

# 23. THEME 2 — PURE

The "simple music player."

Almost nothing.

```text
┌─────────────────────────────┐
│                             │
│         ALBUM ART           │
│                             │
│        Song Title           │
│        Artist               │
│                             │
│       ─────●──────          │
│                             │
│        ◀  ▶  ▶              │
│                             │
└─────────────────────────────┘
```

No clutter.

Perfect for:

* Beginners
* Older users
* People who don't care about advanced features

---

# 24. THEME 3 — DRIVE

This should be a completely different UI.

Huge buttons.

Minimal text.

High contrast.

```text
┌────────────────────────────────────────────┐
│                                            │
│             NOW PLAYING                    │
│                                            │
│           ████████████                     │
│           █  ARTWORK  █                     │
│           ████████████                     │
│                                            │
│             SONG TITLE                     │
│             ARTIST                         │
│                                            │
│      ◀◀       ▶       ▶▶                  │
│                                            │
│      ♥        QUEUE       VOICE            │
│                                            │
└────────────────────────────────────────────┘
```

Interactions:

* Huge targets
* Swipe next
* Swipe previous
* Voice
* No tiny controls
* No complicated menus

---

# 25. THEME 4 — KARAOKE

This could be one of Omnis' signature experiences.

Artwork becomes secondary.

Lyrics become primary.

```text
┌─────────────────────────────────────────────┐
│                                             │
│              SONG TITLE                     │
│                                             │
│        I DON'T WANNA MISS A THING           │
│                                             │
│          I COULD STAY AWAKE                │
│                                             │
│       I COULD STAY AWAKE JUST TO...        │
│                                             │
│              ♪ SING ♪                      │
│                                             │
│       ─────────●────────────                │
│                                             │
│        ◀       ▶       ▶                    │
│                                             │
└─────────────────────────────────────────────┘
```

Features:

* Word following
* Line highlighting
* Automatic scrolling
* Font size
* Lyrics positioning
* Background artwork blur
* Karaoke mode
* Translation
* Timing adjustment
* Lyrics sync editor

---

# 26. THEME 5 — FUTURE

This should make people immediately recognize Omnis.

Think:

**music operating system.**

Not a generic Flutter dashboard.

Use:

* Layered panels
* Glass surfaces
* Dynamic album artwork
* Audio-reactive effects
* Floating navigation
* Animated transitions
* Spectrum visualization
* Dynamic colors
* Spatial layout

Example:

```text
       ┌───────────────┐
       │   ARTWORK     │
       │               │
       └───────────────┘

    SONG TITLE
    ARTIST

 ───────────────●────────────

        ◀   ▶   ▶

 ┌─────────┐ ┌──────────────┐
 │ QUEUE   │ │ VISUALIZER   │
 └─────────┘ └──────────────┘
```

The important thing:

**Do not make this a neon cyberpunk cliché.**

It should look like a plausible music interface from 2035.

---

# 27. THEME 6 — AUDIOPHILE

Everything is about audio.

Display:

```text
FLAC
24-bit
96 kHz
Lossless

ReplayGain
-7.3 dB

Peak
-0.2 dB

Output
USB DAC

DSP
OFF
```

Waveform.

Spectrum.

Technical controls.

Minimal decorative UI.

---

# 28. Themes can alter navigation

This is essential.

Classic:

```text
Sidebar
```

Future:

```text
Floating radial navigation
```

Driving:

```text
Bottom navigation
```

Karaoke:

```text
Top controls
```

Audiophile:

```text
Left technical navigation
```

**All of them access the same Omnis capabilities.**

---

# 29. Design packs

Separate:

### Theme

Changes visual identity.

### Layout Pack

Changes arrangement.

### Behavior Pack

Changes interaction.

### Complete Experience Pack

Changes all three.

This distinction will prevent your architecture from becoming messy.

---

# 30. User customization mode

Omnis needs a visual editor.

Something like:

> **Customize Omnis**

Then the UI enters editing mode.

Every component receives a subtle outline.

```text
┌──────────────────────────────────────┐
│ HOME                         [Edit]  │
│                                      │
│ ┌──────────────────────────────────┐ │
│ │ Continue Listening               │ │
│ └──────────────────────────────────┘ │
│                                      │
│ ┌──────────┐ ┌──────────┐           │
│ │ Moods    │ │ Playlists│           │
│ └──────────┘ └──────────┘           │
└──────────────────────────────────────┘
```

Click a component:

```text
CONTINUE LISTENING

Visibility     [ON]
Size           [Large ▼]
Columns        [4]
Artwork        [Square ▼]
Show artist    [✓]
Show album     [✓]
Show duration  [ ]
```

---

# 31. Drag-and-drop UI builder

Users should be able to:

```text
Home
 ├── Greeting
 ├── Search
 ├── Moods
 ├── Recently Played
 ├── Favorites
 └── Recommendations
```

Drag:

**Moods**

above:

**Search**

and the layout changes.

---

# 32. Component library

Every reusable UI component should be registered.

Examples:

```text
OmnisAlbumCard
OmnisTrackRow
OmnisArtistCard
OmnisPlaylistCard
OmnisMoodCard
OmnisWaveform
OmnisLyrics
OmnisPlaybackControls
OmnisQueue
OmnisSearch
OmnisLibraryGrid
OmnisMiniPlayer
OmnisVisualizer
OmnisAudioInfo
```

Themes consume these components.

---

# 33. Do NOT allow themes to directly manipulate arbitrary Flutter widgets

This is critical.

Bad architecture:

```text
Theme
 ↓
arbitrary Flutter code
 ↓
entire application
```

That would make themes unsafe and impossible to maintain.

Instead:

```text
Theme
 ↓
Omnis Design System
 ↓
Typed Components
 ↓
Capabilities
```

---

# 34. Design tokens

Build a central design-token system.

```text
OmnisTheme
├── colors
├── typography
├── spacing
├── radius
├── elevation
├── shadows
├── animation
├── icons
├── density
├── artwork
└── component styles
```

Example:

```text
spacing:
  xs
  sm
  md
  lg
  xl

radius:
  none
  small
  medium
  large
  pill

density:
  compact
  comfortable
  spacious
```

---

# 35. Dynamic artwork theming

This can make Omnis feel extremely polished.

When playing an album:

```text
Album artwork
      ↓
Extract palette
      ↓
Generate theme accents
      ↓
Update player background
      ↓
Update progress
      ↓
Update visualizer
```

But always allow:

**Dynamic colors: OFF**

because some users will hate it.

---

# 36. Motion system

Animations must be intentional.

Define:

```text
motion:
  instant
  fast
  normal
  expressive
  cinematic
  disabled
```

Accessibility:

> **Reduce motion**

must globally override animations.

---

# 37. Search should be everywhere

Global keyboard shortcut:

**Ctrl + K**

opens:

```text
┌─────────────────────────────────────────────┐
│ Search Omnis                                │
│                                             │
│ 🔎 Type anything...                         │
│                                             │
│ Songs                                       │
│ Artists                                     │
│ Albums                                      │
│ Playlists                                   │
│ Moods                                       │
│ Settings                                    │
│ Commands                                    │
└─────────────────────────────────────────────┘
```

It should search **the entire application**, not just music.

Example:

> `crossfade`

returns:

**Settings → Playback → Crossfade**

Example:

> `Driving`

returns:

* Mood
* Playlist
* Theme
* Setting
* Command

---

# 38. Command palette

This should be built into Omnis.

Ctrl+K / Ctrl+P:

```text
Play
Pause
Next
Previous
Shuffle
Add to playlist
Create mood
Open settings
Enable driving mode
Open lyrics
Toggle visualizer
Change theme
Customize home
Scan library
```

Power users will love this.

---

# 39. Context menus

Right click / long press should be consistent everywhere.

Track:

```text
Play
Play next
Add to queue
Add to playlist
Add to mood
Favorite
Rate
View album
View artist
View lyrics
Edit metadata
Find artwork
Analyze audio
Share
Properties
```

Album:

```text
Play
Queue
Favorite
Add to playlist
Add to mood
Edit metadata
Find artwork
Analyze
```

---

# 40. Mini-player

The mini-player should be globally persistent.

Desktop:

```text
┌───────────────────────────────────────────────────────────────┐
│ [Art] Song Title — Artist       ♡   ◀   ▶   ▶   Queue   🔊  │
└───────────────────────────────────────────────────────────────┘
```

Click it:

**expands into the active theme's Now Playing experience.**

---

# 41. Queue panel

The queue should slide from the right.

```text
┌─────────────────────────────┐
│ QUEUE                       │
│                             │
│ NOW PLAYING                 │
│ Song                        │
│                             │
│ NEXT                        │
│ Song                        │
│ Song                        │
│ Song                        │
│                             │
│ ─────────────               │
│ HISTORY                     │
│ Song                        │
└─────────────────────────────┘
```

Drag tracks.

---

# 42. Mobile

Do not simply shrink the desktop interface.

Mobile gets its own interaction rules.

Bottom navigation:

```text
┌──────────────────────────────┐
│                              │
│          CONTENT             │
│                              │
│                              │
├──────────────────────────────┤
│ Album                        │
│ Song                         │
│ Artist                       │
│ ─────────────●──────         │
├──────────────────────────────┤
│ Home Library Moods Playlist  │
└──────────────────────────────┘
```

Swipe:

* left → next
* right → previous
* up → full player
* down → collapse

---

# 43. Tablet

Use split panes.

```text
┌─────────────┬───────────────────────────┐
│ Navigation  │                           │
│             │       Library             │
│             │                           │
│             │       Albums              │
│             │                           │
├─────────────┴───────────────────────────┤
│               Mini Player               │
└──────────────────────────────────────────┘
```

---

# 44. TV

Completely different.

Large:

* Artwork
* Text
* Controls
* Remote navigation

No mouse assumptions.

---

# 45. Settings UI

Settings should be a **capability browser**, not a massive list.

```text
SETTINGS

Appearance
Playback
Audio
Library
Downloads
Privacy
Accessibility
Keyboard
Notifications
Services
Plugins
Storage
Backup
Advanced
```

But if a plugin adds:

**Lyrics**

Omnis automatically exposes:

```text
Settings
 └── Lyrics
```

without manually hardcoding the page.

---

# 46. Settings customization

Users should be able to:

* Pin settings
* Hide advanced categories
* Search settings
* Reset individual settings
* Reset category
* Reset all settings
* Export settings
* Import settings

---

# 47. UI state persistence

Omnis must remember:

* Last page
* Sidebar state
* Window size
* Window position
* Panel widths
* Player state
* Queue
* Library view
* Sort order
* Filters
* Theme
* Home layout
* Expanded sections
* Settings navigation position

---

# 48. Multiple UI profiles

This could be extremely powerful.

User could have:

### Desktop

Futuristic

### Car

Driving

### TV

Simple

### Work

Minimal

Switch automatically.

```text
Bluetooth device connected
        ↓
"Car stereo"
        ↓
Activate Driving UI
```

---

# 49. UI profiles should be exportable

Users could share:

> **Josh's Omnis Setup**

containing:

* Theme
* Layout
* Sidebar
* Home widgets
* Player configuration
* Keyboard shortcuts
* Settings

without including private information.

---

# 50. Theme marketplace eventually

Imagine:

```text
OMNIS DESIGN STORE

Featured

◆ Futurewave
◆ Vinyl
◆ Minimal
◆ Cyber
◆ Glass
◆ Retro
◆ AMOLED
◆ Classic Hi-Fi
◆ Karaoke
◆ Car
```

A user clicks:

**Install**

and Omnis changes.

---

# 51. The design language

Establish these rules for the AI agent:

### Rule 1

**Artwork is important, but never allowed to destroy usability.**

### Rule 2

**Every action must have a predictable location.**

### Rule 3

**Don't hide essential controls behind decorative interactions.**

### Rule 4

**Advanced functionality should be available without being forced upon
casual users.**

### Rule 5

**Never make the UI look like a developer dashboard.**

### Rule 6

**Never create a screen just because the backend has a service.**

### Rule 7

**Every screen needs a clear visual hierarchy.**

### Rule 8

**Empty states must be designed.**

### Rule 9

**Loading states must be designed.**

### Rule 10

**Error states must be designed.**

---

# 52. Empty states

Never show:

```text
No playlists.
```

Show:

```text
                 ♪

          Your playlists

       Your music deserves
       its own soundtrack.

             [+ Create]
```

---

# 53. First-run experience

First launch:

```text
                 OMNIS

           Your music. Your way.

        [ Find My Music ]

        [ Choose Music Folder ]

        [ Explore Without Music ]
```

Then:

```text
Where should Omnis look?

☑ Music
☐ Downloads
☐ Desktop
☐ External Drives

              [Continue]
```

Then:

```text
Building your library...

██████████████████░░░

1,842 songs
137 albums
84 artists
```

And then:

**Home appears populated immediately.**

---

# 54. Loading states

Use skeleton UI rather than spinning wheels everywhere.

Album:

```text
┌──────────┐
│ ░░░░░░░░ │
│ ░░░░░░░░ │
└──────────┘
░░░░░░░░░░░
░░░░░░░░
```

---

# 55. Error states

Never:

> Exception: Null check operator used...

Instead:

> **We couldn't play this song.**
>
> Omnis will try another playback method automatically.
>
> **[Retry] [Skip] [Details]**

Details can expose technical information.

---

# 56. The UI should be capability-aware

If no lyrics plugin exists:

Don't show a broken Lyrics page.

Instead:

> **Lyrics**
>
> Add a lyrics provider to enable lyrics.

If a feature exists:

Show it.

This creates a UI that **adapts to the user's installation**.

---

# 57. But don't let plugins destroy the navigation

Plugins should contribute capabilities, not randomly add navigation items.

Use:

```text
NavigationContribution
```

with:

```text
priority
icon
label
destination
visibility
category
```

Then Omnis controls the overall hierarchy.

---

# 58. The "Omnis Experience Graph"

I would actually introduce an internal model like:

```text
Experience
├── Navigation
├── Home
├── Library
├── Moods
├── Playlists
├── Player
├── Queue
├── Search
├── Settings
└── Components
```

Themes manipulate the **Experience Graph**, not Flutter screens.

That is the architectural difference between a theme system and a true
customizable UI platform.

---

# 59. The AI agent's UI implementation rule

Give your coding agent this exact instruction:

> **Never create a UI screen as a one-off collection of widgets. Every
> meaningful visual element must be implemented as a reusable,
> theme-aware, capability-aware Omnis component. Screens are compositions
> of components. Themes are compositions of layouts and component styles.
> Plugins provide capabilities and optional components. The Core owns the
> design system, component contracts, navigation model, state management,
> accessibility contracts, and layout persistence.**

That single rule will prevent a tremendous amount of future technical
debt.

---

# 60. The component hierarchy I recommend

```text
OmnisApp
│
├── OmnisShell
│   │
│   ├── Navigation
│   ├── Sidebar
│   ├── GlobalSearch
│   ├── CommandPalette
│   └── MiniPlayer
│
├── OmnisExperience
│   │
│   ├── Home
│   ├── Library
│   ├── Moods
│   ├── Playlists
│   └── Settings
│
└── OmnisPlayer
    │
    ├── Mini
    ├── Expanded
    ├── Fullscreen
    ├── Queue
    ├── Lyrics
    └── Device
```

---

# 61. And finally: make Omnis visually unforgettable

This is where the AI agent should be pushed harder than most coding
agents are normally pushed.

**Do not ask it to "make a modern UI."**

That produces generic rounded rectangles.

Tell it:

> Every major Omnis screen must have a deliberate visual composition.
>
> Use large-scale artwork, intentional negative space, clear typography
> hierarchy, meaningful motion, strong information hierarchy, responsive
> layouts, and distinct visual identities for each official theme.
>
> Avoid generic dashboard design.
>
> Avoid excessive cards.
>
> Avoid putting every piece of information inside a rounded rectangle.
>
> Avoid gradients merely for decoration.
>
> Avoid neon cyberpunk clichés.
>
> Avoid excessive glassmorphism.
>
> Avoid tiny controls.
>
> Avoid inconsistent spacing.
>
> Avoid arbitrary icons.
>
> Avoid UI that looks like a Flutter sample application.
>
> The application should look like a professionally designed consumer
> product.

---

# 62. The three-layer UI test

Every feature the AI builds should pass this test:

### Layer 1 — Normal user

Can they understand it immediately?

### Layer 2 — Power user

Can they customize it?

### Layer 3 — Designer

Can they completely transform it through the theme/layout system?

For example:

**Lyrics**

Normal:

> Tap Lyrics.

Power user:

> Change font, size, timing, position.

Designer:

> Build an entirely different karaoke experience around the lyrics
> capability.

That is the standard.

---

# 63. What I would make the "Omnis moment"

When someone installs Omnis, the first thing they should eventually see
after scanning their library is something like:

```text
                         OMNIS

              Your music, beautifully yours.

          ┌──────────────────────────────┐
          │                              │
          │        CURRENT ALBUM         │
          │                              │
          └──────────────────────────────┘

                    Song Title
                       Artist

             ─────────●──────────

               ◀       ▶       ▶

        ┌────────┐ ┌────────┐ ┌────────┐
        │ CHILL  │ │ ENERGY │ │ DRIVE  │
        └────────┘ └────────┘ └────────┘

             Continue Listening
```

Then the user realizes:

**"Wait. I can completely change this."**

They select:

> **Customize**

and Omnis becomes a design environment.

Then they install:

**Karaoke**

and the entire player transforms into a lyric-focused interface.

They select:

**Driving**

and it becomes a giant-button automotive interface.

They select:

**Audiophile**

and it becomes a precision audio workstation.

They select:

**Future**

and it becomes an immersive music environment.

**Same library. Same playback engine. Same plugins. Same music.
Completely different experience.**

That is the concept that can make Omnis genuinely memorable rather than
merely "another open-source music player."

### The architectural phrase to put at the top of the AI agent's UI documentation:

> **OMNIS IS NOT A UI WITH THEMES. OMNIS IS A MUSIC EXPERIENCE ENGINE.**

That should guide the entire frontend implementation.