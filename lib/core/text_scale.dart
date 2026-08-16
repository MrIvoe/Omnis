/// Clamps a user-chosen app-wide text scale factor to a sane range —
/// spec §58's "app-wide text scaling" gap (item 48): previously only
/// `AppSettings.lyricsTextSize` existed, scoped to just the lyrics
/// view, and a declarative theme's own `ThemeManifest.textScale` is a
/// fixed value an imported theme's *author* sets, not something a user
/// controls. `1.0` is "no change"; below ~0.85 text becomes hard to
/// read, above ~1.5 common layouts (button rows, list tiles) start
/// clipping — the same reasoning `AppSettings.albumArtScale`'s own
/// 0.7-1.4 clamp already applies to a different visual scale.
double clampTextScale(double value) => value.clamp(0.85, 1.5);
