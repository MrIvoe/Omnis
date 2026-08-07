/// Repeat mode: off, repeat the whole queue, or repeat the current track.
///
/// Lives here rather than buried in `AppSettings` (where it originated)
/// because `PluginContext`/`AudioEngine` and any plugin working with
/// repeat state (`ShuffleRepeatPlugin`) need to name this type without
/// depending on the app's settings singleton — the same reasoning
/// `HardwareEqBand`/`Playlist` moved here for.
enum RepeatMode { off, all, one }
