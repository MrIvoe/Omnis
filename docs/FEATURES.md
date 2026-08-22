# Features

**Playback**
- Gapless queue playback, crossfade, ReplayGain-based volume normalization
- Shuffle, repeat (off/all/one), A-B repeat
- Independent pitch and speed controls, skip-silence
- Real per-band hardware equalizer on Android; a virtual bass/mid/treble
  model everywhere else

**Library**
- List/grid views (2–5 column density) for Songs, Albums, and Genres;
  list views for Artists and Folders
- Duplicate and short-track ("ad stinger") detection with multi-select
  cleanup
- Real embedded artwork everywhere (MediaStore on Android, direct ID3
  parsing on desktop) — not a placeholder icon
- Manual and automatic ID3 tag editing — every standard field, plus
  freeform custom fields — with smart skip-if-already-tagged tracking
- Configurable "feat./ft./featuring" artist-separator rules, so a
  featured artist doesn't stay stuck in the title field

**Lyrics**
- Manual lyrics entry, or automatic online lookup (via
  [lrclib.net](https://lrclib.net), free, no API key) with optional
  time-synced display
- Optional auto-fetch when a track starts playing, and an option to embed
  fetched lyrics directly into the file's own tags

**Customization**
- Six built-in Now Playing layouts (Standard, Top Controls, Landscape,
  Full Art + Gestures, Karaoke Gestures, Car Mode), plus an importable
  declarative layout format for building your own — no code required,
  safe to import from a URL with no permission prompt
- Full theming: light/dark/system, accent color, presets
- Every plugin has its own settings page — tap it in the Plugins list —
  the same "click the plugin to configure it" model RuneLite uses

**Streaming integrations** *(bring your own API credentials — see
[PLUGIN_GUIDE.md](PLUGIN_GUIDE.md))*
- Spotify: browse/import your playlists, or remote-control playback on a
  Spotify Connect device
- YouTube: search and browse your playlists, or play a video through
  YouTube's own embedded player

**Ecosystem**
- Install community plugins by pasting a GitHub URL — sandboxed, with a
  permission-confirmation dialog before any downloaded code runs
- A plugin crash never takes down playback — every hook runs sandboxed,
  with failures surfaced on a Plugin Health dashboard, not silently
  swallowed or fatal
